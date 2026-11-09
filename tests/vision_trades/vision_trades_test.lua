local n=0;
local function eq(a,b) assert(a==b,tostring(a).." ~= "..tostring(b)) end;
local function test(name,fn) fn();n=n+1;print("PASS VISION_TRADES "..name) end;
local function scenario()
    local s=SCENARIO();s.time=0;s.env.TEAM_RADIANT=2;s.env.TEAM_DIRE=3;s.env.BOT_MODE_WARD=20;s.env.UNIT_LIST_ENEMIES=99;
    s.enemies={};s.env.GetUnitList=function(kind) return kind==99 and s.enemies or s.wards end;
    s.env.GetNumCouriers=function() return 0 end;s.env.GetHeightLevel=function(p) return math.abs(p.y)<200 and 1 or 3 end;
    s.env.GetItemStockCount=function() return s.shop end;s.shop=2;s.gold=500;
    s.env.GetItemCost=function() return 50 end;s.env.PURCHASE_ITEM_SUCCESS=0;
    s.bot.GetGold=function() return s.gold end;s.buy={};
    s.bot.ActionImmediate_PurchaseItem=function(_,name) s.buy[#s.buy+1]=name;return s.buy_result end;s.buy_result=0;
    local p=s.env.require('bots/laning/profile');p.wards_enabled=true;p.ward_phase_enabled=true;p.runtime_enabled=false;
    s.v=s.env.require('bots/laning/vision/config');s.v.calibration_only=false;s.v.sentry_use_rune_midpoint=false;
    function s:vmod(name) return self.env.require('bots/laning/vision/'..name) end;
    s.sentry=s:vmod('sentry');s.service=s:vmod('service');s.deward=s:vmod('deward');
    s.state=s.broker.State(s.bot);
    function s:enemyWard(kind,x,y)
        local w=self.unit(kind=='sentry' and 'npc_dota_sentry_wards' or 'npc_dota_observer_wards',3,x or 100,y or 0);
        w.hp=2;w.maxhp=2;self.enemies[#self.enemies+1]=w;return w;
    end;
    function s:attackFixture()
        self.bot.Action_AttackUnit=function(_,target,once) eq(once,true);self.orders[#self.orders+1]={kind='attack',target=target};self.attack=target;self.action=3 end;
    end;
    function s:scan()
        self.time=45;self.deward.Scan(self.bot,self.state);self.time=60;self.state=self.broker.State(self.bot);
    end;
    return s;
end;

test('both unknown points stay disabled and Radiant coordinate stays unchanged',function()
    local s=scenario();local site=s:vmod('site');eq(s.v.fixed_location.x,-216.73818969727);eq(s.v.fixed_location.y,-990.77404785156);
    s.bot.team=3;eq(site.Participant(s.bot),true);eq(site.ObserverSupported(s.bot),false);eq(site.Geometry(s.bot),nil);
    eq(s.sentry.Candidate(s.bot),nil);eq(#s.orders,0);
end);
test('calibrated Dire Observer geometry is separate from Radiant cache',function()
    local s=scenario();s.v.dire_fixed_location={x=400,y=900,z=128};local site=s:vmod('site');local r=site.Geometry(s.bot);
    s.bot.team=3;local d=site.Geometry(s.bot);eq(d.location.x,400);eq(d.location.y,900);eq(r.location.x,s.v.fixed_location.x);
end);
test('human Observer and Sentry are logged remotely for Dire without adopting either',function()
    local s=scenario();s.bot.team=3;s.bot.x=7000;s.bot.y=7000;
    local obs=s.unit('npc_dota_observer_wards',3,400,900);obs.id=0;obs.visible=false;
    local blue=s.unit('npc_dota_sentry_wards',3,0,0);blue.id=0;blue.visible=false;s.wards={obs,blue};
    s:vmod('diagnostics').Tick(s.bot,s.state);local logs=table.concat(s.logs,'\n');
    assert(logs:find('"kind":"observer"',1,true));assert(logs:find('"kind":"sentry"',1,true));assert(logs:find('"sf_team":3',1,true));
    eq(s.v.dire_fixed_location,nil);eq(s.v.sentry_fixed_location,nil);eq(#s.orders,0);
end);
test('startup Sentry is bought once even while its placement coordinate is pending',function()
    local s=scenario();eq(s.sentry.TryStartup(s.bot),true);eq(s.buy[1],'item_ward_sentry');
    for i=1,100 do s:advance(.1);s.sentry.TryStartup(s.bot) end;eq(#s.buy,1);
end);
test('starting Sentry already carried or in courier is not bought again',function()
    for _,where in ipairs({'active','courier','backpack','stash'}) do
        local s=scenario();local it=s:item('item_ward_sentry',where=='active' and 0 or where=='backpack' and 6 or 9);
        if where=='courier' then s.items[9]=nil;s.env.GetNumCouriers=function() return 1 end;
            s.env.GetCourier=function() return {GetPlayerID=function() return 7 end,GetItemInSlot=function(_,slot) return slot==0 and it or nil end} end end;
        eq(s.sentry.TryStartup(s.bot),false);eq(#s.buy,0);
    end;
end);
test('missing gold and shop stock wait for the next minute check',function()
    for _,why in ipairs({'gold','stock','unknown'}) do
        local s=scenario();s.v.sentry_fixed_location={x=0,y=0,z=0};s.time=45;
        if why=='gold' then s.gold=49 elseif why=='stock' then s.shop=0 else s.shop=nil end;
        eq(s.sentry.TryPurchase(s.bot),false);eq(#s.buy,0);s.gold=50;s.shop=2;s.time=60;
        eq(s.sentry.TryPurchase(s.bot),false);s.time=105;eq(s.sentry.TryPurchase(s.bot),true);eq(#s.buy,1);
    end;
end);
test('pending unknown purchase never duplicates at subsequent checks',function()
    local s=scenario();s.v.sentry_fixed_location={x=0,y=0,z=0};s.buy_result=nil;s.time=45;
    eq(s.sentry.TryPurchase(s.bot),true);for _,time in ipairs({105,165,225}) do s.time=time;s.sentry.TryPurchase(s.bot) end;eq(#s.buy,1);
end);
test('Sentry prefetch begins at4:30 and refresh can overlap the old ward at6',function()
    local s=scenario();s.v.sentry_fixed_location={x=0,y=0,z=0};s.wards={s.unit('npc_dota_sentry_wards',2,0,0)};
    s.time=269;eq(s.sentry.TryPurchase(s.bot),false);s.time=270;eq(s.sentry.TryPurchase(s.bot),true);
    s:item('item_ward_sentry',0);s.time=360;local job=s.sentry.Candidate(s.bot);assert(job);eq(job.window.start,360);
end);
test('no pregame placement, one primary placement, readback required, expires at7min',function()
    local s=scenario();s.v.sentry_fixed_location={x=0,y=0,z=0};s:item('item_ward_sentry',0);s.time=-1;eq(s.sentry.Candidate(s.bot),nil);
    s.time=0;local job=s.sentry.Candidate(s.bot);assert(job);s.sentry.Execute(s.bot,s.state,job);eq(#s.orders,1);
    eq(s.sentry.Poll(s.bot,s.state,job),true);eq(s.sentry.Candidate(s.bot),nil);
    assert(table.concat(s.logs,'\n'):find('"expires_at":420',1,true));
end);
test('recovery is global read-only atxx45 and stops at12min',function()
    local s=scenario();s.v.sentry_fixed_location={x=0,y=0,z=0};s.bot.x=7000;s.bot.y=7000;s.time=45;
    s.sentry.Check(s.bot);eq(#s.orders,0);s.bot.x=0;s.bot.y=0;s:item('item_ward_sentry',0);s.time=60;assert(s.sentry.Candidate(s.bot));
    s.time=720;eq(s.sentry.Candidate(s.bot),nil);eq(s.sentry.TryPurchase(s.bot),false);
end);
test('Sentry jobs yield to farm enemy heroes retreat rune and unknown safety',function()
    for _,why in ipairs({'creeps','neutral','enemy','retreat','rune','unknown'}) do
        local s=scenario();s.v.sentry_fixed_location={x=0,y=0,z=0};s:item('item_ward_sentry',0);
        if why=='creeps' then s.creeps={s.unit('npc_dota_creep_badguys_melee',3,100,0)}
        elseif why=='neutral' then s.neutrals={s.unit('npc_dota_neutral_centaur_khan',4,100,0)}
        elseif why=='enemy' then s.heroes={s.unit('npc_dota_hero_lina',3,100,0)}
        elseif why=='retreat' then s.mode=4 elseif why=='rune' then s.mode=7 else s.bot.GetNearbyTowers=function() return nil end end;
        eq(s.sentry.Candidate(s.bot),nil);eq(#s.orders,0);
    end;
end);
test('hidden enemy wards never become candidates; visible Sentry outranks Observer',function()
    local s=scenario();local obs=s:enemyWard('observer',60);local blue=s:enemyWard('sentry',100);local hidden=s:enemyWard('sentry',30);hidden.visible=false;
    s:scan();local job=s.deward.Candidate(s.bot,s.state);assert(job);eq(job.target,blue);blue.visible=false;
    job=s.deward.Candidate(s.bot,s.state);eq(job.target,obs);obs.visible=false;eq(s.deward.Candidate(s.bot,s.state),nil);
end);
test('two submitted attacks with actual HP changes are required for a full health ward',function()
    local s=scenario();local w=s:enemyWard('sentry');s:attackFixture();s:scan();local job=s.deward.Candidate(s.bot,s.state);assert(job);
    s.deward.Execute(s.bot,s.state,job);eq(#s.orders,1);eq(s.deward.Destroyed(s.bot,s.state,job),false);
    s:advance(.1);s.deward.Execute(s.bot,s.state,job);eq(#s.orders,1);w.hp=1;s:advance(.7);
    s.deward.Execute(s.bot,s.state,job);eq(#s.orders,2);eq(s.deward.Destroyed(s.bot,s.state,job),false);
    w.hp=0;eq(s.deward.Destroyed(s.bot,s.state,job),true);
end);
test('fog or disappearing handle after first attack is not a confirmed deward',function()
    for _,why in ipairs({'fog','null'}) do
        local s=scenario();local w=s:enemyWard('sentry');s:attackFixture();s:scan();local job=s.deward.Candidate(s.bot,s.state);
        s.deward.Execute(s.bot,s.state,job);if why=='fog' then w.visible=false else w.IsNull=function() return true end end;
        s:advance(3);s.deward.Execute(s.bot,s.state,job);eq(#s.orders,1);eq(s.deward.Destroyed(s.bot,s.state,job),false);
    end;
end);
test('farm arriving between two attacks preempts the whole deward until next window',function()
    local s=scenario();local w=s:enemyWard('sentry');s:attackFixture();s:scan();s.service.Start(s.bot);s.mode=20;
    s.service.Think(s.bot);eq(#s.orders,1);w.hp=1;s:advance(.7);s.creeps={s.unit('npc_dota_creep_badguys_melee',3,100,0)};
    eq(s.service.Holds(s.bot,s.state),false);eq(s.state.vision_support,nil);s.creeps={};s.action=0;s.attack=nil;
    eq(s.deward.Candidate(s.bot,s.state),nil);eq(#s.orders,1);
end);
test('13plus known charges authorize safe local Raze trading without movement orders',function()
    local s=scenario();s:item('item_magic_wand',0,{charges=13,special={restore_per_charge=15}});s.mana=100;
    local e=s.unit('npc_dota_hero_lina',3,200,0);s.heroes={e};local d,p,a=s:mod('trades').Consider(s.bot,s.state);
    eq(d,s.env.BOT_ACTION_DESIRE_HIGH);assert(p and a);eq(#s.orders,0);
end);
test('charge count is not blanket permission to fight under towers or while weak',function()
    for _,why in ipairs({'12','unknown','weak','tower','two','illusion','unaffordable','retreat'}) do
        local s=scenario();local wand=s:item('item_magic_wand',0,{charges=13,special={restore_per_charge=15}});
        local e=s.unit('npc_dota_hero_lina',3,200,0);s.heroes={e};s.mana=100;
        if why=='12' then wand.charges=12 elseif why=='unknown' then wand.special={} elseif why=='weak' then s.hp=400
        elseif why=='tower' then s.towers={s.unit('npc_dota_badguys_tower1_mid',3,300,0)}
        elseif why=='two' then s.heroes[2]=s.unit('npc_dota_hero_viper',3,300,0) elseif why=='illusion' then e.illusion=true
        elseif why=='unaffordable' then s.mana=10 else s.mode=4 end;
        eq(s:mod('trades').Consider(s.bot,s.state),nil);eq(#s.orders,0);
    end;
end);
test('charged Wand is spent on a useful combat trade before HP reaches15percent',function()
    local s=scenario();s:item('item_magic_wand',0,{charges=17,special={restore_per_charge=15}});s.hp=650;
    s.heroes={s.unit('npc_dota_hero_lina',3,200,0)};eq(s:mod('resources').Emergency(s.bot,s.state),true);eq(s.orders[1].ability,'item_magic_wand');
end);
test('full resources calm situations and empty charges do not waste a Wand',function()
    for _,why in ipairs({'calm','full','empty'}) do
        local s=scenario();local wand=s:item('item_magic_wand',0,{charges=17,special={restore_per_charge=15}});
        if why=='calm' then s.hp=650 else s.heroes={s.unit('npc_dota_hero_lina',3,200,0)} end;
        if why=='empty' then wand.charges=0;s.hp=650 end;
        eq(s:mod('resources').Emergency(s.bot,s.state),false);eq(#s.orders,0);
    end;
end);
test('actual bound root can turn a declined ordinary Raze into a safe charged-Wand trade',function()
    local s=scenario();s:item('item_magic_wand',0,{charges=13,special={restore_per_charge=15}});s.mana=300;
    local vector={};vector.__add=function(a,b) return s.env.Vector(a.x+b.x,a.y+b.y,(a.z or 0)+(b.z or 0)) end;
    s.env.Vector=function(x,y,z) return setmetatable({x=x,y=y,z=z or 0},vector) end;
    s.bot.GetLocation=function() return s.env.Vector(s.bot.x,s.bot.y,0) end;
    s.heroes={s.unit('npc_dota_hero_lina',3,200,0)};s.abilities.nevermore_requiem.level=0;
    local require=s.env.require;s.env.require=function(path)
        if path=='bots/laning/tactical/entry' then return {BindLegacy=function() return true end} end;return require(path);
    end;
    local root=assert(loadfile(CURRENT_OWNER_SOURCE));setfenv(root,s.env);root();s.env.require=require;
    s.env.ConsiderRazeOnHero=function() return 0 end;s.env.ConsiderRazeOnCreeps=function() return 0 end;s.env.ConsiderFeastOfSouls=function() return 0 end;
    assert(s:mod('entry').BindLegacy(s.env));
    s.env.AbilityUsageThink();assert(#s.orders==1,table.concat(s.logs,'\n'));eq(s.orders[1].ability,'nevermore_shadowraze1');
end);
test('basic Stick also spends7charges in a useful combat trade',function()
    local s=scenario();s:item('item_magic_stick',0,{charges=7,special={restore_per_charge=15}});s.hp=850;
    s.heroes={s.unit('npc_dota_hero_lina',3,200,0)};eq(s:mod('resources').Emergency(s.bot,s.state),true);eq(s.orders[1].ability,'item_magic_stick');
end);
test('merged dispenser uses secondary charges for Sentry and primary for Observer',function()
    local s=scenario();local i=s:item('item_ward_dispenser',0,{charges=2,secondary=1});local items=s:vmod('ward_items');
    eq(items.Charges(i,'observer'),2);eq(items.Charges(i,'sentry'),1);eq(items.Stock(s.bot,'sentry').total,1);
end);
test('wrong dispenser mode toggles before placement and never guesses unknown mode',function()
    local s=scenario();s.v.sentry_fixed_location={x=0,y=0,z=0};local it=s:item('item_ward_dispenser',0,{charges=1,secondary=1,toggle=true});
    local job=s.sentry.Candidate(s.bot);s.sentry.Execute(s.bot,s.state,job);eq(#s.orders,1);eq(s.orders[1].kind,'self');
    s:advance(.6);s.sentry.Execute(s.bot,s.state,job);eq(s.orders[2].ward_kind,'sentry');
    local t=scenario();t.v.sentry_fixed_location={x=0,y=0,z=0};local item=t:item('item_ward_dispenser',0,{charges=1,secondary=1});
    item.GetToggleState=function() return nil end;local plan=t.sentry.Candidate(t.bot);t.sentry.Execute(t.bot,t.state,plan);eq(#t.orders,0);
end);
test('foreign placement without our charge consumption is not accepted',function()
    local s=scenario();s.v.sentry_fixed_location={x=0,y=0,z=0};s:item('item_ward_sentry',0);local job=s.sentry.Candidate(s.bot);
    s.bot.Action_UseAbilityOnLocation=function() local w=s.unit('npc_dota_sentry_wards',2,0,0);w.id=0;s.wards={w} end;
    s.sentry.Execute(s.bot,s.state,job);eq(s.sentry.Poll(s.bot,s.state,job),false);eq(s.sentry.Candidate(s.bot),nil);
end);
test('high ground or unwalkable Sentry coordinate cannot cause placement',function()
    for _,why in ipairs({'high','blocked'}) do local s=scenario();s.v.sentry_fixed_location={x=0,y=0,z=0};s:item('item_ward_sentry',0);
        if why=='high' then s.env.GetHeightLevel=function() return 3 end else s.env.IsLocationPassable=function() return false end end;
        eq(s.sentry.Candidate(s.bot),nil);eq(#s.orders,0);
    end;
end);
test('revealed enemy ward scan cannot order attacks or check a hidden ward through fog',function()
    local s=scenario();local w=s:enemyWard('sentry');w.visible=false;
    w.GetLocation=function() error('hidden location must not be read') end;s.time=45;s.deward.Scan(s.bot,s.state);
    eq(#s.state.deward_candidates,0);eq(#s.orders,0);
end);
test('a damaged ward may die in one hit and never receives a fictitious second order',function()
    local s=scenario();local w=s:enemyWard('observer');w.hp=1;s:attackFixture();s:scan();local job=s.deward.Candidate(s.bot,s.state);
    s.deward.Execute(s.bot,s.state,job);w.hp=0;eq(s.deward.Destroyed(s.bot,s.state,job),true);eq(#s.orders,1);
end);
test('retreat immediately ends a deward job even between its two hits',function()
    local s=scenario();local w=s:enemyWard('observer');s:attackFixture();s:scan();s.service.Start(s.bot);s.mode=20;s.service.Think(s.bot);
    w.hp=1;s:advance(.8);s.mode=4;eq(s.service.Holds(s.bot,s.state),false);eq(#s.orders,1);eq(s.state.vision_support,nil);
end);
test('unchanging ward HP has bounded attempts and mode lease',function()
    local s=scenario();s:enemyWard('observer');s:attackFixture();s:scan();s.service.Start(s.bot);s.mode=20;
    for i=1,100 do s.service.Think(s.bot);s:advance(.1) end;
    assert(#s.orders<=4);eq(s.state.vision_support,nil);
end);
test('Wand trade recovery does not issue movement and keeps empty-item protection',function()
    local s=scenario();local it=s:item('item_magic_stick',0,{charges=7,special={restore_per_charge=15}});s.hp=850;s.heroes={s.unit('npc_dota_hero_lina',3,200,0)};
    local r=s:mod('resources');local p=r.Read(s.bot,s.state);it.charges=0;eq(r.Use(s.bot,s.state,p,'stale_trade'),false);eq(#s.orders,0);
end);
test('basic Stick starts trading at7 while upgraded Wand still needs13',function()
    for _,case in ipairs({{'item_magic_stick',6,false},{'item_magic_stick',7,true},{'item_magic_wand',12,false},{'item_magic_wand',13,true}}) do
        local s=scenario();s:item(case[1],0,{charges=case[2],special={restore_per_charge=15}});s.mana=100;
        s.heroes={s.unit('npc_dota_hero_lina',3,200,0)};
        local d=s:mod('trades').Consider(s.bot,s.state);eq(d~=nil,case[3]);eq(#s.orders,0);
    end;
end);
test('real purchase callback adds exactly one starting Sentry alongside its Observer queue',function()
    local s=scenario();s.gold=100000;s.bot.SetNextItemPurchaseValue=function() end;s.env.GetItemComponents=function() return {} end;
    s.bot.ActionImmediate_PurchaseItem=function(_,name)
        s.buy[#s.buy+1]=name;
        if name=='item_ward_observer' then s:item(name,0) elseif name=='item_ward_sentry' then s:item(name,1) end;
        return 0;
    end;
    local f=assert(loadfile('item_purchase_nevermore.lua'));setfenv(f,s.env);f();
    for i=1,25 do s.env.ItemPurchaseThink();s:advance(.5) end;
    local observer,blue=0,0;for _,name in ipairs(s.buy) do if name=='item_ward_observer' then observer=observer+1 elseif name=='item_ward_sentry' then blue=blue+1 end end;
    eq(observer,1);eq(blue,1);eq(s.buy[1],'item_tango');
    assert(not table.concat(s.logs,'\n'):find('ERROR',1,true));
end);
test('calibrated Dire can place its Observer through the actual ward mode and readback',function()
    local s=scenario();s.bot.team=3;s.v.dire_fixed_location={x=0,y=300,z=128};s:item('item_ward_observer',0);
    assert(s.service.GetDesire(s.bot)>0);s.mode=20;s.service.Start(s.bot);s.service.Think(s.bot);
    eq(s.orders[1].ward_kind,'observer');eq(s.wards[1].team,3);s:advance();s:mod('wards').Poll(s.bot,s.state);
    eq(s.state.vision_done_slot,0);
end);
test('calibrated Sentry placement is identical for both teams',function()
    for _,team in ipairs({2,3}) do local s=scenario();s.bot.team=team;s.v.sentry_fixed_location={x=0,y=0,z=0};s:item('item_ward_sentry',0);
        local job=s.sentry.Candidate(s.bot);assert(job);s.sentry.Execute(s.bot,s.state,job);eq(s.orders[1].ward_kind,'sentry');eq(s.wards[1].team,team);
        eq(s.sentry.Poll(s.bot,s.state,job),true);
    end;
end);
test('Sentry can equip from backpack without displacing combat items then restore its passive',function()
    local s=scenario();s.v.sentry_fixed_location={x=0,y=0,z=0};local item=s:item('item_ward_sentry',6);
    local passive=s:item('item_branches',0);for i=1,5 do s:item('item_black_king_bar',i) end;
    s.bot.ActionImmediate_SwapItems=function(_,a,b) s.items[a],s.items[b]=s.items[b],s.items[a] end;
    local job=s.sentry.Candidate(s.bot);s.sentry.Execute(s.bot,s.state,job);eq(s.items[0],item);eq(#s.orders,0);
    -- Swap is an immediate API order tracked by broker even though fixture does not append it.
    s:advance(6.1);s.sentry.Execute(s.bot,s.state,job);eq(s.orders[1].ward_kind,'sentry');eq(s.sentry.Poll(s.bot,s.state,job),true);
    s:advance();eq(s.sentry.Restore(s.bot,s.state),true);eq(s.items[0],passive);
end);
test('an in-progress Sentry cast is observed without issuing a second command',function()
    local s=scenario();s.v.sentry_fixed_location={x=0,y=0,z=0};local item=s:item('item_ward_sentry',0);
    s.bot.Action_UseAbilityOnLocation=function() item.charges=0;s.using=true;s.action=5 end;
    s.service.Start(s.bot);s.mode=20;s.service.Think(s.bot);assert(s.state.vision_support.pending);
    s:advance(.1);eq(s.service.Holds(s.bot,s.state),true);eq(#s.orders,0);
    local w=s.unit('npc_dota_sentry_wards',2,0,0);w.id=7;s.wards={w};
    s.service.Poll(s.bot,s.state);eq(s.state.vision_support,nil);
    assert(table.concat(s.logs,'\n'):find('sentry_placement_observed',1,true));
end);
test('disabling tactical wards prevents all new ward purchases and deward jobs',function()
    local s=scenario();s.v.sentry_fixed_location={x=0,y=0,z=0};s:item('item_ward_sentry',0);s:enemyWard('sentry');s:scan();
    s.config.wards=false;eq(s.sentry.TryStartup(s.bot),false);eq(s.sentry.TryPurchase(s.bot),false);
    eq(s.sentry.Candidate(s.bot),nil);eq(s.deward.Candidate(s.bot,s.state),nil);eq(s.service.GetDesire(s.bot),0);eq(#s.orders,0);
end);
test('shared river midpoint works for either team without manual Sentry calibration',function()
    local s=scenario();s.v.sentry_use_rune_midpoint=true;s:item('item_ward_sentry',0);
    local a=s.sentry.Point();assert(a);eq(a.x,0);eq(a.y,0);
    s.bot.team=3;local b=s.sentry.Point();eq(a.x,b.x);eq(a.y,b.y);assert(s.sentry.Candidate(s.bot));
end);
test('unknown landmarks or non-river midpoint disable placement but not starting purchase',function()
    for _,why in ipairs({'landmarks','terrain','blocked'}) do local s=scenario();s.v.sentry_use_rune_midpoint=true;
        if why=='landmarks' then s.env.GetRuneSpawnLocation=function() return nil end
        elseif why=='terrain' then s.env.GetHeightLevel=function() return 3 end
        else s.env.IsLocationPassable=function() return false end end;
        eq(s.sentry.Point(),nil);eq(s.sentry.Candidate(s.bot),nil);eq(s.sentry.TryStartup(s.bot),true);eq(s.buy[1],'item_ward_sentry');
    end;
end);
print('VISION_TRADES PASSED '..n..' cases (new game/calibration still required)');
