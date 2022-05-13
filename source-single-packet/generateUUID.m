function uuid = generateUUID(num)
    str=['a','b','c','d','e','f','g','h','i','j','k','l','m','n','o','p','q','r','s','t','u',...
        'v','w','x','y','z','0','1','2','3','4','5','6','7','8','9'];

    for j=1:num
        for i=1:36
            if i==9||i==14||i==19||i==24
                uuid1(i)='-';
            else
                y=unidrnd(36,1);       
                uuid1(i)=str(y);
            end    
        end
        uuid(j,1)=convertCharsToStrings(uuid1) ;   %将char类型转换为string
    end

    uuid = unique(uuid);
end