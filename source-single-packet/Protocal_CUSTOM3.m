classdef Protocal_CUSTOM3 < Protocal
    properties(Access = public)
        matQualityMetric
        matMHC
        matETX
        matNextHop

        timeCalculateMHC
    end

    methods(Access = public)
        function obj = Protocal_CUSTOM3(argTopo)
            obj@Protocal(argTopo);
            obj.type = "CUSTOM";
            
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
            
            % MHC initialize
            obj.matMHC = inf(obj.topology.nodeNum, 1);
            obj.matMHC(obj.topology.nodeSinkIndex) = 0;

            obj.matNextHop = cell(obj.topology.nodeNum, 1);
        end
    end

    methods(Access = public)
        function calMHC(obj, method)
            switch method
                case "fieldMhc"
                    while(true)
                        obj.forwardPacketMHC();
                        if isempty(obj.queue)
                            obj.timeCalculateMHC = obj.timer.time;
                            % reset timer
                            obj.timer.time = 0;
                            % reset energy
                            for i = 1 : obj.topology.nodeNum
                                obj.topology.node(i).energyResidual  = obj.topology.node(i).energyInitial;
                                obj.topology.node(i).nPacketTransmit = 0;
                                obj.topology.node(i).nPacketReceive  = 0; 
                            end
                            obj.counterCollision = 0;
                            return
                        else
                            dtime = min(obj.queue.receivetime - obj.timer.time);
                            % step time forward
                            obj.timer.step(dtime);
                        end
                    end
                case "fast"
                    for i = 1 : obj.topology.nodeNum
                        pathMin = shortestpathM(obj.topology.route, i, obj.topology.nodeSinkIndex);
                        if isempty(pathMin)
                            obj.matMHC(i) = inf;
                        else
                            obj.matMHC(i) = length(pathMin) - 1;
                        end               
                    end
            end
        end
    end

    methods(Access = protected)
        function forwardPacket(obj)
            if obj.timer.time == 0
                % calculate SNR,LQI of network
                obj.topology.calculateRSSI();
                obj.topology.calculateLQI();
                
                % calculate link quality metric of network
                % parameter lambda yita
                lambda = 1;
                yita   = 1;
                obj.matQualityMetric = (1 - obj.topology.matRSSI ./ max(obj.topology.matRSSI(:))).^lambda ...
                                         + (obj.topology.matLQI ./ max(obj.topology.matLQI(:))).^yita; 
                     
                % calculate ETX
                obj.calculateETX();

                % source node broadcast
                nodeSender    = obj.topology.node(obj.topology.nodeSourceIndex);
                nodeReceiver  = obj.topology.node(successors(obj.topology.route, obj.topology.nodeSourceIndex));
                timeSend      = 0;

                % update QM
                obj.updateQualityMetric(nodeSender, 1.2);

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
                    % the current node is not a candidate forwarding node
                    if obj.isMemberPacket(packetReceived, nodeCurrent, "Q1")
                        % clear all forwardd task
                        nodeCurrent.Q1 = obj.packetRemove(packetReceived, nodeCurrent);
                    end
                    % drop packet
                    nodeCurrent.nPacketReceive = nodeCurrent.nPacketReceive - 1;
                    return
                end
                if obj.isMemberPacket(packetReceived, nodeCurrent, "Q2")
                    % the same packet has been forwarded
                    % drop packet
                    nodeCurrent.nPacketReceive = nodeCurrent.nPacketReceive - 1;
                    return
                end

                timesend = obj.timer.time;

                data   = obj.findNodeForward(nodeCurrent);
                packet = packetReceived;
                packet.data = data;

                if obj.isMemberPacket(packetReceived, nodeCurrent, "Q1")
                    % Select the earliest time for forwarding the same packet
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

        function forwardPacketMHC(obj)
            if obj.timer.time == 0
                % sink nodes broadcast
                nodeSenderIndex = [];
                for i = 1 : obj.topology.nodeSinkNum
                    obj.matMHC(successors(obj.topology.route, obj.topology.nodeSinkIndex(i))) = 1;
                    nodeSenderIndex = [nodeSenderIndex; predecessors(obj.topology.route, obj.topology.nodeSinkIndex(i))];
                end
                nodeSenderIndex = unique(nodeSenderIndex);

                for i = nodeSenderIndex'
                    nodeSender    = obj.topology.node(i);
                    nodeReceiver  = obj.topology.node(predecessors(obj.topology.route, i));
                    timeSend      = 0;
                    data          = "1";
                    packet        = Packet(obj.topology.node(i), data);
            
                    obj.packetTransmit(nodeSender, nodeReceiver, timeSend, packet);
                end
            else
                queueCurrentIndex = find(abs(obj.queue.receivetime - obj.timer.time) < 1e-10);
                queueCurrent = obj.queue(queueCurrentIndex(1), :);
                obj.queue(queueCurrentIndex, :) = [];

                nodeCurrentIndex = queueCurrent.receiver;
                nodeCurrent = obj.topology.node(nodeCurrentIndex);
                packetReceived = queueCurrent.packet;
                packetMHC = str2double(packetReceived.data);
                packetSender = packetReceived.senderId;

                if packetMHC + 1 < obj.matMHC(nodeCurrentIndex)
                    obj.matNextHop{nodeCurrentIndex} = [];
                    obj.matMHC(nodeCurrentIndex) = packetMHC + 1;
                    obj.matNextHop{nodeCurrentIndex} = [obj.matNextHop{nodeCurrentIndex}, packetSender];
                    obj.matNextHop{nodeCurrentIndex} = unique(obj.matNextHop{nodeCurrentIndex});
                elseif packetMHC + 1 == obj.matMHC(nodeCurrentIndex)
                    obj.matNextHop{nodeCurrentIndex} = [obj.matNextHop{nodeCurrentIndex}, packetSender];
                    obj.matNextHop{nodeCurrentIndex} = unique(obj.matNextHop{nodeCurrentIndex});
                elseif packetMHC + 1 > obj.matMHC(nodeCurrentIndex)
                    return
                end

                nodeSender   = nodeCurrent;
                nodeReceiver = obj.topology.node(predecessors(obj.topology.route, nodeCurrentIndex));
                timeSend     = obj.timer.time;
                data         = string(obj.matMHC(nodeCurrentIndex));
                packet       = Packet(nodeSender, data);

                obj.packetTransmit(nodeSender, nodeReceiver, timeSend, packet);

            end
        end
    end
    
    methods(Access = protected)
        function list = findNodeForward(obj, nodeSender)
            senderIndex   = nodeSender.index;
            receiverIndex = successors(obj.topology.route, senderIndex);
            nodeReceiver  = obj.topology.node(receiverIndex);
            
            % initialize the list of candidate forwarding nodes
            list = table('Size', [0, 5], ...
                         'VariableTypes', ["double",   "double",        "double",         "double",    "double"], ...
                         'VariableNames', ["receiver", "qualityMetric", "energyResidual", "hopNumber", "routeUtility"]);
            matMHC_ = obj.matMHC;
            matMHC_(isinf(matMHC_)) = [];
            MHCmax = max(matMHC_);

            for i = 1 : length(receiverIndex)
                if nodeReceiver(i).depth < nodeSender.depth
                    % avoid forward packet to deeper node
                    qualityMetric = obj.matQualityMetric(receiverIndex(i), senderIndex);
                    hopNumber = obj.matMHC(senderIndex);
                    ETX = obj.matETX(senderIndex, receiverIndex(i));
                    % parameter α β γ
                    alpha = 0.2;
                    beta  = 0.1;
                    gamma = 0.7;
                    routeUtility =  (alpha * MHCmax / hopNumber ...
                                + beta  * nodeReceiver(i).energyResidual / nodeReceiver(i).energyInitial ...
                                + gamma * qualityMetric) *  (1 / ETX);

                    list_ = {receiverIndex(i), ...
                             qualityMetric, ...
                             nodeReceiver(i).energyResidual, ...
                             hopNumber, ...
                             routeUtility};
                    list = [list; list_];
                end
            end
            
            % sort list by route cost of forward nodes
            list = sortrows(list, 'routeUtility', 'descend');
            
            if ~isempty(list)
                list = string(list.receiver(1));
            else
                % can't find
                list = "";
            end
        end
        
        function calculateETX(obj)
            pathLenMinTemp = inf;
            for i = 1 : obj.topology.nodeSinkNum
                pathTemp = shortestpath(obj.topology.route, obj.topology.nodeSourceIndex, obj.topology.nodeSinkIndex(i));
                if length(pathTemp) < pathLenMinTemp && ~isempty(pathTemp)
                    pathLenMinTemp = length(pathTemp);
                    pathMinTemp = pathTemp;
                end
            end
            
            % simulation: the best route from souce to sink node will gain ETX = 1.
            obj.matETX = full(obj.topology.route.adjacency);
            indexAdj = find(obj.matETX == 1);
            obj.matETX(indexAdj) = 1 ./ ((0.7 * rand(length(indexAdj), 1)) .* (0.7 * rand(length(indexAdj), 1)));
            for i = 1 : pathLenMinTemp - 1
                obj.matETX(pathMinTemp(i), pathMinTemp(i + 1)) = 1;
            end
        end

        function updateQualityMetric(obj, sender, k)
            % Increase QM for nodes in avaliable path
            % Simulate information acquisition phase
            for i = 1 : obj.topology.nodeSinkNum
                path = shortestpath(obj.topology.route, sender.index, obj.topology.nodeSinkIndex(i));
                for j = 1 : length(path) - 1
                    obj.matQualityMetric(path(j), path(j + 1)) = obj.matQualityMetric(path(j), path(j + 1)) * k;
                    obj.matQualityMetric(path(j + 1), path(j)) = obj.matQualityMetric(path(j + 1), path(j)) * k;
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
