classdef Topology < matlab.mixin.Copyable
    % class of underwater wireless sensor network topolgy
    
    properties(Access = public)
        node
        nodeNum
        nodeRange

        nodeSourceIndex
        nodeSourceNum

        nodeSinkIndex
        nodeSinkNum

        nodeUnderwaterIndex
        nodeUnderwaterNum

        route

        matDistance
        matSNR
        matLQI
        matRSSI
    end

    properties(Access = private)
        pos
        
        matWeight
        matAdjacent
    end

    methods(Access = public)
        function obj = Topology(argNodeNum)
            obj.nodeRange = [1250, 1250, 1250];
            
            % Calculate the number of sink nodes, underwater nodes based on
            % the total number of nodes in the network.
            % The number of source node still choose 1.
            obj.nodeNum = argNodeNum;
            obj.nodeSinkNum = round(0.4408 * obj.nodeNum^0.4819); 
            obj.nodeUnderwaterNum = obj.nodeNum - obj.nodeSinkNum;
            obj.nodeSourceNum = 1;

            flagTopoConn = false;

            % Create the network until there is at least one continuous 
            % upward route from the source node to any sink node.
            while(true)
                obj.createNode();
                obj.calculateRoute();
            
                % check topology
                for i = 1 : obj.nodeSinkNum
                    path = shortestpath(obj.route, obj.nodeSourceIndex, obj.nodeSinkIndex(i));
                    if ~isempty(path)
                        dPath = diff([obj.node(path).depth]);
                        if sum(dPath < 0) == length(dPath)
                            flagTopoConn = true;
                            break
                        end
                    end
                end
            
                if flagTopoConn
                    break
                end
            end

            % clear isolate terminate nodes
            while(true)
                matDegree = outdegree(obj.route);
                indexNodeUnlink = find(matDegree == 0);
                indexNodeUnlink(ismember(indexNodeUnlink, obj.nodeSinkIndex)) = [];
                if sum(indegree(obj.route, indexNodeUnlink)) == 0 && sum(outdegree(obj.route, indexNodeUnlink)) == 0
                    break
                end
                for i = indexNodeUnlink'
                    indexEdgeUnlink = findedge(obj.route, predecessors(obj.route, i), i);
                    obj.route = rmedge(obj.route, indexEdgeUnlink);
                end
            end
            
        end
        
        % Add new nodes based on current topolgy
        function addNode(obj, nodeNumAdd)
            % add sink nodes
            nodeSinkNumAdd = round(0.4408 * (obj.nodeNum + nodeNumAdd)^0.4819) - obj.nodeSinkNum;       
            for i = 1 : nodeSinkNumAdd
                obj.node(end + 1) = Node("sink");
                obj.node(end).index = length(obj.node); 
            end
            
            % add underwater nodes
            for i = 1 : nodeNumAdd - nodeSinkNumAdd
                obj.node(end + 1) = Node("underwater");
                obj.node(end).index = length(obj.node); 
            end
            
            % update toplogy info of node number
            obj.nodeNum           = obj.nodeNum + nodeNumAdd;
            obj.nodeSinkNum       = obj.nodeSinkNum + nodeSinkNumAdd;
            obj.nodeUnderwaterNum = obj.nodeNum - obj.nodeSinkNum;

            % sort node by depth
            obj.nodeSort();
            
            % update topology info of node index
            obj.nodeSinkIndex = (1 : obj.nodeSinkNum)';
            obj.nodeUnderwaterIndex = (obj.nodeSinkNum + 1 : obj.nodeNum)';

            % select the deepest node as source node
