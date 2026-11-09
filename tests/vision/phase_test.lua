local count=0;
local function eq(a,b) assert(a==b,tostring(a).." ~= "..tostring(b)) end;
local function test(name,fn) fn();count=count+1;print("PASS WARD_PHASE "..name) end;
local function scenario()
    local s=SCENARIO();s.time=0;s.env.TEAM_RADIANT=2;s.env.BOT_MODE_WARD=20;
    s.bot.x=-197;s.bot.y=-400;
    s.env.GetHeightLevel=function() return 2 end;
    s.env.IsLocationPassable=function() return true end;
    s.env.GetGroundHeight=function() return 128 end;
    s.env.GetNumCouriers=function() return 0 end;
    local profile=s.env.require("bots/laning/profile");profile.wards_enabled=true;
    profile.ward_phase_enabled=true;profile.runtime_enabled=false;
    function s:vision(name) return self.env.require("bots/laning/vision/"..name) end;
    s:vision("config").calibration_only=false;
    s:item("item_ward_observer",0);s.phase=s:vision("phase");
    s.state=s.broker.State(s.bot);
    function s:start()
        assert(self.phase.GetDesire(self.bot)>0);self.mode=20;self.phase.Start(self.bot);assert(self.state.vision_phase);
    end;
    return s;
