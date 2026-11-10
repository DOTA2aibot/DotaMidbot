local n=0;
local function eq(a,b) assert(a==b,tostring(a).." ~= "..tostring(b)) end;
local function test(name,fn) fn();n=n+1;print('PASS RAZE_TURN '..name) end;
local function scenario()
    local s=SCENARIO();local meta={};meta.__add=function(a,b) return s.env.Vector(a.x+b.x,a.y+b.y,(a.z or 0)+(b.z or 0)) end;
    s.env.Vector=function(x,y,z) return setmetatable({x=x,y=y,z=z or 0},meta) end;
    s.bot.GetLocation=function() return s.env.Vector(s.bot.x,s.bot.y,0) end;
    s.decisions={};s.observer.RazeTurnDecision=function(_,data) s.decisions[#s.decisions+1]=data end;
    local f=assert(loadfile(CURRENT_OWNER_SOURCE));setfenv(f,s.env);f();s.env.InitAbilities(s.bot);
    for i=1,2 do s.abilities['nevermore_shadowraze'..i].level=0 end;
    s.a=s.abilities.nevermore_shadowraze3;
    return s;
end;
test('target inside250 but outside210 radial margin never causes a turn',function()
    local s=scenario();for i=1,30 do s.env.CastRaze(s.bot,s.a,s.env.Vector(0,480,0));s:advance(.033) end;
    eq(#s.orders,0);assert(#s.decisions>0);eq(s.decisions[1].reason,'outside_radial_hit_margin');
end);
test('unreachable turn cannot interrupt an existing attack',function()
    local s=scenario();s.action=3;s.attack=s.unit('npc_dota_creep_badguys_melee',3,200,0);
    s.env.CastRaze(s.bot,s.a,s.env.Vector(0,480,0));eq(#s.orders,0);eq(s.action,3);assert(s.attack);
end);
test('aligned Raze uses one fresh stable callback without face orders',function()
    local s=scenario();s.env.CastRaze(s.bot,s.a,s.env.Vector(500,0,0));eq(#s.orders,0);
    s:advance(.033);s.env.CastRaze(s.bot,s.a,s.env.Vector(500,0,0));eq(#s.orders,1);eq(s.orders[1].ability,'nevermore_shadowraze3');
end);
test('a stationary wrong facing cannot issue an endless150ms face stream',function()
    local s=scenario();for i=1,5 do s.env.CastRaze(s.bot,s.a,s.env.Vector(0,700,0));s:advance(.167) end;
    eq(#s.orders,2);for _,o in ipairs(s.orders) do eq(o.kind,'face') end;
    assert(s.decisions[#s.decisions].reason=='bounded_turn_backoff');
end);
test('geometrically valid cast bypasses the turn backoff',function()
    local s=scenario();for i=1,3 do s.env.CastRaze(s.bot,s.a,s.env.Vector(0,700,0));s:advance(.167) end;
    eq(#s.orders,2);s.bot.GetFacing=function() return 90 end;
    s.env.CastRaze(s.bot,s.a,s.env.Vector(0,700,0));eq(#s.orders,2);
    s:advance(.033);s.env.CastRaze(s.bot,s.a,s.env.Vector(0,700,0));eq(#s.orders,3);eq(s.orders[3].ability,'nevermore_shadowraze3');
end);
test('hero selector uses the same reachable margin as the cast executor',function()
    local s=scenario();local e=s.unit('npc_dota_hero_lina',3,480,0);e.hp=100;s.heroes={e};
    local d=s.env.MIDBOT_TACTICAL_BOUND.originals.ConsiderRazeOnHero(s.bot);eq(d,0);
    e.x=500;d=s.env.MIDBOT_TACTICAL_BOUND.originals.ConsiderRazeOnHero(s.bot);assert(d>0);
end);
test('creep secure and pack aim reject the executor-unreachable rim',function()
    local s=scenario();s.creeps={};
    for i=1,3 do local c=s.unit('npc_dota_creep_badguys_melee',3,480,0);c.hp=100;s.creeps[i]=c end;
    local d=s.env.MIDBOT_TACTICAL_BOUND.originals.ConsiderRazeOnCreeps(s.bot);eq(d,0);
    for _,c in ipairs(s.creeps) do c.x=500 end;
    d=s.env.MIDBOT_TACTICAL_BOUND.originals.ConsiderRazeOnCreeps(s.bot);assert(d>0);
end);
test('absent Stick and PT do not reserve control or issue recovery orders',function()
    local s=scenario();s.mana=0;local e=s.unit('npc_dota_hero_lina',3,700,0);e.hp=100;e.GetHealthRegen=function() return 0 end;s.heroes={e};
    local f=s:mod('finisher');for i=1,90 do eq(f.Tick(s.bot,s.state),false);s:advance(.033) end;
    eq(#s.orders,0);eq(s.state.pt_spell,nil);
end);
test('turning through the hit circle does not trigger a premature Raze',function()
    local s=scenario();local facing=0;s.bot.GetFacing=function() return facing end;
    s.env.CastRaze(s.bot,s.a,s.env.Vector(700,0,0));s:advance(.033);facing=10;
    s.env.CastRaze(s.bot,s.a,s.env.Vector(700,0,0));eq(#s.orders,0);
    s:advance(.033);s.env.CastRaze(s.bot,s.a,s.env.Vector(700,0,0));eq(#s.orders,1);
end);
test('a same-frame callback cannot manufacture stable facing',function()
    local s=scenario();for i=1,5 do s.env.CastRaze(s.bot,s.a,s.env.Vector(700,0,0)) end;eq(#s.orders,0);
end);
test('frequent callbacks do not reset the stability timer forever',function()
    local s=scenario();for i=1,3 do s.env.CastRaze(s.bot,s.a,s.env.Vector(700,0,0));s:advance(.01) end;
    eq(#s.orders,0);s.env.CastRaze(s.bot,s.a,s.env.Vector(700,0,0));eq(#s.orders,1);
end);
test('stability is invalidated by stale samples or a new aim direction',function()
    local s=scenario();local g=s:mod('raze');
    eq(g.Ready(s.bot,s.a,{x=700,y=0}),false);s:advance(.3);eq(g.Ready(s.bot,s.a,{x=700,y=0}),false);
    s:advance(.033);eq(g.Ready(s.bot,s.a,{x=700,y=100}),false);
    s:advance(.033);eq(g.Ready(s.bot,s.a,{x=700,y=100}),true);
end);
test('only our own active drifting Raze can be cancelled before release',function()
    local s=scenario();local g=s:mod('raze');g.Submitted(s.bot,s.a,{x=700,y=0});
    s.active=s.a;s.using=true;s.a.phase=true;s.bot.GetFacing=function() return 60 end;s:advance(.1);
    eq(g.Poll(s.bot,s.state),true);eq(#s.orders,1);eq(s.orders[1].kind,'clear');eq(s.state.raze_cast,nil);
    assert(table.concat(s.logs,'\n'):find('raze_drift_cancelled',1,true));
end);
test('real bound callback cancels its drifting Raze once and returns before other work',function()
    local s=scenario();s.env.CastRaze(s.bot,s.a,s.env.Vector(700,0,0));s:advance(.033);
    s.env.CastRaze(s.bot,s.a,s.env.Vector(700,0,0));eq(#s.orders,1);
    s.bot.GetFacing=function() return 60 end;s:advance(.1);s.env.AbilityUsageThink();
    eq(#s.orders,2);eq(s.orders[2].kind,'clear');eq(s.state.raze_cast,nil);
    s.env.AbilityUsageThink();eq(#s.orders,2);
end);
test('release is observed before any drift cancellation and never labelled a hit',function()
    local s=scenario();local g=s:mod('raze');g.Submitted(s.bot,s.a,{x=700,y=0});s.a.cd=10;
    s.bot.GetFacing=function() return 60 end;s:advance(.1);eq(g.Poll(s.bot,s.state),false);eq(#s.orders,0);eq(s.state.raze_cast,nil);
    local logs=table.concat(s.logs,'\n');assert(logs:find('raze_release_observed',1,true));assert(logs:find('"hit":"unknown"',1,true));
end);
test('another visible unit in the actual impact circle prevents cancellation',function()
    local s=scenario();local g=s:mod('raze');g.Submitted(s.bot,s.a,{x=700,y=0});s.active=s.a;s.a.phase=true;
    s.bot.GetFacing=function() return 60 end;s.creeps={s.unit('npc_dota_creep_badguys_melee',3,350,606)};s:advance(.1);
    eq(g.Poll(s.bot,s.state),false);eq(#s.orders,0);assert(s.state.raze_cast);
end);
test('edge-of-radius casts are not cancelled merely for crossing the safety margin',function()
    local s=scenario();local g=s:mod('raze');g.Submitted(s.bot,s.a,{x=700,y=0});s.active=s.a;s.a.phase=true;
    s.bot.GetFacing=function() return 20 end;s:advance(.1);eq(g.Poll(s.bot,s.state),false);eq(#s.orders,0);
end);
test('unowned casts other abilities unknown APIs and interrupted phases are never stopped',function()
    for _,why in ipairs({'unowned','other','unknown','lost'}) do
        local s=scenario();local g=s:mod('raze');
        if why~='unowned' then g.Submitted(s.bot,s.a,{x=700,y=0}) end;
        s.active=why=='other' and s.abilities.nevermore_requiem or s.a;s.a.phase=true;
        if why=='unknown' then s.bot.GetNearbyHeroes=function() return nil end end;
        if why=='lost' then s.state.raze_cast.phase_seen=true;s.a.phase=false end;
        s.bot.GetFacing=function() return 60 end;s:advance(.1);eq(g.Poll(s.bot,s.state),false);eq(#s.orders,0);
    end;
end);
test('expired ownership cannot cancel a later cast of the same ability',function()
    local s=scenario();local g=s:mod('raze');g.Submitted(s.bot,s.a,{x=700,y=0});
    s.active=s.a;s.a.phase=true;s.bot.GetFacing=function() return 60 end;s:advance(2.1);
    eq(g.Poll(s.bot,s.state),false);eq(#s.orders,0);eq(s.state.raze_cast,nil);
end);
print('RAZE_TURN PASSED '..n..' cases; real jitter/hit rate still need a new match');
