classdef Protocal_REPBR < Protocal
    properties(Access = public)
        matTriangleMetric
    end

    methods(Access = public)
        function obj = Protocal_REPBR(argTopo)
            obj@Protocal(argTopo);
            obj.type = "REPBR";
            
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
                % calculate SNR,LQI of network
                obj.topology.calculateSNR();
                obj.topology.calculateLQI();
                
                % calculate triangle metric of network
                obj.matTriangleMetric = sqrt(obj.topology.matSNR.^2 + obj.topology.matLQI.^2);
                for i = 1 : obj.topology.nodeNum
                    obj.matTriangleMetric(i, i) = nan;
                end

                % source node broadcast
                nodeSender    = obj.topology.node(obj.topology.nodeSourceIndex);
                nodeReceiver  = obj.topology.node(neighbors(obj.topology.route, obj.topology.nodeSourceIndex));
                timeSend      = 0;
                
                % update QM
                obj.updateTriangleMetric(nodeSender, 1.2);

                % [reference] A reliable energy-efficient pressure-based routing protocol for underwater wireless sensor network
                data          = obj.findNodeForward(nodeSender);
                packet        = Packet(obj.topology.node(obj.topology.nodeSourceIndex), data);
        
                obj.packetTransmit(nodeSender, nodeReceiver, timeSend, packet);

                % Q1 & Q2 update
                obj.q12Update(nodeSender, timeSend, packet);

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

                % [reference] A reliable energy-efficient pressure-based routing protocol for underwater wireless sensor network
                list = str2double(split(packetReceived.data));
                list(isnan(list)) = [];

                if ~ismember(nodeCurrentIndex, list)
                    if obj.isMemberPacket(packetReceived, nodeCurrent, "Q1")
                        nodeCurrent.Q1 = obj.packetRemove(packetReceived, nodeCurrent);
                    end
                    nodeCurrent.nPacketReceive = nodeCurrent.nPacketReceive - 1;
                    return
                end
                if obj.isMemberPacket(packetReceived, nodeCurrent, "Q2")
                    nodeCurrent.nPacketReceive = nodeCurrent.nPacketReceive - 1;
                    return
                end

                timesend = obj.timer.time;
                
                % update QM
                obj.updateTriangleMetric(nodeCurrent, 1.2);

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
                nodeReceiver  = obj.topology.node(neighbors(obj.topology.route, nodeCurrentIndex));
                % timeSend
                % packet 
        
                obj.packetTransmit(nodeSender, nodeReceiver, timesend + 0.5, packet);
                
                % update current node Q2
                Q2_ = {packet.senderId, packet.sequenceNumber};
                nodeCurrent.Q2 = [nodeCurrent.Q2; Q2_];
                     
            end
        end
    end
    
    methods(Access = protected)
        function list = findNodeForward(obj, nodeSender)
            senderIndex   = nodeSender.index;
            receiverIndex = neighbors(obj.topology.route, senderIndex);
            nodeReceiver  = obj.topology.node(receiverIndex);
            
            list = table('Size', [0, 5], ...
                         'VariableTypes', ["double",   "double",           "double",         "double",          "double"], ...
                         'VariableNames', ["receiver", "triangleMetric",  "energyResidual", "rankLinkQuality", "routeCost"]);

            % avoid forward packet to deeper node
            for i = 1 : length(receiverIndex)
                if nodeReceiver(i).depth < nodeSender.depth
                    triangleMetric = obj.matTriangleMetric(receiverIndex(i), senderIndex);

                    if triangleMetric > 0 && triangleMetric <= 30
                        rankLinkQuality = 1;
                    elseif triangleMetric > 30 && triangleMetric <= 80
                        rankLinkQuality = 2;
                    elseif triangleMetric > 80 && triangleMetric <= 145
                        rankLinkQuality = 3;
                    elseif triangleMetric > 145
                        rankLinkQuality = 4;
                    end

                    routeCost = (1 - nodeReceiver(i).energyResidual / nodeReceiver(i).energyInitial) ...
                                + (1 - triangleMetric / max(max(obj.matTriangleMetric)));

                    list_ = {receiverIndex(i), ...
                             triangleMetric, ...
                             nodeReceiver(i).energyResidual, ...
                             rankLinkQuality, ...
                             routeCost};
                    list = [list; list_];
                end
            end
            list = sortrows(list, 'rankLinkQuality', 'descend');

            % sort list by route cost of forward nodes
            list = sortrows(list, 'routeCost', 'ascend');
            
            if ~isempty(list)
                list = strjoin(string(list.receiver(1)));
            else
                % can't find
                list = "";
            end
        end

        function updateTriangleMetric(obj, sender, k)
            % increase TM for nodes in avaliable path
            for i = 1 : obj.topology.nodeSinkNum
                path = shortestpath(obj.topology.route, sender.index, obj.topology.nodeSinkIndex(i));
                for j = 1 : length(path) - 1
                    obj.matTriangleMetric(path(j), path(j + 1)) = obj.matTriangleMetric(path(j), path(j + 1)) * k;
                    obj.matTriangleMetric(path(j + 1), path(j)) = obj.matTriangleMetric(path(j + 1), path(j)) * k;
                end
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

        function q12Update(~, nodeSender, timesend, packet)
            Q1_ = {timesend, packet};
            nodeSender.Q1 = [nodeSender.Q1; Q1_];

            Q2_ = {packet.senderId, packet.sequenceNumber};
            nodeSender.Q2 = [nodeSender.Q2; Q2_];
        end
    end
    % --------------------------------------------

end