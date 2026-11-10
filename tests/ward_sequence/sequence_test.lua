local n=0;
local function eq(a,b) assert(a==b,tostring(a)..' ~= '..tostring(b)) end;
local function test(name,fn) fn();n=n+1;print('PASS WARD_SEQUENCE '..name) end;
local function scenario(team)
    local s=SCENARIO();s.time=0;s.bot.team=team or 2;s.env.TEAM_RADIANT=2;s.env.TEAM_DIRE=3;s.env.BOT_MODE_WARD=20;s.env.UNIT_LIST_ENEMIES=99;
    s.enemies={};s.env.GetUnitList=function(kind) return kind==99 and s.enemies or s.wards end;
    s.env.GetNumCouriers=function() return 0 end;
    local profile=s.env.require('bots/laning/profile');profile.wards_enabled=true;profile.ward_phase_enabled=true;
    s.v=s.env.require('bots/laning/vision/config');s.v.sentry_first=true;
    s.v.fixed_location={x=0,y=300,z=128};s.v.dire_fixed_location={x=0,y=-300,z=128};s.v.sentry_fixed_location={x=0,y=0,z=0};
    s.env.GetHeightLevel=function(p) return math.abs(p.y)>=200 and 3 or 1 end;
    s.seq=s.env.require('bots/laning/vision/sequence');s.service=s.env.require('bots/laning/vision/service');
    s.phase=s.env.require('bots/laning/vision/phase');s.state=s.broker.State(s.bot);
    function s:coverage()
        local w=self.unit('npc_dota_sentry_wards',self.bot.team,0,0);w.id=7;self.wards={w};return w;
    end;
    function s:enemy(x,y,kind)
        local w=self.unit(kind=='observer' and 'npc_dota_observer_wards' or 'npc_dota_sentry_wards',self.bot.team==2 and 3 or 2,x or 100,y or 0);
        w.hp=2;w.maxhp=2;self.enemies[#self.enemies+1]=w;return w;
    end;
    s.bot.Action_AttackUnit=function(_,target,once) eq(once,true);s.orders[#s.orders+1]={kind='attack',target=target};s.attack=target;s.action=3 end;
    function s:placeSentry()
        self:item('item_ward_sentry',0);self:item('item_ward_observer',1);
        assert(self.service.GetDesire(self.bot)>0);self.service.Start(self.bot);self.mode=20;self.service.Think(self.bot);
        eq(self.orders[1].ward_kind,'sentry');self:advance(.05);self.service.Poll(self.bot,self.state);
    end;
    function s:startFollowup()
        assert(self.service.GetDesire(self.bot)>0);self.service.Start(self.bot);eq(self.state.vision_support.kind,'sentry_followup');self.service.Think(self.bot);
    end;
    return s;
end;
test('production default enables Sentry-first policy',function()
    local c=assert(loadfile('laning/vision/config.lua'))();eq(c.sentry_first,true);
end);
test('both sides place Sentry before Observer even when Observer is already ready',function()
    for _,team in ipairs({2,3}) do local s=scenario(team);s:placeSentry();s:advance(.4);
        eq(s.seq.ObserverAllowed(s.bot),true);s.service.Start(s.bot);s.service.Think(s.bot);
        eq(#s.orders,2);eq(s.orders[2].ward_kind,'observer');
    end;
end);
test('missing Sentry blocks both Observer approach and the tactical direct executor',function()
    local s=scenario();s:item('item_ward_observer',0);
    eq(s.phase.GetDesire(s.bot),0);eq(s:mod('wards').Plan(s.bot),nil);eq(#s.orders,0);
    s.time=45;s.env.require('bots/laning/vision/sentry').Check(s.bot);s.time=60;s:item('item_ward_sentry',6);s.creeps={s.unit('npc_dota_creep_badguys_melee',3,200,0)};
    eq(s.phase.GetDesire(s.bot),0);eq(s.service.GetDesire(s.bot),0);eq(#s.orders,0);
end);
test('missing Sentry cancels an Observer approach without clearing native orders',function()
    local s=scenario();s:coverage();s:item('item_ward_observer',0);s.phase.Start(s.bot);assert(s.state.vision_phase);
    s.mode=20;s.wards={};eq(s.phase.GetDesire(s.bot),0);eq(s.state.vision_phase,nil);eq(#s.orders,0);
end);
test('visible local enemy Sentry receives two attacks despite a new creep wave',function()
    local s=scenario();local w=s:enemy();s:placeSentry();s.creeps={s.unit('npc_dota_creep_badguys_melee',3,200,0)};
    s:startFollowup();eq(s.orders[2].kind,'attack');eq(s.seq.ObserverAllowed(s.bot),false);
    w.hp=1;s:advance(.8);s.service.Think(s.bot);eq(s.orders[3].kind,'attack');eq(#s.orders,3);
    w.hp=0;s:advance(.2);s.service.Poll(s.bot,s.state);eq(s.state.sentry_followup,nil);eq(s.state.vision_support,nil);
    s.action=0;s.attack=nil;eq(s.seq.ObserverAllowed(s.bot),true);
    s.time=45;s.env.require('bots/laning/vision/recovery').Poll(s.bot,s.state);s.time=60;
    eq(s.phase.GetDesire(s.bot),0);s.creeps={};s:advance(.2);assert(s.phase.GetDesire(s.bot)>0);
end);
test('one attack suffices for an already damaged Sentry and kill credit remains unknown',function()
    local s=scenario();local w=s:enemy();w.hp=1;s:placeSentry();s:startFollowup();w.hp=0;s:advance(.1);s.service.Poll(s.bot,s.state);
    eq(#s.orders,2);eq(s.state.sentry_followup,nil);assert(table.concat(s.logs,'\n'):find('"own_kill_credit":"unknown"',1,true));
end);
test('unchanged HP never creates a third attack or fictitious destruction',function()
    local s=scenario();s:enemy();s:placeSentry();s:startFollowup();s:advance(2.6);s.service.Think(s.bot);eq(#s.orders,3);
    s:advance(.5);s.service.Think(s.bot);eq(#s.orders,3);s:advance(2);s.service.Poll(s.bot,s.state);eq(s.state.sentry_followup,nil);
    eq(s.seq.ObserverAllowed(s.bot),false);assert(not table.concat(s.logs,'\n'):find('deward_destroyed_observed',1,true));
end);
test('newly revealed Sentry may appear during bounded reveal grace',function()
    local s=scenario();s:placeSentry();eq(s.seq.ObserverAllowed(s.bot),false);s:advance(.2);s:enemy();s:startFollowup();eq(s.orders[2].kind,'attack');
end);
test('no local target releases Observer after reveal grace without an attack',function()
    local s=scenario();s:placeSentry();s:advance(.4);s.service.Poll(s.bot,s.state);eq(s.state.sentry_followup,nil);
    eq(s.seq.ObserverAllowed(s.bot),true);eq(#s.orders,1);
end);
test('local cleanup never chases a Sentry outside attack range',function()
    local s=scenario();s.bot.x=-300;s:enemy(300);s:placeSentry();s:advance(.4);s.service.Poll(s.bot,s.state);
    eq(s.state.sentry_followup,nil);eq(#s.orders,1);eq(s.seq.ObserverAllowed(s.bot),false);
end);
test('target at actual attack-range edge is attacked without a positioning step',function()
    local s=scenario();s.bot.x=-200;s:enemy(325);s:placeSentry();s:startFollowup();eq(#s.orders,2);eq(s.orders[2].kind,'attack');
end);
test('death retreat direct hero threat and incoming projectile preempt the second hit',function()
    for _,why in ipairs({'dead','retreat','hero','projectile','unknown'}) do
        local s=scenario();local w=s:enemy();s:placeSentry();s:startFollowup();w.hp=1;s:advance(.8);
        if why=='dead' then s.hp=0 elseif why=='retreat' then s.mode=4
        elseif why=='hero' then s.heroes={s.unit('npc_dota_hero_lina',3,300,0)}
        elseif why=='projectile' then s.projectiles={{caster=s.unit('npc_dota_hero_lina',3,900,0)}}
        else s.bot.GetNearbyTowers=function() return nil end end;
        s.service.Think(s.bot);eq(#s.orders,2);eq(s.state.sentry_followup,nil);
    end;
end);
test('hidden enemy wards never contribute locations or success evidence',function()
    local s=scenario();local w=s:enemy();s:placeSentry();s:startFollowup();w.visible=false;w.GetLocation=function() error('hidden position') end;
    s:advance(.1);s.service.Poll(s.bot,s.state);eq(s.state.sentry_followup,nil);eq(#s.orders,2);eq(s.seq.ObserverAllowed(s.bot),true);
    assert(not table.concat(s.logs,'\n'):find('deward_destroyed_observed',1,true));
end);
test('recovery retries Observer in the next minute after farm preemption',function()
    local s=scenario();s:coverage();s:item('item_ward_observer',0);s.time=45;
    local recovery=s.env.require('bots/laning/vision/recovery');recovery.Poll(s.bot,s.state);s.time=60;
    s.creeps={s.unit('npc_dota_creep_badguys_melee',3,100,0)};eq(s.phase.GetDesire(s.bot),0);s.time=91;s.creeps={};eq(s.phase.GetDesire(s.bot),0);
    s.time=105;recovery.Poll(s.bot,s.state);s.time=120;assert(s.phase.GetDesire(s.bot)>0);eq(#s.orders,0);
end);
test('normal deward still yields to farm and never receives the local exception',function()
    local s=scenario();s:coverage();s:enemy(100,0,'observer');s.time=45;s.service.Poll(s.bot,s.state);s.time=60;
    s.service.Start(s.bot);eq(s.state.vision_support.kind,'deward');s.mode=20;s.service.Think(s.bot);eq(s.orders[1].kind,'attack');
    s.creeps={s.unit('npc_dota_creep_badguys_melee',3,200,0)};s:advance(.8);eq(s.service.Holds(s.bot,s.state),false);eq(#s.orders,1);
end);
test('ordinary Observer yields to farm even after Sentry coverage is ready',function()
    local s=scenario();s:coverage();s:item('item_ward_observer',0);s.time=45;s.env.require('bots/laning/vision/recovery').Poll(s.bot,s.state);s.time=60;s.creeps={s.unit('npc_dota_creep_badguys_melee',3,100,0)};
    eq(s.phase.GetDesire(s.bot),0);eq(#s.orders,0);
end);
test('Observer dispenser toggle does not abort its own phase as busy',function()
    local s=scenario();s:coverage();local item=s:item('item_ward_dispenser',0,{charges=1,secondary=0,toggle=false});
    local orig=s.bot.Action_UseAbilityOnEntity;s.bot.Action_UseAbilityOnEntity=function(bot,it,target) orig(bot,it,target);s.active=it;s.using=true;s.queued=1 end;
    s.service.Start(s.bot);s.mode=20;s.service.Think(s.bot);eq(#s.orders,1);s:advance(.1);s:mod('wards').Poll(s.bot,s.state);
    eq(s.service.Holds(s.bot,s.state),true);s.service.Think(s.bot);eq(#s.orders,1);
    s.active=nil;s.using=false;s.queued=0;s:advance(1);s.service.Think(s.bot);eq(s.orders[2].ward_kind,'observer');
end);
test('unknown allied ward census or enemy list blocks speculative Observer placement',function()
    for _,why in ipairs({'allied','enemy'}) do local s=scenario();s:coverage();s:item('item_ward_observer',0);
        s.env.GetUnitList=function(kind) if (why=='allied' and kind==4) or (why=='enemy' and kind==99) then return nil end;return kind==99 and {} or s.wards end;
        eq(s.seq.ObserverAllowed(s.bot),false);eq(s.phase.GetDesire(s.bot),0);eq(#s.orders,0);
    end;
end);
test('existing allied coverage alone never arms the farm-priority exception',function()
    local s=scenario();s:coverage();s:enemy();s.time=45;s.service.Poll(s.bot,s.state);eq(s.state.sentry_followup,nil);
    s.time=60;s.creeps={s.unit('npc_dota_creep_badguys_melee',3,100,0)};eq(s.service.GetDesire(s.bot),0);eq(#s.orders,0);
end);
test('losing range between the two attacks ends cleanup without chase',function()
    local s=scenario();local w=s:enemy();s:placeSentry();s:startFollowup();w.hp=1;s.bot.x=-1000;s:advance(.8);
    s.service.Think(s.bot);eq(#s.orders,2);eq(s.state.sentry_followup,nil);
end);
test('startup combined wards use self-targeted switch, readback, then both placements',function()
    local s=scenario();local it=s:item('item_ward_dispenser',0,{charges=1,secondary=1,toggle=true});
    s.service.Start(s.bot);s.mode=20;s.service.Think(s.bot);eq(s.orders[1].kind,'entity');eq(it.charges,1);eq(it.secondary,1);
    s:advance(.6);s.service.Think(s.bot);eq(s.orders[2].ward_kind,'sentry');eq(it.charges,1);eq(it.secondary,0);
    s:advance(.1);s.service.Poll(s.bot,s.state);s:advance(.4);s.service.Start(s.bot);s.service.Think(s.bot);
    eq(s.orders[3].kind,'entity');s:advance(1.1);s.service.Think(s.bot);eq(s.orders[4].ward_kind,'observer');eq(it.charges,0);
end);
test('the former no-target dispenser command does not change mode in the regression fixture',function()
    local s=scenario();local it=s:item('item_ward_dispenser',0,{charges=1,secondary=1,toggle=true});
    s.bot:Action_UseAbility(it);eq(it.toggle,true);eq(it.secondary,1);s.bot:Action_UseAbilityOnEntity(it,s.bot);eq(it.toggle,false);eq(it.secondary,1);
end);
local function weakEnemy(s,x)
    local e=s.unit('npc_dota_hero_lina',s.bot.team==2 and 3 or 2,x or 600,0);
    e.GetAttackDamage=function() return 45 end;e.GetMana=function() return 0 end;return e;
end;
test('startup ward outranks farm rune mode and routine attacks despite affordable poke',function()
    local s=scenario();s:item('item_ward_sentry',0);s:item('item_tango',1,{charges=2});s.hp=480;s.recent=0;s.mode=7;s.action=3;
    s.creeps={s.unit('npc_dota_creep_badguys_melee',3,100,0)};s.attack=s.creeps[1];s.heroes={weakEnemy(s)};
    eq(s.service.GetDesire(s.bot),s.v.ward_start_desire);eq(#s.orders,0);
end);
test('recovery permits a single weak enemy and recent poke but still yields to accessible farm',function()
    local s=scenario();s:item('item_ward_sentry',0);s.hp=800;s.recent=0;s.heroes={weakEnemy(s)};
    s.time=45;s.env.require('bots/laning/vision/sentry').Check(s.bot);s.time=60;
    assert(s.service.GetDesire(s.bot)>0);s.creeps={s.unit('npc_dota_creep_badguys_melee',3,200,0)};
    eq(s.service.GetDesire(s.bot),0);eq(#s.orders,0);
end);
test('startup extends the bounded approach to reach mid instead of waiting for native movement',function()
    local s=scenario();s.bot.x=-1600;s.bot.y=-1000;s:item('item_ward_sentry',0);
    assert(s.service.GetDesire(s.bot)>.9);s.time=45;s.env.require('bots/laning/vision/sentry').Check(s.bot);s.time=60;
    eq(s.service.GetDesire(s.bot),0);eq(#s.orders,0);
end);
test('Tango is not instantaneous survival health and serious danger still blocks startup',function()
    for _,why in ipairs({'low','burst','two','spell','tower','unknown'}) do
        local s=scenario();s:item('item_ward_sentry',0);s:item('item_tango',1,{charges=3});local e=weakEnemy(s);s.heroes={e};
        if why=='low' then s.hp=200 elseif why=='burst' then e.GetAttackDamage=function() return 1000 end
        elseif why=='two' then s.heroes[2]=weakEnemy(s,700)
        elseif why=='spell' then s.projectiles={{caster=e,is_attack=false}}
        elseif why=='tower' then s.towers={s.unit('npc_dota_badguys_tower1_mid',3,100,0)}
        else e.GetAttackDamage=nil end;
        eq(s.service.GetDesire(s.bot),0);eq(#s.orders,0);
    end;
end);
print('WARD_SEQUENCE PASSED '..n..' cases; new game test required');
