classdef Protocal < handle
    
    properties(Access = public)
        type
        queue
        queueEnd
        timer
        topology

        networkLifetime   = 0
        energyConsumption = 0
        delayEndToEnd     = 0
        deliveryRatio     = 0

        counterCollision = 0
    end
    
    properties(Access = protected)
        nPacketTransmit = 0
        nPacketReceive  = 0

        flagEnd = false

        ratioSpeed = 10;
    end

    methods(Access = public)
        function obj = Protocal(argTopo)
            obj.topology = copy(argTopo);
            obj.timer = Timer;
            obj.queue = table('Size', [0, 5], ...
                              'VariableTypes', ["double", "double", "double", "double", "Packet"], ...
                              'VariableNames', ["sendtime", "sender", "receivetime", "receiver", "packet"]);

            obj.queueEnd = table('Size', [0, 3], ...
                                 'VariableTypes', ["double", "double", "Packet"], ...
                                 'VariableNames', ["receivetime", "receiver", "packet"]);
        end
        
        function run(obj)
            while(true)
                obj.forwardPacket();

                if isempty(obj.queue) || obj.flagEnd
                    % statistical result
                    if isempty(obj.queueEnd)
                        % no packet receive at any sink nodes 
                        obj.energyConsumption = nan;
                        obj.delayEndToEnd = nan;
                        obj.networkLifetime = nan;
                        obj.deliveryRatio = nan;
                    else                        
                        % Network lifetime is defined as the first time of node out of energy.
                        obj.networkLifetime = obj.timer.time * obj.ratioSpeed;
                        
                        obj.nPacketTransmit = obj.nPacketTransmit - height(obj.queue(obj.queue.sender == obj.topology.nodeSourceIndex, :)) / length(successors(obj.topology.route, obj.topology.nodeSourceIndex));
                        
                        % the number of different packets received
                        packetSeq = unique([obj.queueEnd.packet.sequenceNumber]);
                        obj.nPacketReceive = length(packetSeq);
                        
                        % the energy consumption per packet received
                        obj.energyConsumption = sum([obj.topology.node.energyInitial] - [obj.topology.node.energyResidual]) / obj.nPacketReceive; 

                        % Consider the ratio of each node
%                         obj.deliveryRatio = sum([obj.topology.node.nPacketTransmit]) / sum([obj.topology.node.nPacketReceive]);
                        obj.deliveryRatio = obj.nPacketReceive / obj.nPacketTransmit;

                        % End-to-end delay is defined as the received time of the first packet.
                        % Add delay correction of collision due to increased network density.
                        timeFirstReceive = nan(obj.nPacketReceive, 1);
                        for i = 1 : obj.nPacketReceive
                            tempIndex = find([obj.queueEnd.packet.sequenceNumber] == packetSeq(i));
                            timeFirstReceive(i) = obj.queueEnd.receivetime(tempIndex(1));
                        end
                        timeFirstReceive = sort(timeFirstReceive, "ascend");
                        obj.delayEndToEnd = mean(timeFirstReceive - (0 : obj.nPacketReceive - 1)' * obj.topology.node(obj.topology.nodeSourceIndex).periodPackGenerate) + log(obj.counterCollision + 1) * 2 + log(obj.topology.nodeNum - 99) * 1.5;

                    end

                    return
                else
                    dtime = min(obj.queue.receivetime - obj.timer.time);
                    
                    % energy consumption of idle listenning
                    for i = 1 : obj.topology.nodeNum
                        obj.topology.node(i).energyResidual = obj.topology.node(i).energyResidual ...
                                                                - dtime * obj.topology.node(i).powerConsumptionListen;
                    end
                    
                    % forward time
                    obj.timer.step(dtime);
                end
            end

        end

    end

    methods(Access = protected)
        forwardPacket(obj);
    end
    
    methods(Access = protected)
        function packetTransmit(obj, nodeSender, nodeReceiver, sendTime, packet)
            receiverNum   = length(nodeReceiver);
            receiverIndex = [nodeReceiver.index]';
            senderIndex   = nodeSender.index;
            
            % MAC protocal: 802.11 DYNAV
            receiveTime = sendTime + ...
                            obj.topology.matDistance(senderIndex, receiverIndex) / nodeSender.velocityTransmit * 4 + ...
                            nodeSender.dTimeTRX + ...
                            [nodeReceiver.dTimeTRX];

            % packet transmit
            queue_ = cell(receiverNum, 5);
            for i = 1 : receiverNum
                queue_(i, :) = {sendTime, senderIndex, receiveTime(i), receiverIndex(i), packet};
            end
            obj.queue = [obj.queue; queue_];

            % collision manage
            obj.queue = sortrows(obj.queue, 'receivetime', 'ascend');
            for receiverQueue = unique(obj.queue.receiver)'
                line = find(obj.queue.receiver == receiverQueue);
                interval = diff(obj.queue.receivetime(line));
                if isempty(interval)
                    % only one packet will be receive for current node
                    continue
                else
                    for i = 1 : length(interval)     
                        if interval(i) < obj.topology.node(receiverQueue).dTimeTRX
                            obj.counterCollision = obj.counterCollision + 1;
                            % two receive time collide, receive time shift
                            timeShift = obj.topology.node(receiverQueue).dTimeTRX - interval(i);
                            obj.queue.receivetime(line(i+1 : end)) = obj.queue.receivetime(line(i+1 : end)) + timeShift;
                        end
                    end
                end
            end

            % energy consume: MAC protocal 802.11-DYNAV
            nodeSender.energyResidual = nodeSender.energyResidual - nodeSender.energyConsumptionTransmit ...
                                                                  + nodeSender.powerConsumptionListen * nodeSender.dTimeTRX;
            for i = 1 : receiverNum
                nodeReceiver(i).energyResidual = nodeReceiver(i).energyResidual - nodeReceiver(i).energyConsumptionReceive ...
                                                                                + nodeReceiver(i).powerConsumptionListen * nodeReceiver(i).dTimeTRX;
            end
            
            % energy check. If any node run out of energy, simulation ternimate
            energyRes = [obj.topology.node.energyResidual];
            energyRes(obj.topology.nodeSourceIndex) = [];
            if sum(energyRes > 0) < obj.topology.nodeNum - 1
                obj.flagEnd = true;
            end

            % packet number count
            nodeSender.nPacketTransmit = nodeSender.nPacketTransmit + 1;
            for i = 1 : receiverNum
                nodeReceiver(i).nPacketReceive = nodeReceiver(i).nPacketReceive + 1;
            end
            if senderIndex == obj.topology.nodeSourceIndex
                nodeSender.nPacketReceive = 1;
            end
            for i = 1 : length(obj.topology.nodeSinkNum)
                obj.topology.node(obj.topology.nodeSinkIndex(i)).nPacketTransmit = 1;
            end

        end
    end

end
