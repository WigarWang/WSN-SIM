clear;

tic

nRepeat = 5;
nTopo   = 7;

networkLifetime_DBR      = zeros(nRepeat, nTopo);
energyConsumption_DBR    = zeros(nRepeat, nTopo);
delayEndToEnd_DBR        = zeros(nRepeat, nTopo);
deliveryRatio_DBR        = zeros(nRepeat, nTopo);

networkLifetime_EEDBR    = zeros(nRepeat, nTopo);
energyConsumption_EEDBR  = zeros(nRepeat, nTopo);
delayEndToEnd_EEDBR      = zeros(nRepeat, nTopo);
deliveryRatio_EEDBR      = zeros(nRepeat, nTopo);

networkLifetime_REPBR    = zeros(nRepeat, nTopo);
energyConsumption_REPBR  = zeros(nRepeat, nTopo);
delayEndToEnd_REPBR      = zeros(nRepeat, nTopo);
deliveryRatio_REPBR      = zeros(nRepeat, nTopo);

networkLifetime_CUSTOM   = zeros(nRepeat, nTopo);
energyConsumption_CUSTOM = zeros(nRepeat, nTopo);
delayEndToEnd_CUSTOM     = zeros(nRepeat, nTopo);
deliveryRatio_CUSTOM     = zeros(nRepeat, nTopo);

networkCreateTime_CUSTOM = zeros(nRepeat, nTopo);

parfor i = 1 : nRepeat
    topo = Topology(100);

    if i < 10
        strIndex = " " + string(i);
    else
        strIndex = string(i);
    end

    for j = 1 : nTopo
        fprintf("[ DBR    ] " + "topology " + strIndex + " nodes " + string(topo.nodeNum));
        proto_DBR = Protocal_DBR(topo);
        proto_DBR.run();
        disp("    → finshed.");
        
        fprintf("[ EEDBR  ] " + "topology " + strIndex + " nodes " + string(topo.nodeNum));
        proto_EEDBR = Protocal_EEDBR(topo);
        proto_EEDBR.run();
        disp("    → finshed.");
        
        fprintf("[ REPBR  ] " + "topology " + strIndex + " nodes " + string(topo.nodeNum));
        proto_REPBR = Protocal_REPBR(topo);
        proto_REPBR.run();
        disp("    → finshed.");

        fprintf("[ CUSTOM ] " + "topology " + strIndex + " nodes " + string(topo.nodeNum));
        proto_CUSTOM = Protocal_CUSTOM2(topo);
%         proto_CUSTOM.calMHC("fieldMhc");
        proto_CUSTOM.calMHC("fast");
        proto_CUSTOM.run();
        disp("    → finshed.");

        topo.addNode(50);

        networkLifetime_DBR(i, j)     = proto_DBR.networkLifetime;
        energyConsumption_DBR(i, j)   = proto_DBR.energyConsumption;
        delayEndToEnd_DBR(i, j)       = proto_DBR.delayEndToEnd;
        deliveryRatio_DBR(i, j)       = proto_DBR.deliveryRatio;

        networkLifetime_EEDBR(i, j)   = proto_EEDBR.networkLifetime;
        energyConsumption_EEDBR(i, j) = proto_EEDBR.energyConsumption;
        delayEndToEnd_EEDBR(i, j)     = proto_EEDBR.delayEndToEnd;
        deliveryRatio_EEDBR(i, j)     = proto_EEDBR.deliveryRatio;
        
        networkLifetime_REPBR(i, j)   = proto_REPBR.networkLifetime;
        energyConsumption_REPBR(i, j) = proto_REPBR.energyConsumption;
        delayEndToEnd_REPBR(i, j)     = proto_REPBR.delayEndToEnd;
        deliveryRatio_REPBR(i, j)     = proto_REPBR.deliveryRatio;

        networkLifetime_CUSTOM(i, j)   = proto_CUSTOM.networkLifetime;
        energyConsumption_CUSTOM(i, j) = proto_CUSTOM.energyConsumption;
        delayEndToEnd_CUSTOM(i, j)     = proto_CUSTOM.delayEndToEnd;
        deliveryRatio_CUSTOM(i, j)     = proto_CUSTOM.deliveryRatio;

%         networkCreateTime_CUSTOM(i, j) = proto_CUSTOM.timeCalculateMHC;
    end
end
disp("--------------------------------------------------------------------");

disp("end-to-end delay");
fprintf("[ DBR    ]  ");
disp(mean(delayEndToEnd_DBR, 'omitnan'));
fprintf("[ EEDBR  ]  ");
disp(mean(delayEndToEnd_EEDBR, 'omitnan'));
fprintf("[ REPBR  ]  ");
disp(mean(delayEndToEnd_REPBR, 'omitnan'));
fprintf("[ CUSTOM ]  ");
disp(mean(delayEndToEnd_CUSTOM, 'omitnan'));
disp("-----------------------------------------------------------");
disp("delivery ratio");
fprintf("[ DBR    ]  ");
disp(mean(deliveryRatio_DBR, 'omitnan'));
fprintf("[ EEDBR  ]  ");
disp(mean(deliveryRatio_EEDBR, 'omitnan'));
fprintf("[ REPBR  ]  ");
disp(mean(deliveryRatio_REPBR, 'omitnan'));
fprintf("[ CUSTOM ]  ");
disp(mean(deliveryRatio_CUSTOM, 'omitnan'));
disp("-----------------------------------------------------------");
disp("energy consumption");
fprintf("[ DBR    ]  ");
disp(mean(energyConsumption_DBR, 'omitnan'));
fprintf("[ EEDBR  ]  ");
disp(mean(energyConsumption_EEDBR, 'omitnan'));
fprintf("[ REPBR  ]  ");
disp(mean(energyConsumption_REPBR, 'omitnan'));
fprintf("[ CUSTOM ]  ");
disp(mean(energyConsumption_CUSTOM, 'omitnan'));
disp("-----------------------------------------------------------");
disp("network lifetime");
fprintf("[ DBR    ]  ");
disp(uint16(mean(networkLifetime_DBR, 'omitnan')));
fprintf("[ EEDBR  ]  ");
disp(uint16(mean(networkLifetime_EEDBR, 'omitnan')));
fprintf("[ REPBR  ]  ");
disp(uint16(mean(networkLifetime_REPBR, 'omitnan')));
fprintf("[ CUSTOM ]  ");
disp(uint16(mean(networkLifetime_CUSTOM, 'omitnan')));
disp("-----------------------------------------------------------");

toc
