local n=0;
local function eq(a,b) assert(a==b,tostring(a).." ~= "..tostring(b)) end;
local function test(name,fn) fn();n=n+1;print("PASS WARD_DELIVERY "..name) end;
local function scenario()
    local s=SCENARIO();s.time=210;s.env.TEAM_RADIANT=2;s.env.BOT_MODE_WARD=20;s.bot.x=-197;s.bot.y=-900;
    local p=s.env.require("bots/laning/profile");p.wards_enabled=true;p.ward_phase_enabled=true;p.runtime_enabled=false;
    function s:vision(name) return self.env.require("bots/laning/vision/"..name) end;
    s:vision("config").calibration_only=false;s.env.GetHeightLevel=function() return 3 end;
    s.env.GetNumCouriers=function() return #s.couriers end;s.env.GetCourier=function(i) return s.couriers[i+1] end;
    s.couriers={};s.courierItems={};s.courierMode=4;s.courierDistance=500;s.courierHP=100;s.courierAlive=true;s.courierCalls=0;
    s.env.GetCourierState=function() return s.courierMode end;
    s.env.COURIER_STATE_IDLE=0;s.env.COURIER_STATE_AT_BASE=1;s.env.COURIER_STATE_RETURNING_TO_BASE=4;
    s.env.COURIER_ACTION_TAKE_AND_TRANSFER_ITEMS=6;
    local c={GetPlayerID=function() return 7 end,GetItemInSlot=function(_,slot) return s.courierItems[slot] end,
        IsAlive=function() return s.courierAlive end,GetHealth=function() return s.courierHP end,
        GetMaxHealth=function() return 100 end,DistanceFromFountain=function() return s.courierDistance end};
    s.couriers={c};s.courier=c;
    s.env.PURCHASE_ITEM_SUCCESS=0;s.env.PURCHASE_ITEM_OUT_OF_STOCK=100;
    s.env.GetItemCost=function() return 0 end;s.env.GetItemComponents=function() return {} end;
    s.bot.GetGold=function() return 1000 end;s.bot.SetNextItemPurchaseValue=function() end;
    s.buys={};s.buyResult=0;
    s.bot.ActionImmediate_PurchaseItem=function(_,name) s.buys[#s.buys+1]=name;return s.buyResult end;
    s.bot.ActionImmediate_Courier=function(_,unit,action) eq(unit,c);eq(action,6);s.courierCalls=s.courierCalls+1;return s.courierAccepted end;
    function s:root() local f=assert(loadfile("item_purchase_nevermore.lua"));setfenv(f,self.env);f() end;
    return s;
end;
test("purchase begins at3:30 and8:30 rather than waiting for the planting window",function()
    for _,t in ipairs({210,510}) do local s=scenario();local m=s:vision("supply");s.time=t-1;eq(m.TryPurchase(s.bot),false);
        s.time=t;eq(m.TryPurchase(s.bot),true);eq(s.buys[1],"item_ward_observer");s:advance();eq(m.TryPurchase(s.bot),false);eq(#s.buys,1);
    end;
end);
test("ward in backpack stash courier or active inventory is never bought twice",function()
    for _,where in ipairs({"active","backpack","stash","courier"}) do local s=scenario();local it=s:item("item_ward_observer",where=="backpack" and 6 or (where=="stash" and 9 or 0));
        if where=="courier" then s.items[0]=nil;s.courierItems[0]=it end;
        eq(s:vision("supply").TryPurchase(s.bot),false);eq(#s.buys,0);
    end;
end);
test("stock details distinguish location and fail closed on throwing inventory API",function()
    local s=scenario();local m=s:vision("supply");s:item("item_ward_observer",9);local d=m.StockDetails(s.bot);eq(d.stash,1);eq(d.active,0);eq(d.total,1);
    s.bot.GetItemInSlot=function() error("unavailable") end;eq(m.Stock(s.bot),nil);eq(m.TryPurchase(s.bot),false);
end);
test("actual root reserves a healthy near-base returning courier for the stashed ward",function()
    local s=scenario();s:item("item_ward_observer",9);s:root();s.env.ItemPurchaseThink();eq(s.courierCalls,1);
    assert(table.concat(s.logs,"\n"):find('vision_courier_attempt',1,true));
    s:advance(3.1);s.env.ItemPurchaseThink();eq(s.courierCalls,1);s:advance(7.1);s.env.ItemPurchaseThink();eq(s.courierCalls,2);
end);
test("active deliveries dead far injured and unknown couriers cannot be rerouted",function()
    for _,why in ipairs({"delivering","dead","far","injured","unknown_hp","unknown_distance","unknown_enum"}) do local s=scenario();s:item("item_ward_observer",9);
        if why=="delivering" then s.courierMode=3 elseif why=="dead" then s.courierAlive=false
        elseif why=="far" then s.courierDistance=1201 elseif why=="injured" then s.courierHP=79
        elseif why=="unknown_hp" then s.courier.GetHealth=nil elseif why=="unknown_distance" then s.courier.DistanceFromFountain=nil
        else s.env.COURIER_STATE_RETURNING_TO_BASE=nil end;
        s:root();s.env.ItemPurchaseThink();eq(s.courierCalls,0);
    end;
end);
test("foreign courier and ordinary nonward stash do not get the returning override",function()
    for _,why in ipairs({"foreign","otheritem","already_carried","already_on_courier","outside_schedule"}) do local s=scenario();local it=s:item("item_ward_observer",9);
        if why=="foreign" then s.courier.GetPlayerID=function() return 8 end
        elseif why=="otheritem" then s:item("item_branches",9)
        elseif why=="already_carried" then s:item("item_ward_observer",0)
        elseif why=="already_on_courier" then s.courierItems[0]=it
        else s.time=100 end;
        s:root();s.env.ItemPurchaseThink();eq(s.courierCalls,0);
    end;
end);
test("base and idle courier behavior for ordinary purchases remains unchanged",function()
    for _,state in ipairs({0,1}) do local s=scenario();s.time=100;s.courierMode=state;s:item("item_branches",9);
        s:root();s.env.ItemPurchaseThink();eq(s.courierCalls,1);
    end;
end);
test("rejected courier submission is an attempt and still respects retry cooldown",function()
    local s=scenario();s.courierAccepted=false;s:item("item_ward_observer",9);s:root();s.env.ItemPurchaseThink();eq(s.courierCalls,1);
    local log=table.concat(s.logs,"\n");assert(log:find('"api_rejected":true',1,true));assert(log:find('"outcome":"delivery_unverified"',1,true));
    assert(not log:find('vision_delivery_observed',1,true));s:advance(3.1);s.env.ItemPurchaseThink();eq(s.courierCalls,1);
end);
test("arrival logs only after actual active inventory readback and tracks an overdue stash",function()
    local s=scenario();local it=s:item("item_ward_observer",9);local m=s:vision("supply");m.Observe(s.bot);
    s.items[9]=nil;s.courierItems[0]=it;s:advance(1.1);m.Observe(s.bot);
    assert(not table.concat(s.logs,"\n"):find('vision_delivery_observed',1,true));
    s.courierItems[0]=nil;s.items[0]=it;s:advance(1.1);m.Observe(s.bot);
    local log=table.concat(s.logs,"\n");assert(log:find('vision_delivery_observed',1,true));assert(log:find('"before_window":true',1,true));
    local count=#s.logs;s:advance(1.1);m.Observe(s.bot);eq(#s.logs,count);
end);
test("backpack observer can be equipped before window without moving or placing",function()
    local s=scenario();local ward=s:item("item_ward_observer",6);
    s.bot.ActionImmediate_SwapItems=function(_,a,b) s.items[a],s.items[b]=s.items[b],s.items[a] end;
    eq(s:vision("inventory").Tick(s.bot,s.broker.State(s.bot)),true);eq(s.items[0],ward);
    eq(#s.orders,0);eq(s:vision("schedule").Slot(s.time),nil);
end);
test("unknown purchase result never creates duplicate pending ward orders",function()
    local s=scenario();s.buyResult=nil;local m=s:vision("supply");eq(m.TryPurchase(s.bot),true);
    for _,t in ipairs({211,240,300,330}) do s.time=t;eq(m.TryPurchase(s.bot),false) end;eq(#s.buys,1);
end);
print("WARD_DELIVERY PASSED "..n.." cases (courier attempts are not live delivery guarantees)");
