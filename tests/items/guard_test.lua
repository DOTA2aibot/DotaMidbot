local count=0;
local function eq(a,b) assert(a==b,tostring(a).." ~= "..tostring(b)) end;
local function test(name,fn) fn();count=count+1;print("PASS DELIVERY_GUARD "..name) end;
local function scenario()
    local s=SCENARIO();s.env.BOT_MODE_ROAM=6;s.env.BOT_MODE_WARD=22;s.env.COURIER_STATE_DELIVERING_ITEMS=3;
    s.env.require("bots/laning/profile").delivery_lane_guard=true;s.env.GetLaneFrontLocation=function() return {x=200,y=0,z=0} end;
    s.env.IsLocationPassable=function() return true end;s.courier=s.unit("npc_dota_courier",2,-3000,0);s.courier.id=7;
    s.courier.GetItemInSlot=function(_,i) if i==0 then return {} end end;s.env.GetNumCouriers=function() return 1 end;
    s.env.GetCourier=function() return s.courier end;s.env.GetCourierState=function() return s.courierState or 3 end;
    s.bot.GetIncomingTrackingProjectiles=function() return s.projectiles or {} end;
    s.guard=s.env.require("bots/laning/items/delivery_guard");s.action=2;
    s.bot.Action_AttackUnit=function(_,u,once) assert(once==true);s.orders[#s.orders+1]={kind="attack",target=u};s.action=3 end;
    function s:deviate() self.guard.GetDesire(self.bot);self.bot.x=-100;self:advance(.4);self.action=1;return self.guard.GetDesire(self.bot) end;
    return s;
end;
test("no courier deviation means no desire or orders",function()
    local s=scenario();for i=1,6 do eq(s.guard.GetDesire(s.bot),0);s:advance(.2) end;eq(#s.orders,0);
end);
test("observed lane deviation opens a read-only candidate",function()
    local s=scenario();assert(s:deviate()>0);eq(#s.orders,0);
end);
test("guard moves towards lane anchor and never towards courier",function()
    local s=scenario();s:deviate();s.mode=6;s.guard.Start(s.bot);s.guard.Think(s.bot);eq(#s.orders,1);
    assert(s.orders[1].location.x>s.bot.x);assert(s.orders[1].location.x>s.courier.x);s:advance(.1);s.guard.Think(s.bot);eq(#s.orders,1);
end);
test("nearby creep farm wins over meeting courier without chasing creep",function()
    local s=scenario();s:deviate();local c=s.unit("npc_dota_creep_badguys_melee",3,100,0);s.creeps={c};
    s.mode=6;s.guard.Start(s.bot);s.guard.Think(s.bot);eq(s.orders[1].kind,"attack");eq(s.orders[1].target,c);
    s:advance(.1);s.guard.Think(s.bot);eq(#s.orders,1);
end);
test("safe low-mana retreat may be guarded but real danger may not",function()
    local s=scenario();s.mode=4;s.mana=1;assert(s:deviate()>0);
    for _,why in ipairs({"hp","enemy","damage","tower","missile","cast","queue","ward","rune","attack"}) do local t=scenario();t:deviate();
        if why=="hp" then t.hp=700 elseif why=="enemy" then t.heroes={t.unit("npc_dota_hero_lina",3,100,0)}
        elseif why=="damage" then t.recent=1 elseif why=="tower" then local tower=t.unit("npc_dota_tower",3,100,0);tower.range=700;t.towers={tower}
        elseif why=="missile" then t.projectiles={{}} elseif why=="cast" then t.using=true elseif why=="queue" then t.queued=1
        elseif why=="ward" then t.mode=22 elseif why=="rune" then t.mode=7 else t.mode=2 end;
        eq(t.guard.GetDesire(t.bot),0);eq(#t.orders,0);
    end;
end);
test("delivery completion foreign dead courier unknown stock and near arrival disable guard",function()
    for _,why in ipairs({"done","foreign","dead","cargo","near","enum","lane"}) do local s=scenario();s:deviate();
        if why=="done" then s.courierState=4 elseif why=="foreign" then s.courier.id=8 elseif why=="dead" then s.courier.hp=0
        elseif why=="cargo" then s.courier.GetItemInSlot=function() error("unknown") end elseif why=="near" then s.courier.x=-500
        elseif why=="enum" then s.env.COURIER_STATE_DELIVERING_ITEMS=nil else s.env.GetLaneFrontLocation=nil end;
        eq(s.guard.GetDesire(s.bot),0);eq(#s.orders,0);
    end;
end);
test("lease is bounded and leaving never clears someone else's action",function()
    local s=scenario();s:deviate();s.mode=6;s.guard.Start(s.bot);s.guard.Think(s.bot);s:advance(6.1);eq(s.guard.GetDesire(s.bot),0);eq(s.state.delivery_guard,nil);eq(#s.orders,1);
end);
test("guard yields after a newly visible threat and during rune mode",function()
    for _,why in ipairs({"enemy","rune"}) do local s=scenario();s:deviate();s.mode=6;s.guard.Start(s.bot);
        if why=="enemy" then s.heroes={s.unit("npc_dota_hero_lina",3,100,0)} else s.mode=7 end;
        s.guard.Think(s.bot);eq(s.state.delivery_guard,nil);eq(#s.orders,0);
    end;
end);
test("non-test profile illusion and nonSF cannot activate courier guard",function()
    for _,why in ipairs({"profile","illusion","hero"}) do local s=scenario();
        if why=="profile" then s.env.require("bots/laning/profile").delivery_lane_guard=false elseif why=="illusion" then s.bot.illusion=true else s.bot.name="npc_dota_hero_lina" end;
        eq(s:deviate(),0);eq(#s.orders,0);
    end;
end);
test("personal mode has full lifecycle and graceful no-desire on callback failure",function()
    local s=scenario();s:deviate();local f=assert(loadfile("profiles/all_test/mode_roam_nevermore.lua"));setfenv(f,s.env);f();
    assert(s.env.GetDesire()>0);s.mode=6;s.env.OnStart();s.env.Think();s.env.OnEnd();eq(s.state.delivery_guard,nil);eq(#s.orders,1);
end);
print("DELIVERY_GUARD PASSED "..count.." cases (native arbitration/path and actual rendezvous need client test)");
