classdef Protocal_EEDBR < Protocal
    properties(Access = public)

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
                % packet forward list calculate
                data          = obj.findNodeForward(nodeSender);

                packet        = Packet(obj.topology.node(obj.topology.nodeSourceIndex), data);

                nodeSender.holdingInterval = [obj.timer.time, timeSend];
                nodeSender.holdingPacket   = packet;
        
                obj.packetTransmit(nodeSender, nodeReceiver, timeSend, packet);

                % Q1 & Q2 update
                Q1_ = {timeSend, packet};
                nodeSender.Q1 = [nodeSender.Q1; Q1_];
                Q2_ = {packet.senderId, packet.sequenceNumber};
                nodeSender.Q2 = [nodeSender.Q2; Q2_];

            else
                queueCurrentIndex = find(abs(obj.queue.receivetime - obj.timer.time) < 1e-10);
                queueCurrent = obj.queue(queueCurrentIndex(1), :);
                obj.queue(queueCurrentIndex, :) = [];

                nodeCurrentIndex = queueCurrent.receiver;
                nodeCurrent = obj.topology.node(nodeCurrentIndex);
                packetReceived = queueCurrent.packet;

                if ismember(queueCurrent.receiver, obj.topology.nodeSinkIndex)
                    % packet has been transmit to one of the sink nodes
                    queueEnd_ = queueCurrent(:, ["receivetime", "receiver", "packet"]);
                    obj.queueEnd = [obj.queueEnd; queueEnd_];
                    return
                end

                % [reference] An Energy Efficient Localization-Free Routing Protocol for Underwater Wireless Sensor Networks
                list = str2double(split(packetReceived.data));
                list(isnan(list)) = [];

                if ~ismember(nodeCurrentIndex, list)
                    if obj.isMemberPacket(packetReceived, nodeCurrent, "Q1")
                        nodeCurrent.Q1 = obj.packetRemove(packetReceived, nodeCurrent);
                    end
                    ratioDelivery = nodeCurrent.nPacketTransmit / nodeCurrent.nPacketReceive;
                    if ratioDelivery < 0.9
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
                    timeholdingMax = 1;
                    priorityMin = 1;
                    
                    priority = 2^(priorityIndex - 2) * priorityMin;

                    timeholding = (1 - nodeCurrent.energyResidual / nodeCurrent.energyInitial) * timeholdingMax + priority;
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

%                 if obj.timer.time > nodeCurrent.holdingInterval(1) && obj.timer.time < nodeCurrent.holdingInterval(2)
%                     % receive the same packet at holding time
%                     ratioDelivery = nodeCurrent.nPacketTransmit / nodeCurrent.nPacketReceive;
%                     if rand() < ratioDelivery
%                         return
%                     end
%                 end             

                % transmit packet
                nodeSender    = obj.topology.node(nodeCurrentIndex);
                nodeReceiver  = obj.topology.node(successors(obj.topology.route, nodeCurrentIndex));
                % timeSend
                % packet
                
                obj.packetTransmit(nodeSender, nodeReceiver, timesend, packet);

                nodeCurrent.holdingInterval = [obj.timer.time, timesend];
                nodeCurrent.holdingPacket   = packet;
                
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
                    list_ = {receiverIndex(i), nodeReceiver(i).depth, nodeReceiver(i).energyResidual};
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