%             [~, obj.nodeSourceIndex] = max(obj.pos(:, 3));
%             obj.node(obj.nodeSourceIndex).isSource = true;
            obj.nodeSourceIndex = find([obj.node.isSource] == true);

            % update route
            obj.calculateRoute();

            % clear isolate terminate nodes
            while(true)
                matDegree = outdegree(obj.route);
                indexNodeUnlink = find(matDegree == 0);
                indexNodeUnlink(ismember(indexNodeUnlink, obj.nodeSinkIndex)) = [];
                if sum(indegree(obj.route, indexNodeUnlink)) == 0 && sum(outdegree(obj.route, indexNodeUnlink)) == 0
                    break
                end
                for i = indexNodeUnlink'
                    indexEdgeUnlink = findedge(obj.route, predecessors(obj.route, i), i);
                    obj.route = rmedge(obj.route, indexEdgeUnlink);
                end
            end
        end

        function calculateSNR(obj)
            f = repmat([obj.node.frequency], [obj.nodeNum, 1]);
            N_dB = 110 - 18 * log10(f);
            A_dB = 32.44 + 20 * log10(obj.matDistance) + 10 * log10(f);
            
            phi = 0.8;
            P_dB = repmat([obj.node.powerConsumptionTransmit], [obj.nodeNum, 1]);
            P_dB = 10 * log10(P_dB) + 172 / phi;

            Df_dB = 10 * log10(f / 10);

            obj.matSNR = P_dB - A_dB - N_dB - Df_dB;

            for i = 1 : obj.nodeNum
                obj.matSNR(i, i) = nan;
            end
        end

        function calculateLQI(obj)
            f = repmat([obj.node.frequency], [obj.nodeNum, 1]);
            
            A_dB = 32.44 + 20 * log10(obj.matDistance) + 10 * log10(f);

            phi = 1;
            P_dB = repmat([obj.node.powerConsumptionTransmit], [obj.nodeNum, 1]);
            P_dB = 10 * log10(P_dB) + 172 / phi;

            RSSI = (P_dB - A_dB) ./ P_dB;

            obj.matLQI = (10 * RSSI + 81) * 255 / 91;

            for i = 1 : obj.nodeNum
                obj.matLQI(i, i) = nan;
            end
        end

        function calculateRSSI(obj)
            f = repmat([obj.node.frequency], [obj.nodeNum, 1]);
            
            A_dB = 32.44 + 20 * log10(obj.matDistance) + 10 * log10(f);

            phi = 0.8;
            P_dB = repmat([obj.node.powerConsumptionTransmit], [obj.nodeNum, 1]);
            P_dB = 10 * log10(P_dB) + 172 / phi;

            obj.matRSSI = P_dB - A_dB;

            for i = 1 : obj.nodeNum
                obj.matRSSI(i, i) = nan;
            end
        end

        function plot(obj)
            figure("Name", "Network Topolgy");
            hold("on");
            grid("on");
            
            xlim([0, obj.nodeRange(1)]);
            ylim([0, obj.nodeRange(2)]);
            zlim([-obj.nodeRange(3), 0]);
            
            CustomColormap = zeros(256, 3);
            CustomColormap(1  , :) = [1 0 0];
            CustomColormap(256, :) = [0 0 1];
            
            nodeColor = [2 * ones(obj.nodeSinkNum, 1); ...
                         ones(obj.nodeUnderwaterNum - obj.nodeSourceNum, 1); ...
                         zeros(obj.nodeSourceNum, 1)];

            plot(obj.route, "XData", obj.pos(:, 1), ...
                            "YData", obj.pos(:, 2), ...
                            "ZData", -obj.pos(:, 3), ...
                            "EdgeLabel", obj.route.Edges.Weight, ...
                            "LineWidth", 1, ...
                            "NodeCData", nodeColor, ...
                            "EdgeFontSize", 6, ...
                            "EdgeAlpha", 0.3, ...
                            "EdgeColor", "k");
            handleAxe = gca;
            handleAxe.Colormap = CustomColormap;
        end
    end

    methods(Access = public)
        function createNode(obj)
            % just for pre-request space, make no sense
            obj.node = repmat(Node("underwater"), [obj.nodeNum, 1]);
            % create nodes
            for i = 1 : obj.nodeNum
                if i <= obj.nodeSinkNum 
                    obj.node(i) = Node("sink");
                else
                    obj.node(i) = Node("underwater");
                end
                obj.node(i).index = i;
            end
            
            % sort node by depth
            obj.nodeSort();

            obj.nodeSinkIndex = (1 : obj.nodeSinkNum)';
            obj.nodeUnderwaterIndex = (obj.nodeSinkNum + 1 : obj.nodeNum)';

            % select the deepest node as source node
            [~, obj.nodeSourceIndex] = max(obj.pos(:, 3));
            obj.node(obj.nodeSourceIndex).isSource = true;
        end

        function calculateRoute(obj)
            obj.matDistance = squareform(pdist(obj.pos));
            
            range = obj.node(1).rangeTransmit;
            
            obj.matAdjacent = zeros(obj.nodeNum);
            obj.matAdjacent(obj.matDistance <= range & obj.matDistance ~= 0) = 1;
            
            obj.matWeight = zeros(obj.nodeNum);
            for i = 1 : obj.nodeNum
                for j = 1 : obj.nodeNum
                    if obj.matDistance(i, j) <= range && obj.matDistance(i, j) > 0 && obj.node(i).depth > obj.node(j).depth
                        obj.matWeight(i, j) = obj.matDistance(i, j);
                    end
                end
            end

            obj.route = digraph(obj.matWeight);
        end

        function nodeSort(obj)
            obj.pos = reshape([obj.node.position], [3, obj.nodeNum])';
            
            [~, indexSort] = sort(obj.pos(:, 3), "ascend");
            
            % reindex
            for i = 1 : obj.nodeNum
                obj.node(indexSort(i)).index = i;
            end
            
            % sort nodes in ascend
            node_ = obj.node;
            for i = 1 : obj.nodeNum
                node_(obj.node(i).index) = obj.node(i);
            end
            
            % update
            obj.node = node_;
            obj.pos = reshape([obj.node.position], [3, obj.nodeNum])';

        end
    end

    methods(Access = protected)
        function cp = copyElement(obj)
             % Shallow copy object
             cp = copyElement@matlab.mixin.Copyable(obj);
             % Get handle from obj.node
             hobj = obj.node;
             % Copy default object
             new_hobj = copy(hobj);
             % Assign the new object to property
             cp.node = new_hobj;
        end
    end

end
