classdef Protocal_EEDBR < Protocal
    properties(Access = public)
        nInfoAcquist = 0

        vecDepth
        vecEnergyResidualPercentage
    end

    properties(Access = protected)
        nPacketTransmit_ = 0
        nPacketReceive_  = 0

        bufferSendtime = 0
        bufferPacket = ""
    end

    methods(Access = public)
        function obj = Protocal_EEDBR(argTopo)
            obj@Protocal(argTopo);
            obj.type = "EEDBR";
            
            obj.topology.node.addprop("Q1");
            obj.topology.node.addprop("Q2");
            for i = 1 : obj.topology.nodeNum
                obj.topology.node(i).Q1 = table('size', [0, 2], ...
                                                'VariableTypes', ["double", "Packet"], ...
                                                'VariableNames', ["sendtime", "packet"]);
                obj.topology.node(i).Q2 = table('size', [0, 2], ...
                                                'VariableTypes', ["double", "string"], ...
                                                'VariableNames', ["sender", "sequence"]);
                % reduce the initial energy of each nodes to speed up
                obj.topology.node(i).energyInitial = obj.topology.node(i).energyInitial / obj.ratioSpeed;
                obj.topology.node(i).energyResidual = obj.topology.node(i).energyResidual / obj.ratioSpeed;
            end
        end
    end

    methods(Access = protected)
        function forwardPacket(obj)
            if obj.timer.time == 0
                % source node broadcast
                nodeSender    = obj.topology.node(obj.topology.nodeSourceIndex);
                nodeReceiver  = obj.topology.node(successors(obj.topology.route, obj.topology.nodeSourceIndex));
                timeSend      = 0;

                % [reference] An Energy Efficient Localization-Free Routing Protocol for Underwater Wireless Sensor Networks
                obj.acquistInfo();
                
                obj.nPacketTransmit = fix(nodeSender.energyInitial / nodeSender.energyConsumptionSourceBroadcast);
            
                for i = 1 : obj.nPacketTransmit
                    data   = obj.findNodeForward(nodeSender);
                    packet = Packet(obj.topology.node(obj.topology.nodeSourceIndex), data); 
                
                    obj.packetTransmit(nodeSender, nodeReceiver, timeSend, packet);
                    
                    % Q1 & Q2 update
                    Q1_ = {timeSend, packet};
                    nodeSender.Q1 = [nodeSender.Q1; Q1_];
                    Q2_ = {packet.senderId, packet.sequenceNumber};
                    nodeSender.Q2 = [nodeSender.Q2; Q2_];

                    timeSend = timeSend + nodeSender.periodPackGenerate;
                end
                
                obj.nInfoAcquist = fix(max(obj.queue.sendtime) / nodeSender.periodInfoAcquist);
                for i = 1 : obj.nInfoAcquist
                    timeInfoAcquist = i * nodeSender.periodInfoAcquist;
                    packet = Packet(nodeSender, "");
                    queue_ = {nan, nan, timeInfoAcquist, nan, packet};
                    obj.queue = [obj.queue; queue_];
                end
                
            else
                queueCurrentIndex = find(abs(obj.queue.receivetime - obj.timer.time) < 1e-10);
                queueCurrent = obj.queue(queueCurrentIndex(1), :);
                obj.queue(queueCurrentIndex, :) = [];
                
                if isnan(queueCurrent.sender)
                    obj.acquistInfo();
                    return
                end

                if mod(queueCurrent.sendtime, obj.topology.node(obj.topology.nodeSourceIndex).periodPackGenerate) == 0 && ...
                   obj.bufferSendtime ~= queueCurrent.sendtime
                    obj.nPacketTransmit_ = obj.nPacketTransmit_ + 1;
                    obj.bufferSendtime = queueCurrent.sendtime;
                end

                nodeCurrentIndex = queueCurrent.receiver;
                nodeCurrent = obj.topology.node(nodeCurrentIndex);
                packetReceived = queueCurrent.packet;

                if ismember(queueCurrent.receiver, obj.topology.nodeSinkIndex)
                    % packet has been transmit to one of the sink nodes
                    queueEnd_ = queueCurrent(:, ["receivetime", "receiver", "packet"]);
                    obj.queueEnd = [obj.queueEnd; queueEnd_];
                    if obj.bufferPacket ~= queueCurrent.packet.sequenceNumber
                        obj.nPacketReceive_ = obj.nPacketReceive_ + 1;
                        obj.bufferPacket = queueCurrent.packet.sequenceNumber;
                    end
                    return
                end

                % [reference] An Energy Efficient Localization-Free Routing Protocol for Underwater Wireless Sensor Networks
                list = str2double(split(packetReceived.data));
                list(isnan(list)) = [];

                if ~ismember(nodeCurrentIndex, list)
                    if obj.isMemberPacket(packetReceived, nodeCurrent, "Q1")
                        nodeCurrent.Q1 = obj.packetRemove(packetReceived, nodeCurrent);
                    end
                    ratioDelivery = obj.nPacketReceive_ / obj.nPacketTransmit_;
                    if rand() > ratioDelivery
                        nodeCurrent.nPacketReceive = nodeCurrent.nPacketReceive - 1;
                    end
                    return
                end
                if obj.isMemberPacket(packetReceived, nodeCurrent, "Q2")
                    nodeCurrent.nPacketReceive = nodeCurrent.nPacketReceive - 1;
                    return
                end
                
                priorityIndex = find(list == nodeCurrentIndex);
                if priorityIndex == 1
                    timeholding = 0;
                else
                    % parameters
                    timeholdingMax = 5;
                    priorityMin = 1;
                    
                    priority = 2^(priorityIndex - 2) * priorityMin;

                    timeholding = (1 - obj.vecEnergyResidualPercentage(nodeCurrentIndex)) * timeholdingMax + priority;
                end

                timesend = timeholding + obj.timer.time;
                
                data   = obj.findNodeForward(nodeCurrent);
                packet = packetReceived;
                packet.data = data;

                if obj.isMemberPacket(packetReceived, nodeCurrent, "Q1")
                    timesendPervious = queueCurrent.sendtime;
                    timesend = min(timesendPervious, timesend);
                else
                    % update current node Q1
                    Q1_ = {timesend, packet}; 
                    nodeCurrent.Q1 = [nodeCurrent.Q1; Q1_];
                end        

                % transmit packet
                nodeSender    = obj.topology.node(nodeCurrentIndex);
                nodeReceiver  = obj.topology.node(successors(obj.topology.route, nodeCurrentIndex));
                % timeSend
                % packet
                
                obj.packetTransmit(nodeSender, nodeReceiver, timesend, packet);
                
                % update current node Q2
                Q2_ = {packet.senderId, packet.sequenceNumber};
                nodeCurrent.Q2 = [nodeCurrent.Q2; Q2_];
            end
        end
    end
    
    methods(Access = protected)
        function list = findNodeForward(obj, nodeSender)
            senderIndex   = nodeSender.index;
            receiverIndex = successors(obj.topology.route, senderIndex);
            nodeReceiver  = obj.topology.node(receiverIndex);
            
            list = table('Size', [0, 3], ...
                         'VariableTypes', ["double",   "double", "double"], ...
                         'VariableNames', ["receiver", "depth",  "energyResidual"]);

            % avoid forward packet to deeper node
            for i = 1 : length(receiverIndex)
                if nodeReceiver(i).depth <= nodeSender.depth
                    list_ = {receiverIndex(i), obj.vecDepth(receiverIndex(i)), obj.vecEnergyResidualPercentage(receiverIndex(i))};
                    list = [list; list_];
                end
            end
            list = sortrows(list,'depth','ascend');

            % sort list by residual energy of forward nodes
            list = sortrows(list,'energyResidual','descend');
            
            if height(list) > 2
                list = strjoin(string(list.receiver(1 : 2)));
            else
                list = strjoin(string(list.receiver));
            end
