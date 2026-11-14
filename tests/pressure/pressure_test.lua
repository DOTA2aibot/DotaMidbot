local n=0;
local function eq(a,b) assert(a==b,tostring(a).." ~= "..tostring(b)) end;
local function test(name,fn) fn();n=n+1;print("PASS PRESSURE "..name) end;
local function scenario()
    local s=SCENARIO();s.profile={tower_pressure_enabled=true,ignore_watchers=true,runtime_enabled=false};
    local previous=s.env.require;
    s.env.require=function(path)
        if path:match("laning/profile$") then return s.profile end;
        if path:match("laning/economy/runes$") then return {Decide=function() return (s.rune_desire or 0)>0 and {desire=s.rune_desire} or nil end} end;
        return previous(path);
    end;
    s.env.TEAM_RADIANT=2;s.env.TEAM_DIRE=3;s.env.TOWER_MID_1=1;s.env.DAMAGE_TYPE_ALL=7;
    s.env.BOT_MODE_ROAM=3;s.env.BOT_MODE_SIDE_SHOP=6;s.env.BOT_MODE_WARD=22;
    s.env.IsLocationPassable=function() return not s.blocked end;
    s.bot.x=-650;s.bot.y=0;s.enemy_dps=10;s.botFactor=.45;
    s.bot.GetAttackDamage=function() return 100 end;s.bot.GetAttackRange=function() return 500 end;
    s.bot.GetAttackPoint=function() return .5 end;s.bot.GetCurrentMovementSpeed=function() return 300 end;
    s.bot.IsRooted=function() return false end;
    s.bot.GetActualIncomingDamage=function(_,raw,kind) return raw*s.botFactor end;
    s.enemy=s.unit("npc_dota_hero_viper",3,50,0);s.enemy.hp=1000;s.enemy.magic_factor=.75;
    s.enemy.GetHealthRegen=function() return 2 end;
    s.enemy.GetEstimatedDamageToTarget=function(_,_,_,seconds,_) return seconds*s.enemy_dps end;
    s.heroes={s.enemy};s.bot.target=s.enemy;
    s.tower=s.unit("npc_dota_badguys_tower1_mid",3,0,0);s.tower.range=700;
    s.tower.GetAttackDamage=function() return 80 end;s.tower.GetSecondsPerAttack=function() return 1 end;
    s.tower.GetAttackTarget=function() return s.focus end;s.towers={s.tower};
    s.home=s.unit("npc_dota_goodguys_tower1_mid",2,-2500,0);
    s.env.GetTower=function(team) return team==2 and s.home or s.tower end;
    s.ally=s.unit("npc_dota_creep_goodguys_melee",2,-100,0);s.ally.hp=1000;s.allies={s.ally};s.focus=s.ally;
    s.bot.GetNearbyLaneCreeps=function(_,_,enemy) return enemy and s.creeps or s.allies end;
    s.bot.Action_AttackUnit=function(_,target,once)
        s.orders[#s.orders+1]={kind="attack",target=target,once=once};s.action=s.env.BOT_ACTION_TYPE_ATTACK;s.attack=target;
    end;
    for i=1,3 do s.abilities["nevermore_shadowraze"..i].castpoint=.55 end;
    s.R=s.env.require("bots/laning/pressure/risk");s.P=s.env.require("bots/laning/pressure/entry");
    s.W=s.env.require("bots/laning/pressure/watchers");
    function s:evaluate() return self.R.Evaluate(self.bot,self.enemy,self.tower) end;
    function s:start() assert(self.P.GetDesire(self.bot)>0);self.mode=3;self.P.Start(self.bot);assert(self.state.pressure) end;
    return s;
end;

test("healthy covered pressure is allowed without claiming a kill",function()
    local s=scenario();local p=assert(s:evaluate());eq(p.cover,s.ally);eq(p.lethal,false);assert(p.hp_after_estimate>=p.reserve);assert(p.tower_shots>=2);
end);
test("no creeps and no lethal combo cannot dive",function()
    local s=scenario();s.focus=nil;s.allies={};local p,why=s:evaluate();eq(p,nil);eq(why,"no_creeps_no_lethal");
end);
test("a short Raze lethal dive is possible without creeps and includes all tower shots",function()
    local s=scenario();s.focus=nil;s.allies={};s.enemy.hp=200;
    local p=assert(s:evaluate());eq(p.lethal,true);eq(p.cover,nil);assert(p.tower_shots>=5);assert(p.damage>=s.enemy.hp);
end);
test("low HP or high incoming damage denies an otherwise lethal dive",function()
    local s=scenario();s.focus=nil;s.enemy.hp=200;s.hp=350;eq(s:evaluate(),nil);
    s.hp=1000;s.enemy_dps=150;local p,why=s:evaluate();eq(p,nil);eq(why,"survival_budget");
end);
test("missing enemy estimate or armor-adjusted tower damage fails closed",function()
    local s=scenario();s.enemy.GetEstimatedDamageToTarget=nil;eq(s:evaluate(),nil);
    s=scenario();s.bot.GetActualIncomingDamage=nil;eq(s:evaluate(),nil);
end);
test("a dying cover creep is not counted as protection",function()
    local s=scenario();s.ally.hp=50;eq(s:evaluate(),nil);
end);
test("a creep farther from tower than SF is not cover or a deaggro target",function()
    local s=scenario();s.ally.x=-900;eq(s.R.Cover(s.bot,s.tower),nil);eq(s.R.DeaggroTarget(s.bot,s.tower),nil);eq(s:evaluate(),nil);
end);
test("a second visible enemy or illusion forbids pressure",function()
    local s=scenario();s.heroes[2]=s.unit("npc_dota_hero_lina",3,100,0);eq(s:evaluate(),nil);
    s=scenario();s.enemy.illusion=true;eq(s:evaluate(),nil);
end);
test("blocked escape and overlapping towers forbid entry",function()
    local s=scenario();s.blocked=true;eq(s:evaluate(),nil);
    s=scenario();local extra=s.unit("npc_dota_badguys_tower2_mid",3,-400,0);extra.range=700;s.towers[2]=extra;eq(s:evaluate(),nil);
end);
test("fortification and visible enemy cast phases forbid entry",function()
    local s=scenario();s.tower.modifiers.modifier_fountain_glyph=true;eq(s:evaluate(),nil);
    s=scenario();local a=s:ability("viper_viper_strike");a.phase=true;s.enemy.active=a;eq(s:evaluate(),nil);
end);
test("unreachable far Raze is not counted when SF is already close",function()
    local s=scenario();s.bot.x=-200;local combo=assert(s.R.Combo(s.bot,s.enemy,{x=-200,y=0},0));
    -- distance250 reaches near/medium, not range700 radius250.
    eq(combo.spells,2);eq(combo.damage,300);
end);
test("mana and cooldowns limit projected damage; Wand charges are not borrowed",function()
    local s=scenario();s.mana=75;s:item("item_magic_wand",0,{charges=20});
    local p=assert(s:evaluate());eq(p.damage,150);
    s.abilities.nevermore_shadowraze3.cd=10;s.mana=0;s.focus=nil;s.enemy.hp=50;eq(s:evaluate(),nil);
end);
test("Raze projection does not count right-click damage as a guaranteed kill",function()
    local s=scenario();s.focus=nil;s.enemy.hp=1;s.mana=0;eq(s:evaluate(),nil);
end);
test("control profile neither reserves ROAM nor overrides tower safety",function()
    local s=scenario();s.profile.tower_pressure_enabled=false;eq(s.P.GetDesire(s.bot),0);
    eq(s.P.AllowStep(s.bot,{x=-600,y=0},s.tower),false);s.P.Think(s.bot);eq(#s.orders,0);
end);
test("startup, rune, retreat and last-hit opportunities have priority",function()
    local s=scenario();s.time=10;eq(s.P.GetDesire(s.bot),0);s.time=100;s.rune_desire=.42;eq(s.P.GetDesire(s.bot),0);
    s.rune_desire=0;s.mode=4;eq(s.P.GetDesire(s.bot),0);s.mode=1;
    local creep=s.unit("npc_dota_creep_badguys_melee",3,-400,0);creep.hp=50;s.creeps={creep};eq(s.P.GetDesire(s.bot),0);
end);
test("pressure closes for near Raze instead of stopping at attack range",function()
    local s=scenario();s.bot.x=-420;s.enemy.hp=150;s:start();s.P.Think(s.bot);eq(#s.orders,1);eq(s.orders[1].kind,"face");assert(s.orders[1].location.x>s.bot.x);
end);
test("same-frame and unchanged movement orders are not spammed",function()
    local s=scenario();s:start();s.P.Think(s.bot);eq(#s.orders,1);
    s.P.Think(s.bot);eq(#s.orders,1);s.action=1;s:advance(.5);s.P.Think(s.bot);eq(#s.orders,1);
end);
test("non-lethal covered pressure attacks from range instead of forcing a near-Raze walk",function()
    local s=scenario();s.bot.x=-420;s:start();s.P.Think(s.bot);eq(#s.orders,1);eq(s.orders[1].kind,"attack");eq(s.orders[1].target,s.enemy);
end);
test("a living creep currently taking tower shots remains cover when SF is closer",function()
    local s=scenario();s.bot.x=-350;s.ally.x=-500;eq(s.R.Cover(s.bot,s.tower),s.ally);eq(s.R.DeaggroTarget(s.bot,s.tower),nil);
    assert(s:evaluate());
end);
test("pending Raze and recent own Raze turn cannot be overwritten",function()
    local s=scenario();s:start();s.state.raze_facing={at=s.time};s.P.Think(s.bot);eq(#s.orders,0);
    s:advance(.3);s:mod("raze").Submitted(s.bot,s.abilities.nevermore_shadowraze3,{x=50,y=0});s.P.Think(s.bot);eq(#s.orders,0);
end);
test("focus switches attempt one A-click on a closer ally",function()
    local s=scenario();s:start();s.bot.x=-350;s.focus=s.bot;s:advance(.1);s.P.Think(s.bot);
    eq(#s.orders,1);eq(s.orders[1].kind,"attack");eq(s.orders[1].target,s.ally);eq(s.orders[1].once,true);
end);
test("deaggro success requires the tower target readback",function()
    local s=scenario();s:start();s.bot.x=-350;s.focus=s.bot;s:advance(.1);s.P.Think(s.bot);
    s.focus=s.ally;s:advance(.1);s.P.Think(s.bot);eq(s.state.pressure.drop,nil);
    assert(table.concat(s.logs,"\n"):find('"confirmed":true',1,true));
end);
test("failed deaggro exits instead of repeatedly attacking the ally",function()
    local s=scenario();s:start();s.bot.x=-350;s.focus=s.bot;s:advance(.1);s.P.Think(s.bot);
    s:advance(.4);s.P.Think(s.bot);eq(s.state.pressure.exiting,true);eq(#s.orders,1);
end);
test("the 3.1 second deaggro interval is not bypassed by a new decision",function()
    local s=scenario();s:start();s.bot.x=-350;s.focus=s.bot;s.next_deaggro=s.time+3;
    s.state.next_deaggro=s.time+3;s:advance(.1);s.P.Think(s.bot);eq(#s.orders,0);eq(s.state.pressure.exiting,true);
end);
test("a new enemy or a dead target ends pressure with an exit",function()
    local s=scenario();s:start();s.heroes[2]=s.unit("npc_dota_hero_lina",3,100,0);s:advance(.1);assert(s.P.GetDesire(s.bot)>0);eq(s.state.pressure.exiting,true);
    s=scenario();s:start();s.enemy.hp=0;s:advance(.1);s.P.GetDesire(s.bot);eq(s.state.pressure.exiting,true);
end);
test("cover loss ends a non-lethal session",function()
    local s=scenario();s:start();s.focus=nil;s.allies={};s:advance(.1);s.P.GetDesire(s.bot);eq(s.state.pressure.exiting,true);
end);
test("mode exit never clears a new native order or spell",function()
    local s=scenario();s:start();s.P.Leave(s.bot,"mode_ended");eq(#s.orders,0);eq(s.state.pressure,nil);eq(s.P.GetDesire(s.bot),0);
end);
test("bounded sessions and stalled approaches return to the lane",function()
    local s=scenario();s:start();s:advance(3.6);s.P.GetDesire(s.bot);eq(s.state.pressure.exiting,true);
    s=scenario();s:start();s.P.Think(s.bot);s:advance(1.3);s.P.Think(s.bot);eq(s.state.pressure.exiting,true);
end);
test("root turn permission uses risk and only the evaluated mid T1",function()
    local s=scenario();eq(s.P.AllowStep(s.bot,{x=-600,y=0},s.tower),true);
    eq(s.P.AllowStep(s.bot,{x=-600,y=0},s.home),false);
    s.enemy_dps=300;eq(s.P.AllowStep(s.bot,{x=-600,y=0},s.tower),false);
end);
test("only the exact watcher capture can interrupt a channel",function()
    local s=scenario();local a=s:ability("ability_lamp_use");s.active=a;s.channel=true;
    eq(s.W.Tick(s.bot,s.state),true);eq(#s.orders,1);eq(s.orders[1].kind,"clear");
    s=scenario();s.active=s.abilities.nevermore_requiem;s.channel=true;eq(s.W.Tick(s.bot,s.state),false);eq(#s.orders,0);
end);
test("watcher movement suppression never touches a hero target",function()
    local s=scenario();eq(s.W.Tick(s.bot,s.state),false);
    s.bot.target=s.unit("npc_dota_watch_tower",4,0,0);s.mode=6;s.action=1;
    eq(s.W.Tick(s.bot,s.state),true);eq(s.orders[1].kind,"clear");
end);
test("disabled watcher policy and repeated callbacks issue no clears",function()
    local s=scenario();s.active=s:ability("ability_lamp_use");s.profile.ignore_watchers=false;eq(s.W.Tick(s.bot,s.state),false);
    s.profile.ignore_watchers=true;eq(s.W.Tick(s.bot,s.state),true);eq(s.W.Tick(s.bot,s.state),false);eq(#s.orders,1);
end);
test("two already airborne tower shots increase the dive budget",function()
    local s=scenario();local before=assert(s:evaluate());
    s.bot.GetIncomingTrackingProjectiles=function() return {{is_attack=true,caster=s.tower},{is_attack=true,caster=s.tower}} end;
    local after=assert(s:evaluate());eq(after.tower_shots,before.tower_shots+1);eq(after.airborne_tower_shots,2);
end);
test("unknown projectile data fails closed",function()
    local s=scenario();s.bot.GetIncomingTrackingProjectiles=nil;eq(s:evaluate(),nil);
end);
test("root CastRaze retains the old gate in control and permits a risk-approved T1 turn",function()
    for _,active in ipairs({false,true}) do
        local s=scenario();s.profile.tower_pressure_enabled=active;
        local meta={};meta.__add=function(a,b) return s.env.Vector(a.x+b.x,a.y+b.y,(a.z or 0)+(b.z or 0)) end;
        s.env.Vector=function(x,y,z) return setmetatable({x=x,y=y,z=z or 0},meta) end;
        s.bot.GetLocation=function() return s.env.Vector(s.bot.x,s.bot.y,0) end;
        s.bot.GetFacing=function() return 90 end;
        local f=assert(loadfile("ability_item_usage_nevermore.lua"));setfenv(f,s.env);f();s.env.InitAbilities(s.bot);
        s.env.CastRaze(s.bot,s.abilities.nevermore_shadowraze3,s.env.Vector(50,0,0));
        eq(#s.orders,active and 1 or 0);if active then eq(s.orders[1].kind,"face") end;
    end;
end);
test("Dire pressure and retreat use the opposite mid-tower direction",function()
    local s=scenario();s.bot.team=3;s.bot.x=650;s.enemy.team=2;s.enemy.x=-50;s.tower.team=2;s.home.team=3;s.home.x=2500;s.ally.team=3;s.ally.x=100;
    s.env.GetTower=function(team) return team==3 and s.home or s.tower end;
    local p=assert(s:evaluate());assert(p.exit.x>700);assert(p.goal.x<s.bot.x);s:start();
end);
test("nearby enemy illusions also count as extra pressure risk",function()
    local s=scenario();local illusion=s.unit("npc_dota_hero_viper",3,150,0);illusion.illusion=true;s.heroes[2]=illusion;eq(s:evaluate(),nil);
end);
test("nearby enemy creeps contribute to the incoming damage budget",function()
    local s=scenario();local before=assert(s:evaluate());local c=s.unit("npc_dota_creep_badguys_melee",3,-200,0);
    c.GetAttackDamage=function() return 15 end;c.GetSecondsPerAttack=function() return 1 end;s.creeps={c};
    local after=assert(s:evaluate());assert(after.incoming>before.incoming);
    c.GetAttackDamage=nil;eq(s:evaluate(),nil);
end);
test("a stale same-frame candidate cannot start after the target becomes invalid",function()
    local s=scenario();assert(s.P.GetDesire(s.bot)>0);s.enemy.hp=0;s.P.Start(s.bot);eq(s.state.pressure,nil);eq(#s.orders,0);
end);
test("exit state suppresses new offensive decisions in the actual legacy binding",function()
    local s=scenario();s:start();s.state.pressure.exiting=true;
    local f=assert(loadfile("ability_item_usage_nevermore.lua"));setfenv(f,s.env);f();
    eq(s.env.ConsiderRazeOnHero(s.bot),0);eq(s.env.ConsiderRazeOnCreeps(s.bot),0);eq(s.env.ConsiderFeastOfSouls(s.bot),0);
end);
test("stale watcher targets cannot clear lane, rune or owned-pressure movement",function()
    local s=scenario();s.bot.target=s.unit("npc_dota_watch_tower",4,0,0);s.action=1;
    for _,mode in ipairs({1,7,22}) do s.mode=mode;eq(s.W.Tick(s.bot,s.state),false) end;
    s.mode=3;s.state.pressure={};eq(s.W.Tick(s.bot,s.state),false);
    s.state.pressure=nil;s.state.raze_cast={};eq(s.W.Tick(s.bot,s.state),false);eq(#s.orders,0);
end);
test("a decision error is logged and releases ownership without issuing orders",function()
    local s=scenario();s:start();s.R.Evaluate=function() error("synthetic unreadable data") end;
    eq(s.P.GetDesire(s.bot),0);eq(s.state.pressure,nil);eq(#s.orders,0);
    assert(table.concat(s.logs,"\n"):find("helper_error",1,true));
end);
print("PRESSURE PASSED "..n.." cases; native ROAM/deaggro/pathing remain unverified in Dota");
