classdef Protocal_DBR < Protocal
    properties(Access = public)

    end

    methods(Access = public)
        function obj = Protocal_DBR(argTopo)
            obj@Protocal(argTopo);
            obj.type = "DBR";
            
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
                data          = string(nodeSender.depth);
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

                % [reference] DBR: Depth-Based Routing for Underwater Sensor Networks
                Dp     = str2double(queueCurrent.packet.data);
                Dc     = obj.topology.node(queueCurrent.receiver).depth;
                deltaD = Dp - Dc;
                % Parameter Dth: Depth Threshold
                Dth = 0;
                if deltaD <= Dth
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

                packet = queueCurrent.packet;
                packet.data = string(Dc);

                R     = nodeCurrent.rangeTransmit;
                v0    = nodeCurrent.velocityTransmit;
                tau   = R / v0;
                % Parameter delta
                delta = R;
                
                timeholding = (2 * tau) / delta * (R - (Dp - Dc));
                timesend = timeholding + obj.timer.time;

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
