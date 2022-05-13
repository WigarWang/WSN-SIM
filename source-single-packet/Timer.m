classdef Timer < handle
    properties(Access = public)
        time = 0;
    end

    methods(Access = public)
        function step(obj, dTime)
            obj.time = obj.time + dTime;
        end
    end
end