%             list = strjoin(string(list.receiver));
        end
        
        function acquistInfo(obj)
            % simulate information acquist stage
            % energy consumption
            for i = 1 : obj.topology.nodeNum
                obj.topology.node(i).energyResidual = obj.topology.node(i).energyResidual - ...
                                                        obj.topology.node(i).energyConsumptionTransmit_info - ...
                                                        obj.topology.node(i).energyConsumptionReceive_info * indegree(obj.topology.route, i);
            end
            % information update
            obj.vecDepth = [obj.topology.node.depth]';
            obj.vecEnergyResidualPercentage = [obj.topology.node.energyResidual]' ./ [obj.topology.node.energyInitial]';
        end

        function flag = isMemberPacket(~, packet, node, mem)
            compCounter = 0;
            switch mem
                case "Q1"
                    if isempty(node.Q1)
                        flag = false;
                    else
                        for i = 1 : length(node.Q1.packet)
                            compCounter = compCounter + isequal(packet.sequenceNumber, node.Q1.packet(i).sequenceNumber);
                        end
                        if compCounter > 0
                            flag = true;
                        else
                            flag = false;
                        end
                    end
                case "Q2"
                    if isempty(node.Q2)
                        flag = false;
                    else
                        for i = 1 : length(node.Q2.sequence)
                            compCounter = compCounter + isequal(packet.sequenceNumber, node.Q2.sequence(i));
                        end
                        if compCounter > 0
                            flag = true;
                        else
                            flag = false;
                        end
                    end
            end

        end

        function Q1 = packetRemove(~, argPacket, argNode)
            argNode.Q1(argPacket.sequenceNumber == [argNode.Q1.packet.sequenceNumber], :) = [];
            Q1 = argNode.Q1;
        end

    end
    % --------------------------------------------

end
