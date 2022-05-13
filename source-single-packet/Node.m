classdef Node < dynamicprops & matlab.mixin.Copyable
    % class of underwater wireless sensor network nodes

    properties(Access = public)
        type
        index
        isSource

        position
        depth
        
        energyInitial  = 100
        energyResidual = 100
        
        powerConsumptionTransmit = 2
        powerConsumptionReceive  = 0.75
        powerConsumptionListen   = 0.0008

        periodPackGenerate = 15
        periodInfoAcquist  = 100

        packetSize = 64 % Byte
        bandwidth  = 1e4
        frequency  = 2e4
        energyConsumptionTransmit
        energyConsumptionReceive
        dTimeTRX 

        rangeTransmit = 250

        rangePosition = [1250 1250 1250]

        velocityTransmit = 1.5e3

        nPacketTransmit = 0
        nPacketReceive  = 0

        holdingInterval = [0, 0]
        holdingPacket
    end

    methods(Access = public)
        function obj = Node(argType)
            obj.type = argType;
            switch obj.type
                case "underwater"
                    obj.position = [fix(obj.rangePosition(1) * rand()), ...
                                   fix(obj.rangePosition(2) * rand()), ...
                                   fix(obj.rangePosition(3) * rand())];
                    obj.depth = obj.position(3);
                case "sink"
                    obj.rangePosition = [obj.rangePosition(1:2), 0];
                    obj.position = [fix(obj.rangePosition(1) * rand()), ...
                                   fix(obj.rangePosition(2) * rand()), ...
                                   0];
                    obj.depth = 0;
            end
            obj.isSource = false;
            
            % MAC 802.11
            % TX: RTS(24Byte) DATA(frame + 34Byte) 
		    % RX：CTS(24Byte) ACK(20Byte)
            dTimeTX = (24 + 34 + obj.packetSize) * 8 / obj.bandwidth;
            dTimeRX = (24 + 20) * 8 / obj.bandwidth;
            obj.dTimeTRX = dTimeTX + dTimeRX;

            obj.energyConsumptionTransmit = dTimeTX * obj.powerConsumptionTransmit + dTimeRX * obj.powerConsumptionReceive;
            obj.energyConsumptionReceive  = dTimeRX * obj.powerConsumptionTransmit + dTimeTX * obj.powerConsumptionReceive;
        end
    end
    
end