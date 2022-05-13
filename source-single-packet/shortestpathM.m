function pathMinTemp = shortestpathM(graph, s, d)
    pathLenMinTemp = inf;
    pathMinTemp = [];
    for i = 1 : length(d)
        pathTemp = shortestpath(graph, s, d(i));
        if length(pathTemp) < pathLenMinTemp && ~isempty(pathTemp)
            pathLenMinTemp = length(pathTemp);
            pathMinTemp = pathTemp;
        end
    end
end
