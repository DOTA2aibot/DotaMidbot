local n=0;
local function eq(a,b) assert(a==b,tostring(a).." ~= "..tostring(b)) end;
local function test(name,fn) fn();n=n+1;print("PASS LOCAL_DEWARD "..name) end;
local function scenario()
    local s=SCENARIO();s.env.TEAM_RADIANT=2;s.env.TEAM_DIRE=3;s.env.BOT_MODE_WARD=22;s.env.UNIT_LIST_ENEMIES=99;
    local p=s.env.require("bots/laning/profile");p.wards_enabled=true;p.ward_phase_enabled=true;p.tower_pressure_enabled=true;
    s.v=s.env.require("bots/laning/vision/config");s.v.sentry_first=true;
    s.enemies={};s.env.GetUnitList=function(kind) return kind==99 and s.enemies or s.wards end;
    s.bot.GetAttackRange=function() return 500 end;s.bot.GetAttackDamage=function() return 100 end;
    s.bot.Action_AttackUnit=function(_,target,once) eq(once,true);s.orders[#s.orders+1]={kind="attack",target=target};s.attack=target;s.action=3 end;
    s.localD=s.env.require("bots/laning/vision/local_deward");s.service=s.env.require("bots/laning/vision/service");
    function s:ward(kind,x)
        local w=self.unit(kind=="sentry" and "npc_dota_sentry_wards" or "npc_dota_observer_wards",3,x or 100,0);w.hp=2;w.maxhp=2;
        self.enemies[#self.enemies+1]=w;return w;
    end;
    function s:creep(x) local c=self.unit("npc_dota_creep_badguys_melee",3,x or 100,0);c.hp=40;self.creeps[#self.creeps+1]=c;return c end;
    return s;
end;
test("visible Observer is available immediately outside minute windows",function()
    local s=scenario();s:ward("observer");local j=assert(s.localD.Candidate(s.bot,s.state));eq(j.ward_kind,"observer");eq(j.desire,.83);
end);
test("Sentry still outranks a nearer Observer",function()
    local s=scenario();s:ward("observer",100);local blue=s:ward("sentry",300);
    eq(assert(s.localD.Candidate(s.bot,s.state)).target,blue);
end);
test("one or two endangered creeps do not veto a valuable ward",function()
    local s=scenario();s:ward("observer");local c=s:creep(100);s:creep(200);s.action=3;s.attack=c;
    assert(s.localD.Candidate(s.bot,s.state));
end);
test("three endangered last hits defer cleanup to protect the wave",function()
    local s=scenario();s:ward("observer");for i=1,3 do s:creep(i*100) end;
    eq(s.localD.Candidate(s.bot,s.state),nil);
end);
test("hidden wards and distant wards never become cleanup targets",function()
    local s=scenario();local w=s:ward("observer");w.visible=false;eq(s.localD.Candidate(s.bot,s.state),nil);
    w.visible=true;w.x=1000;eq(s.localD.Candidate(s.bot,s.state),nil);
end);
test("nearby hero kill and direct danger preempt the ward",function()
    local s=scenario();s:ward("observer");local e=s.unit("npc_dota_hero_lina",3,700,0);e.hp=50;e.GetHealthRegen=function() return 0 end;
    s.heroes={e};eq(s.localD.Candidate(s.bot,s.state),nil);
    e.x=100;eq(s.localD.Candidate(s.bot,s.state),nil);
end);
test("own pressure and an uncompleted Raze are never interrupted",function()
    local s=scenario();s:ward("observer");s.state.pressure={};eq(s.localD.Candidate(s.bot,s.state),nil);
    s.state.pressure=nil;s:mod("raze").Submitted(s.bot,s.abilities.nevermore_shadowraze3,{x=700,y=0});
    eq(s.localD.Candidate(s.bot,s.state),nil);
end);
test("existing WARD service completes two attacks without same-frame cancellation",function()
    local s=scenario();local w=s:ward("observer");eq(s.service.GetDesire(s.bot),.83);
    s.mode=22;s.service.Start(s.bot);s.service.Think(s.bot);eq(#s.orders,1);assert(s.service.Holds(s.bot,s.state));
    s:advance(.3);s.service.Think(s.bot);eq(#s.orders,1);
    w.hp=1;s:advance(.8);s.service.Think(s.bot);eq(#s.orders,2);
    w.hp=0;s:advance(.8);s.service.Poll(s.bot,s.state);eq(s.state.vision_support,nil);eq(#s.orders,2);
    assert(table.concat(s.logs,"\n"):find("deward_destroyed_observed",1,true));
end);
test("losing visibility yields without invented kill credit",function()
    local s=scenario();local w=s:ward("observer");s.mode=22;s.service.Start(s.bot);s.service.Think(s.bot);
    w.visible=false;s:advance(.3);eq(s.service.Holds(s.bot,s.state),false);eq(s.state.vision_support,nil);
    assert(not table.concat(s.logs,"\n"):find("deward_destroyed_observed",1,true));
end);
test("new local work does not stop merely because ward refresh ended at12 minutes",function()
    local s=scenario();s.time=800;s:ward("observer");assert(s.localD.Candidate(s.bot,s.state));
end);
test("control profile cannot acquire the new high-priority cleanup",function()
    local s=scenario();s.env.require("bots/laning/profile").tower_pressure_enabled=false;s:ward("observer");eq(s.localD.Candidate(s.bot,s.state),nil);
end);
test("short approach remains bounded and never chases a distant ward",function()
    local s=scenario();s:ward("observer",600);local j=assert(s.localD.Candidate(s.bot,s.state));eq(j.location.x,600);
    s.mode=22;s.service.Start(s.bot);s.service.Think(s.bot);eq(s.orders[1].kind,"face");
end);
test("a small recent poke is allowed but a dangerous damage estimate is not",function()
    local s=scenario();s:ward("observer");s.recent=.1;
    local e=s.unit("npc_dota_hero_lina",3,600,0);e.hp=800;e.GetHealthRegen=function() return 0 end;
    e.GetEstimatedDamageToTarget=function() return 80 end;s.heroes={e};
    assert(s.localD.Candidate(s.bot,s.state));
    e.GetEstimatedDamageToTarget=function() return 700 end;eq(s.localD.Candidate(s.bot,s.state),nil);
end);
print("LOCAL_DEWARD PASSED "..n.." cases; real attacks and credits still require Dota");