end;
test("pinned human entity XY uses ground Z, no grid search or invented SF success",function()
    local s=scenario();s.env.GetAllTrees=function() error("search must not run") end;
    local p=assert(s:vision("site").Get(s.bot));eq(p.location.x,-216.73818969727);eq(p.location.y,-990.77404785156);eq(p.location.z,128);
    eq(p.expected_coverage,"human_calibrated_point_sf_placement_unverified");assert(p.rune_distance>0);
    local t=scenario();t.env.GetHeightLevel=nil;eq(t.phase.GetDesire(t.bot),0);
end);
test("only windows0-30,300-330,600-630 open and prefetch starts210/510",function()
    local s=scenario();local c=s:vision("schedule");
    for _,t in ipairs({-90,-.01,30.01,299.99,330.01,599.99,630.01,900}) do eq(c.Slot(t),nil) end;
    eq(c.Slot(0),0);eq(c.Slot(30),0);eq(c.Slot(300),1);eq(c.Slot(330),1);eq(c.Slot(600),2);eq(c.Slot(630),2);
    eq(c.Request(209.9),nil);eq(c.Request(210).slot,1);eq(c.Request(510).slot,2);
end);
test("active rune mode preempts even inside mandatory ward window",function()
    for _,time in ipairs({0,300,600}) do local s=scenario();s.time=time;assert(s.phase.GetDesire(s.bot)>0);s.mode=7;eq(s.phase.GetDesire(s.bot),0) end;
end);
test("candidate and mode desire issue no orders",function()
    local s=scenario();for i=1,5 do assert(s.phase.GetDesire(s.bot)>0) end;eq(#s.orders,0);
end);
test("mode owns approach across ticks then places once and confirms before release",function()
    local s=scenario();s:start();s.phase.Think(s.bot);eq(s.orders[1].kind,"face");assert(s.state.vision_phase);
    s:advance(.1);s.phase.Think(s.bot);eq(#s.orders,1); -- no per-frame order spam
    s.bot.y=-800;s:advance(.6);s.phase.Think(s.bot);eq(s.orders[2].kind,"ward");
    eq(s.orders[2].location.x,-216.73818969727);eq(s.orders[2].location.y,-990.77404785156);assert(s.state.ward_pending);
    s:advance();s:mod("wards").Poll(s.bot,s.state);eq(s.state.ward_pending,nil);
    eq(s.phase.Holds(s.bot,s.state),false);eq(s.state.vision_phase,nil);eq(s.state.vision_done_slot,0);
    eq(s.phase.GetDesire(s.bot),0);eq(#s.orders,2);
end);
test("confirmed slot cannot repeat and next window opens only at due time",function()
    local s=scenario();s.state.vision_done_slot=0;s.time=5;eq(s.phase.GetDesire(s.bot),0);
    s.time=299;eq(s.phase.GetDesire(s.bot),0);s.time=300;assert(s.phase.GetDesire(s.bot)>0);
    s.state.vision_done_slot=1;s.time=310;eq(s.phase.GetDesire(s.bot),0);s.time=600;assert(s.phase.GetDesire(s.bot)>0);
end);
test("living allied observer prevents approach and duplicates",function()
    local s=scenario();s.wards={s.unit("npc_dota_observer_wards",2,-197,-1003)};
    eq(s.phase.GetDesire(s.bot),0);eq(#s.orders,0);
end);
test("ordinary creep farm deny and native AA yield during mandatory window",function()
    local s=scenario();s.creeps={s.unit("npc_dota_creep_lane",3,-197,-700)};s.action=3;
    assert(s.phase.GetDesire(s.bot)>0);s:start();s.phase.Think(s.bot);eq(#s.orders,1);assert(s.state.vision_phase);
    s:advance(.1);eq(s.phase.Holds(s.bot,s.state),true);
end);
test("direct enemy threat retreat cast and unknown query prevent entry",function()
    for _,why in ipairs({"enemy","retreat","casting","unknown","damage","health","queued"}) do
        local s=scenario();
        if why=="enemy" then s.heroes={s.unit("npc_dota_hero_lina",3,-197,-700)}
        elseif why=="retreat" then s.mode=4 elseif why=="attack" then s.action=3
        elseif why=="casting" then s.using=true elseif why=="unknown" then s.enemies_unknown=true
        elseif why=="damage" then s.recent=1 elseif why=="health" then s.hp=600 else s.queued=1 end;
        eq(s.phase.GetDesire(s.bot),0);eq(#s.orders,0);
    end;
end);
test("new direct danger releases owned phase without clearing another action",function()
    for _,why in ipairs({"enemy","rune","retreat","dead","muted","health","disabled"}) do local s=scenario();s:start();s.phase.Think(s.bot);
        if why=="enemy" then s.heroes={s.unit("npc_dota_hero_lina",3,-197,-700)}
        elseif why=="creep" then s.creeps={s.unit("npc_dota_creep_lane",3,-197,-700)}
        elseif why=="rune" then s.mode=7 elseif why=="retreat" then s.mode=4
        elseif why=="dead" then s.hp=0 elseif why=="muted" then s.bot.IsMuted=function() return true end
        elseif why=="health" then s.hp=600 else s.config.enabled=false end;
        s:advance();eq(s.phase.Holds(s.bot,s.state),false);eq(s.state.vision_phase,nil);eq(#s.orders,1);
        for _,o in ipairs(s.orders) do assert(o.kind~="clear") end;
    end;
end);
test("time limit and stalled path are bounded, retry cannot cause microstep loop",function()
    for _,dt in ipairs({2.1,8.1}) do local s=scenario();s:start();s.phase.Think(s.bot);s:advance(dt);s.phase.Think(s.bot);
        eq(s.state.vision_phase,nil);eq(s.phase.GetDesire(s.bot),0);eq(#s.orders,1);
        s.time=31;eq(s.phase.GetDesire(s.bot),0);s.time=300;assert(s.phase.GetDesire(s.bot)>0);
    end;
end);
test("no passable casting position releases phase without a move",function()
    local s=scenario();s.env.IsLocationPassable=function() return false end;s:start();s.phase.Think(s.bot);
    eq(s.state.vision_phase,nil);eq(#s.orders,0);
end);
test("approach beyond maximum is rejected",function()
    local s=scenario();s.bot.y=1000;eq(s.phase.GetDesire(s.bot),0);eq(#s.orders,0);
end);
test("ward pending is held across a cast and readback, not resubmitted",function()
    local s=scenario();s.bot.y=-800;
    s.bot.Action_UseAbilityOnLocation=function(_,item) s.orders[#s.orders+1]={kind="ward"};s.using=true;s.active=item end;
    s:start();s.phase.Think(s.bot);assert(s.state.ward_pending);s:advance(.2);
    assert(s.phase.Holds(s.bot,s.state));s.phase.Think(s.bot);eq(#s.orders,1);
    s:advance(3);s:mod("wards").Poll(s.bot,s.state);eq(s.state.ward_pending,nil);
    eq(s.phase.Holds(s.bot,s.state),false);eq(s.state.vision_done_slot,nil);
end);
test("readback timeout without consumption never counts as placement",function()
    local s=scenario();s.bot.y=-800;s.bot.Action_UseAbilityOnLocation=function() end;
    s:start();s.phase.Think(s.bot);s:advance(3.1);s:mod("wards").Poll(s.bot,s.state);
    eq(s.state.vision_done_slot,nil);eq(s.state.vision_confirmed_at,nil);
end);
test("ability ward hook cannot issue opportunistic ward orders in phase profile",function()
    local s=scenario();s.bot.y=-800;eq(s:mod("wards").Tick(s.bot,s.state),false);eq(#s.orders,0);
end);
test("real tactical entry suppresses PT/abilities and preserves observer during lease",function()
    local s=scenario();s:bind();s:item("item_power_treads",1,{stat=1});s:start();s.phase.Think(s.bot);
    s:advance(.1);s.env.AbilityUsageThink();s.env.ItemUsageThink();eq(#s.orders,1);assert((s.observed or 0)>0);
    assert(s.state.vision_phase);s.phase.Leave(s.bot,"test_finished");s.mode=1;s:advance();
    eq(s.phase.Holds(s.bot,s.state),false);
end);
test("emergency BKB releases ward lease and is the only new order",function()
    local s=scenario();s:bind();local bkb=s:item("item_black_king_bar",1);s:start();s.phase.Think(s.bot);
    local enemy=s.unit("npc_dota_hero_sven",3,-197,-700);s.heroes={enemy};
    local a=s:ability("sven_storm_bolt",{cost=0});a.caster=enemy;
    s.projectiles={{ability=a,caster=enemy,location={x=-197,y=-390},velocity=1000,is_attack=false}};
    s:advance(.1);s.env.AbilityUsageThink();eq(s.state.vision_phase,nil);
    eq(s.orders[#s.orders].ability,"item_black_king_bar");eq(#s.orders,2);
end);
test("callback entry has complete lifecycle and resets ownership on end",function()
    local s=scenario();local f=assert(loadfile("profiles/vision/mode_ward_nevermore.lua"));setfenv(f,s.env);f();
    assert(s.env.GetDesire()>0);s.mode=20;s.env.OnStart();assert(s.state.vision_phase);s.env.Think();
    s.env.OnEnd();eq(s.state.vision_phase,nil);eq(s.env.GetDesire(),0);
end);
test("wrong team illusion nonSF disabled profile and diagnostic cannot own ward mode",function()
    for _,why in ipairs({"dire","illusion","otherhero","disabled","diagnostic"}) do local s=scenario();
        local profile=s.env.require("bots/laning/profile");
        if why=="dire" then s.bot.team=3 elseif why=="illusion" then s.bot.illusion=true
        elseif why=="otherhero" then s.bot.name="npc_dota_hero_lina"
        elseif why=="disabled" then profile.ward_phase_enabled=false else profile.runtime_enabled=true end;
        eq(s.phase.GetDesire(s.bot),0);eq(#s.orders,0);
    end;
end);
print("WARD_PHASE PASSED "..count.." cases (synthetic engine; client mode dispatch/LOS unverified)");
