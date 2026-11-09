local n=0;
local function eq(a,b) assert(a==b,tostring(a).." ~= "..tostring(b)) end;
local function test(name,fn) fn();n=n+1;print("PASS VISION_CALIBRATION "..name) end;
local function scenario()
    local s=SCENARIO();s.env.TEAM_RADIANT=2;s.env.BOT_MODE_WARD=20;s.time=0;
    local p=s.env.require("bots/laning/profile");p.wards_enabled=true;p.ward_phase_enabled=true;
    function s:vision(name) return self.env.require("bots/laning/vision/"..name) end;
    s.state=s.broker.State(s.bot);s.env.GetHeightLevel=function() return 3 end;
    s.env.GetNumCouriers=function() return 0 end;s.env.PURCHASE_ITEM_SUCCESS=0;
    s.env.GetItemCost=function() return 0 end;s.bot.GetGold=function() return 1000 end;
    s.buys={};s.bot.ActionImmediate_PurchaseItem=function(_,name) s.buys[#s.buys+1]=name;return 0 end;
    return s;
end;
test("explicit calibration switch still blocks all automatic Radiant ward orders",function()
    local s=scenario();s:vision("config").calibration_only=true;s:item("item_ward_observer",0);
    eq(s:vision("config").calibration_only,true);eq(s:vision("phase").GetDesire(s.bot),0);
    eq(s:mod("wards").Tick(s.bot,s.state),false);eq(s:vision("supply").TryPurchase(s.bot),false);eq(#s.orders,0);eq(#s.buys,0);
end);
test("manual human Observer records actual XYZ and owner without auto-adoption",function()
    local s=scenario();local w=s.unit("npc_dota_observer_wards",2,-100,-900);w.id=2;
    w.GetLocation=function() return {x=-100,y=-900,z=128} end;s.wards={w};s.env.IsPlayerBot=function(id) return id~=2 end;
    s:vision("diagnostics").Tick(s.bot,s.state);local log=table.concat(s.logs,"\n");
    assert(log:find('ward_entity_observed',1,true));assert(log:find('"human_owned":true',1,true));
    assert(log:find('"z":128',1,true));assert(log:find('"owner_id":2',1,true));assert(log:find('"auto_adopted":false',1,true));
    eq(#s.orders,0);eq(s:vision("config").fixed_location.x,-216.73818969727);
end);
test("unchanged ward emits only once and multiple human wards stay distinct",function()
    local s=scenario();s.wards={s.unit("npc_dota_observer_wards",2,-100,-900)};
    local d=s:vision("diagnostics");d.Tick(s.bot,s.state);local first=#s.logs;s:advance(5);d.Tick(s.bot,s.state);eq(#s.logs,first);
    s.wards[2]=s.unit("npc_dota_observer_wards",2,-120,-950);s:advance(5);d.Tick(s.bot,s.state);eq(#s.logs,first+1);eq(#s.orders,0);
end);
test("geometry records candidate as unverified and unknown API is not false evidence",function()
    local s=scenario();s:vision("config").calibration_source=nil;s.env.GetGroundHeight=nil;s.env.IsLocationVisible=nil;
    s:vision("diagnostics").Tick(s.bot,s.state);local log=table.concat(s.logs,"\n");
    assert(log:find('"photo_match":"not_verified"',1,true));assert(log:find('"plant_validity":"not_tested"',1,true));
    assert(not log:find('"ground_z":0',1,true));eq(#s.orders,0);
end);
test("actual tactical callback writes manual ward entity despite no ward phase",function()
    local s=scenario();s.wards={s.unit("npc_dota_observer_wards",2,-100,-900)};s:bind();s.env.ItemUsageThink();
    assert(table.concat(s.logs,"\n"):find('ward_entity_observed',1,true));eq(#s.orders,0);
end);
test("scheduled refresh prefetches own next ward and allows only confirmed prior-slot overlap",function()
    local s=scenario();s:vision("config").calibration_only=false;
    local supply=s:vision("supply");local w=s.unit("npc_dota_observer_wards",2,-197,-1003);w.id=7;s.wards={w};
    supply.Placed(s.bot,w,{location={x=-197,y=-1003},vision_slot=0});s.state.vision_done_slot=0;
    eq(supply.CanReplace(s.bot,{handle=w},0),false);eq(supply.CanReplace(s.bot,{handle=w},1),true);
    s.time=239;eq(supply.TryPurchase(s.bot),false);s.time=240;eq(supply.TryPurchase(s.bot),true);eq(#s.buys,1);
    s.time=241;eq(supply.TryPurchase(s.bot),false);eq(#s.buys,1);
    s:item("item_ward_observer",0);s.bot.x=-197;s.bot.y=-900;s.time=300;s.mode=20;
    local phase=s:vision("phase");phase.Start(s.bot);assert(s.state.vision_phase);phase.Think(s.bot);
    assert(s.state.ward_pending);s:advance();s:mod("wards").Poll(s.bot,s.state);eq(s.state.vision_done_slot,1);
    phase.Holds(s.bot,s.state);eq(phase.GetDesire(s.bot),0);eq(#s.orders,1);
end);
test("unconfirmed or another player's ward cannot be deliberately duplicated",function()
    local s=scenario();s:vision("config").calibration_only=false;local w=s.unit("npc_dota_observer_wards",2,-197,-1003);
    s.wards={w};s.time=300;s:item("item_ward_observer",0);eq(s:vision("phase").GetDesire(s.bot),0);
    eq(s:vision("supply").CanReplace(s.bot,{handle=w},1),false);
end);
test("missed window is explicit one-time evidence and never triggers a late catch-up trip",function()
    local s=scenario();s:vision("config").calibration_only=false;s:item("item_ward_observer",0);s.time=18.1;
    local phase=s:vision("phase");eq(phase.GetDesire(s.bot),0);local count=#s.logs;s:advance();phase.Poll(s.bot,s.state);eq(#s.logs,count);
    assert(table.concat(s.logs,"\n"):find('ward_window_missed',1,true));eq(#s.orders,0);
end);
test("pinned point is enabled and retains real ward Z without GroundHeight API",function()
    local s=scenario();local c=s:vision("config");eq(c.calibration_only,false);eq(c.calibration_source.match_id,"9082528045");
    s.env.GetGroundHeight=nil;local p=assert(s:vision("site").Get(s.bot));
    eq(p.location.x,-216.73818969727);eq(p.location.y,-990.77404785156);eq(p.location.z,128);
    s:vision("diagnostics").Tick(s.bot,s.state);local log=table.concat(s.logs,"\n");
    assert(log:find('human_ward_coordinate_pinned',1,true));assert(log:find('requires_current_match_readback',1,true));
end);
test("unwalkable ward cliff remains plantable and approach targets passable cast range",function()
    local s=scenario();local c=s:vision("config");local q=c.fixed_location;s.bot.x=q.x;s.bot.y=q.y+700;
    s.env.IsLocationPassable=function(p) return math.sqrt((p.x-q.x)^2+(p.y-q.y)^2)>200 end;
    s:item("item_ward_observer",0);local phase=s:vision("phase");assert(phase.GetDesire(s.bot)>0);s.mode=20;phase.Start(s.bot);phase.Think(s.bot);
    eq(s.orders[1].kind,"face");assert(s.env.IsLocationPassable(s.orders[1].location));
    s.bot.x=s.orders[1].location.x;s.bot.y=s.orders[1].location.y;s:advance(1.1);phase.Think(s.bot);
    eq(s.orders[2].kind,"ward");eq(s.orders[2].location.x,q.x);eq(s.orders[2].location.y,q.y);eq(s.orders[2].location.z,128);
end);
print("VISION_CALIBRATION PASSED "..n.." cases (mock SF execution; human coordinate separately verified in source log)");
