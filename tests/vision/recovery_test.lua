local n=0;
local function eq(a,b) assert(a==b,tostring(a).." ~= "..tostring(b)) end;
local function test(name,fn) fn();n=n+1;print("PASS WARD_RECOVERY "..name) end;
local function scenario()
    local s=SCENARIO();s.env.TEAM_RADIANT=2;s.env.BOT_MODE_WARD=20;s.time=45;s.bot.x=-197;s.bot.y=-900;
    local p=s.env.require("bots/laning/profile");p.wards_enabled=true;p.ward_phase_enabled=true;p.runtime_enabled=false;
    function s:v(name) return self.env.require("bots/laning/vision/"..name) end;
    s.state=s.broker.State(s.bot);s.vconfig=s:v("config");s.vconfig.calibration_only=false;
    s.env.GetNumCouriers=function() return 0 end;s.env.GetHeightLevel=function() return 3 end;
    s.shop=2;s.env.GetItemStockCount=function() s.shopReads=(s.shopReads or 0)+1;return s.shop end;
    s.env.GetItemCost=function() return 0 end;s.bot.GetGold=function() return 1000 end;
    s.env.PURCHASE_ITEM_SUCCESS=0;s.buys={};
    s.bot.ActionImmediate_PurchaseItem=function(_,name) s.buys[#s.buys+1]=name;return s.buyResult or 0 end;
    s.recovery=s:v("recovery");s.supply=s:v("supply");s.schedule=s:v("schedule");s.phase=s:v("phase");
    function s:check(t) self.time=t;self.recovery.Poll(self.bot,self.state) end;
    function s:plant(t)
        self.time=t;assert(self.phase.GetDesire(self.bot)>0);self.mode=20;self.phase.Start(self.bot);self.phase.Think(self.bot);
        assert(self.state.ward_pending);self:advance();self:mod("wards").Poll(self.bot,self.state);self.phase.Holds(self.bot,self.state);self.mode=1;
    end;
    return s;
end;
test("check is read-only once per45s bucket and never invents a purchase",function()
    local s=scenario();s:check(44.99);eq(s.state.vision_checked_minute,nil);s:check(45);
    for _,t in ipairs({45,45.1,46,59.9,60,104.99}) do s:check(t) end;
    eq(s.shopReads,1);eq(#s.buys,0);eq(#s.orders,0);eq(s.state.vision_recovery_purchase.window.start,60);
    s:check(105);eq(s.shopReads,2);
end);
test("missing observer is ordered once then only carried inventory opens recovery",function()
    local s=scenario();s:check(45);eq(s.supply.TryPurchase(s.bot),true);eq(#s.buys,1);
    s:item("item_ward_observer",9);s:check(105);eq(s.state.vision_recovery,nil);eq(s.supply.TryPurchase(s.bot),false);
    s.items[0]=s.items[9];s.items[9]=nil;s:check(165);eq(s.state.vision_recovery.start,180);eq(#s.buys,1);
    s:plant(180);assert(s.state.vision_completed['recovery:180']);eq(s.phase.GetDesire(s.bot),0);
end);
test("no stock defers exactly to next45 even if stock returns earlier",function()
    local s=scenario();s.shop=0;s:check(45);eq(s.supply.TryPurchase(s.bot),false);eq(#s.buys,0);
    s.shop=2;s:check(60);eq(s.supply.TryPurchase(s.bot),false);
    s:check(105);eq(s.supply.TryPurchase(s.bot),true);eq(#s.buys,1);
end);
test("primary prefetch also defers stock failures without blocking ordinary queue",function()
    local s=scenario();s.time=210;s.shop=0;eq(s.supply.TryPurchase(s.bot),false);s.shop=2;
    s.time=211;eq(s.supply.TryPurchase(s.bot),false);s.time=224.99;eq(s.supply.TryPurchase(s.bot),false);
    s.time=225;eq(s.supply.TryPurchase(s.bot),true);eq(#s.buys,1);
end);
test("unknown negative unaffordable and throwing stock queries fail closed",function()
    for _,kind in ipairs({"nil","negative","throw","gold"}) do local s=scenario();
        if kind=="nil" then s.shop=nil elseif kind=="negative" then s.shop=-1
        elseif kind=="throw" then s.env.GetItemStockCount=function() error("unknown") end
        else s.env.GetItemCost=function() return 10 end;s.bot.GetGold=function() return 0 end end;
        s:check(45);eq(s.supply.TryPurchase(s.bot),false);eq(#s.buys,0);eq(s.state.vision_recovery,nil);
    end;
end);
test("known purchase failure is retried next45 not next frame",function()
    local s=scenario();s.buyResult=7;s:check(45);eq(s.supply.TryPurchase(s.bot),true);s.buyResult=0;
    s:check(60);eq(s.supply.TryPurchase(s.bot),false);s:check(105);eq(s.supply.TryPurchase(s.bot),true);eq(#s.buys,2);
end);
test("pending unknown purchase remains guarded across minute checks",function()
    local s=scenario();s.bot.ActionImmediate_PurchaseItem=function() s.buys[#s.buys+1]='observer';return nil end;
    s:check(45);eq(s.supply.TryPurchase(s.bot),true);s:check(105);eq(s.supply.TryPurchase(s.bot),false);eq(#s.buys,1);
end);
test("existing coverage suppresses recovery but never primary refresh",function()
    local s=scenario();local w=s.unit("npc_dota_observer_wards",2,-216.73818969727,-990.77404785156);s.wards={w};
    s:item("item_ward_observer",0);s:check(285);eq(s.state.vision_recovery,nil);s:plant(300);
    eq(s.state.vision_done_slot,1);eq(#s.orders,1);s:check(345);eq(s.state.vision_recovery,nil);eq(#s.buys,0);
end);
test("coverage disappearing opens next-minute recovery, newly restored coverage cancels it",function()
    local s=scenario();s:item("item_ward_observer",0);s:check(345);eq(s.state.vision_recovery.start,360);
    s.wards={s.unit("npc_dota_observer_wards",2,-216.73818969727,-990.77404785156)};s.time=360;eq(s.phase.GetDesire(s.bot),0);eq(#s.orders,0);
end);
test("dead and off-mid checks can order but cannot issue hero movement",function()
    local s=scenario();s:bind();s.hp=0;s.bot.x=-7000;s.time=345;s.env.AbilityUsageThink();
    eq(s.state.vision_checked_minute,5);eq(s.supply.TryPurchase(s.bot),true);eq(#s.orders,0);
    s.hp=1000;s:item("item_ward_observer",0);s:check(405);s.time=420;eq(s.phase.GetDesire(s.bot),0);
    s.bot.x=-197;s.bot.y=-900;s:check(465);s:plant(480);eq(s.state.vision_done_slot,108);
end);
test("unknown wards or inventory never trigger speculative purchase",function()
    for _,kind in ipairs({"wards","inventory"}) do local s=scenario();
        if kind=="wards" then s.env.GetUnitList=function() return nil end else s.bot.GetItemInSlot=function() error("unknown") end end;
        s:check(45);eq(s.supply.TryPurchase(s.bot),false);eq(s.state.vision_recovery,nil);eq(#s.buys,0);
    end;
end);
test("own courier observer prevents a second purchase",function()
    local s=scenario();local it=s:item("item_ward_observer",0);s.items[0]=nil;
    s.env.GetNumCouriers=function() return 1 end;s.env.GetCourier=function() return {GetPlayerID=function() return 7 end,GetItemInSlot=function(_,i) if i==0 then return it end end} end;
    s:check(45);eq(s.state.vision_recovery,nil);eq(s.supply.TryPurchase(s.bot),false);eq(#s.buys,0);
end);
test("a simultaneous foreign ward cannot consume our placement readback",function()
    local s=scenario();s:item("item_ward_observer",0);s.time=300;s.mode=20;s.phase.Start(s.bot);s.phase.Think(s.bot);
    local foreign=s.unit("npc_dota_observer_wards",2,-216.73818969727,-990.77404785156);foreign.id=8;table.insert(s.wards,1,foreign);
    s:advance();s:mod("wards").Poll(s.bot,s.state);eq(s.state.vision_done_slot,1);eq(s.state.ward_pending,nil);
    assert(table.concat(s.logs,"\n"):find('"owner_matches":true',1,true));
end);
test("ten-minute success stops all further checks orders and resupply",function()
    local s=scenario();s:item("item_ward_observer",0);s:plant(600);eq(s.state.vision_final_ward,true);
    s.wards={};s.items[0]=nil;s:check(645);eq(s.supply.TryPurchase(s.bot),false);s.time=660;eq(s.phase.GetDesire(s.bot),0);
end);
test("missed ten-minute slot recovers at11 but never at12",function()
    local s=scenario();s:item("item_ward_observer",0);s:check(645);eq(s.state.vision_recovery.start,660);s:plant(660);eq(s.state.vision_final_ward,true);
    local t=scenario();t:item("item_ward_observer",0);t:check(705);eq(t.state.vision_recovery,nil);eq(t.schedule.NextWindow(705),nil);
    t.time=720;eq(t.supply.TryPurchase(t.bot),false);eq(t.phase.GetDesire(t.bot),0);
end);
test("missed-window report retains actual safety reason after window closes",function()
    local s=scenario();s:item("item_ward_observer",0);s.time=300;s.hp=100;eq(s.phase.GetDesire(s.bot),0);
    s.time=333.1;s.phase.GetDesire(s.bot);local log=table.concat(s.logs,"\n");assert(log:find('"last_reason":"health"',1,true));
end);
test("remote unseen allied ward check needs neither local sight nor facing nor movement",function()
    for _,exists in ipairs({true,false}) do
        local s=scenario();s.bot.x=-7000;s.bot.y=-7000;s.location_visible=false;
        local w=s.unit("npc_dota_observer_wards",2,-216.73818969727,-990.77404785156);w.visible=false;
        s.wards=exists and {w} or {};s:item("item_ward_observer",0);
        local facingReads=0;s.bot.GetFacing=function() facingReads=facingReads+1;return 180 end;
        s:check(45);eq(facingReads,0);eq(#s.orders,0);eq(#s.buys,0);eq(s.bot.x,-7000);eq(s.bot.y,-7000);
        if exists then eq(s.state.vision_recovery,nil) else eq(s.state.vision_recovery.start,60) end;
    end;
end);
print("WARD_RECOVERY PASSED "..n.." cases (synthetic API, not a live-match guarantee)");
