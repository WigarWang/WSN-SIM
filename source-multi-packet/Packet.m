classdef Packet
    properties(Access = public)
        senderId
        sequenceNumber
        data
    end

    methods(Access = public)
        function obj = Packet(varargin)
            if nargin == 2
                argNode = varargin{1};
                argData = varargin{2};

                obj.senderId = argNode.index;
                % obj.sequenceNumber = matlab.lang.internal.uuid;
                obj.sequenceNumber = generateUUID(1);
                obj.data = argData;
            end
        end
    end
end