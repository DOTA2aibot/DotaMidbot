local count=0;
local function eq(a,b) assert(a==b,tostring(a).." ~= "..tostring(b)) end;
local function test(name,fn) fn();count=count+1;print("PASS TACTICAL "..name) end;
local function enemy(s,x) local e=s.unit("npc_dota_hero_lina",3,x or 400,0);e.hp=300;s.heroes={e};return e end;
local function ownRequiem(s,e)
    local q=s:mod("requiem");local a=s.abilities.nevermore_requiem;
    q.Submitted(s.bot,s.state,a,{ability=a,targets={e}});a.phase=true;s.active=a;s.using=true;return q,a;
end;
test("real actor guard rejects own illusions and unknown API",function()
    local s=SCENARIO();local u=s:mod("util");eq(u.Actor(s.bot),true);s.bot.illusion=true;eq(u.Actor(s.bot),false);
    s.bot.illusion=false;s.bot.IsIllusion=nil;eq(u.Actor(s.bot),false);
end);
test("requiem selects a confirmed real enemy",function()
    local s=SCENARIO();local e=enemy(s);local desire,target=s:mod("requiem").Consider(s.bot,s.state);assert(desire>0);eq(target,e);
end);
test("requiem refuses illusion and unknown identity",function()
    for _,v in ipairs({"illusion","unknown","clone","human_unknown_id"}) do
        local s=SCENARIO();local e=enemy(s);
        if v=="illusion" then e.illusion=true elseif v=="unknown" then e.IsIllusion=nil
        elseif v=="clone" then e.modifiers.modifier_arc_warden_tempest_double=true else e.id=-1 end;
        eq(s:mod("requiem").Consider(s.bot,s.state),0);
    end;
end);
test("a real enemy after an illusion can still trigger requiem",function()
    local s=SCENARIO();local e=enemy(s);local fake=s.unit("npc_dota_hero_lina",3,300,0);fake.hp=10;fake.illusion=true;s.heroes={fake,e};
    local _,target=s:mod("requiem").Consider(s.bot,s.state);eq(target,e);
end);
test("requiem never starts on hidden or invulnerable enemies",function()
    local s=SCENARIO();local e=enemy(s);e.visible=false;eq(s:mod("requiem").Consider(s.bot,s.state),0);
    e.visible=true;e.IsInvulnerable=function() return true end;eq(s:mod("requiem").Consider(s.bot,s.state),0);
end);
test("all tracked enemies visibly out of actual range cancels once",function()
    local s=SCENARIO();local e=enemy(s);local q,a=ownRequiem(s,e);e.x=1300;
    eq(q.Tick(s.bot,s.state),false);s:advance(.2);eq(q.Tick(s.bot,s.state),true);eq(#s.orders,1);eq(s.orders[1].kind,"clear");
    s:advance();q.Tick(s.bot,s.state);eq(#s.orders,1);eq(q.Consider(s.bot,s.state),0);
end);
test("one remaining enemy preserves own requiem",function()
    local s=SCENARIO();local e=enemy(s);local q=ownRequiem(s,e);e.x=1300;
    local other=s.unit("npc_dota_hero_axe",3,600,0);s.heroes={e,other};q.Tick(s.bot,s.state);s:advance(.3);q.Tick(s.bot,s.state);eq(#s.orders,0);
end);
test("fog loss is unknown rather than a reason to cancel",function()
    local s=SCENARIO();local e=enemy(s);local q=ownRequiem(s,e);e.visible=false;e.x=1300;
    q.Tick(s.bot,s.state);s:advance(.3);q.Tick(s.bot,s.state);eq(#s.orders,0);
end);
test("target predicted to return into range preserves cast",function()
    local s=SCENARIO();local e=enemy(s);local q=ownRequiem(s,e);e.x=1300;e.vx=-400;
    q.Tick(s.bot,s.state);s:advance(.2);q.Tick(s.bot,s.state);eq(#s.orders,0);
end);
test("unknown range or movement data cannot cancel",function()
    for _,v in ipairs({"range","movement"}) do
        local s=SCENARIO();local e=enemy(s);local q,a=ownRequiem(s,e);e.x=1300;
        if v=="range" then a.special={} else e.GetExtrapolatedLocation=nil end;
        q.Tick(s.bot,s.state);s:advance(.3);q.Tick(s.bot,s.state);eq(#s.orders,0);
    end;
end);
test("unowned, queued or different active ability cannot be cancelled",function()
    for _,v in ipairs({"unowned","queue","different","channel"}) do
        local s=SCENARIO();local e=enemy(s);local q=ownRequiem(s,e);e.x=1400;
        if v=="unowned" then s.state.requiem=nil elseif v=="queue" then s.queued=1 elseif v=="different" then s.active=s.abilities.nevermore_frenzy else s.channel=true end;
        eq(q.Cancel(s.bot,s.state,"test"),false);eq(#s.orders,0);
    end;
end);
test("released requiem cannot be cancelled",function()
    local s=SCENARIO();local e=enemy(s);local q,a=ownRequiem(s,e);s:release(a);s:advance(.6);eq(q.Tick(s.bot,s.state),false);eq(#s.orders,0);
end);
test("cancellation requires a stable out-of-range interval",function()
    local s=SCENARIO();local e=enemy(s);local q=ownRequiem(s,e);e.x=1300;q.Tick(s.bot,s.state);
    s:advance(.1);e.x=900;q.Tick(s.bot,s.state);s:advance(.1);e.x=1300;q.Tick(s.bot,s.state);eq(#s.orders,0);
end);
test("mana budgets use current costs and learned levels",function()
    local s=SCENARIO();local m=s:mod("mana");eq(m.Budget(s.bot,false),225);eq(m.Budget(s.bot,true),445);
    s.abilities.nevermore_shadowraze1.cost=90;eq(m.Budget(s.bot,false),240);
    s.abilities.nevermore_requiem.level=0;eq(m.Budget(s.bot,true),310);
end);
test("clarity used in safe situation below three-raze budget",function()
    local s=SCENARIO();s.mana=150;s:item("item_clarity",0,{behavior=8});eq(s:mod("mana").Tick(s.bot,s.state),true);eq(s.orders[1].ability,"item_clarity");
end);
test("clarity blocked near enemy, recent damage and active regeneration",function()
    for _,v in ipairs({"enemy","recent","regen","unknown","tower","projectile"}) do
        local s=SCENARIO();s.mana=50;s:item("item_clarity",0,{behavior=8});
        if v=="enemy" then enemy(s,950) elseif v=="recent" then s.recent=1 elseif v=="regen" then s.bot.modifiers.modifier_clarity_potion=true
        elseif v=="unknown" then s.enemies_unknown=true elseif v=="tower" then local t=s.unit("tower",3,300,0);t.range=700;s.towers={t}
        else s.projectiles={{is_attack=true}} end;
        eq(s:mod("mana").Tick(s.bot,s.state),false);eq(#s.orders,0);
    end;
end);
test("mana already covers budget so consumables are kept",function()
    local s=SCENARIO();s.mana=500;enemy(s);s:item("item_enchanted_mango",0);eq(s:mod("mana").Tick(s.bot,s.state),false);
end);
test("mango consumed in combat for full-combo deficit",function()
    local s=SCENARIO();s.mana=250;enemy(s);s:item("item_enchanted_mango",0);eq(s:mod("mana").Tick(s.bot,s.state),true);eq(s.orders[1].ability,"item_enchanted_mango");
end);
test("mango supports self-target behavior from live item flags",function()
    local s=SCENARIO();s.mana=100;enemy(s);s:item("item_enchanted_mango",0,{behavior=8});s:mod("mana").Tick(s.bot,s.state);eq(s.orders[1].kind,"entity");
end);
test("small mana deficit does not waste a whole mango",function()
    local s=SCENARIO();s.mana=430;enemy(s);s:item("item_enchanted_mango",0,{special={mana=100}});eq(s:mod("mana").Tick(s.bot,s.state),false);
end);
test("backpack and stash regen items are never used",function()
    for _,slot in ipairs({6,9}) do local s=SCENARIO();s.mana=50;enemy(s);s:item("item_enchanted_mango",slot);eq(s:mod("mana").Tick(s.bot,s.state),false) end;
end);
test("unknown item behavior issues no guessed cast",function()
    local s=SCENARIO();s.mana=50;enemy(s);s:item("item_enchanted_mango",0,{behavior=0});eq(s:mod("mana").Tick(s.bot,s.state),false);eq(#s.orders,0);
end);
test("one frame and pending outcomes prevent duplicate item attempts",function()
    local s=SCENARIO();s.mana=50;enemy(s);s:item("item_enchanted_mango",0);local m=s:mod("mana");m.Tick(s.bot,s.state);m.Tick(s.bot,s.state);eq(#s.orders,1);
end);
test("BKB reacts to known incoming control before low HP",function()
    local s=SCENARIO();local e=enemy(s);local spell=s:ability("sven_storm_bolt");spell.caster=e;
    s.projectiles={{is_attack=false,ability=spell}};s:item("item_black_king_bar",0);eq(s:mod("threats").Tick(s.bot,s.state),true);eq(s.orders[1].ability,"item_black_king_bar");
end);
test("ordinary attack projectiles and allied spells do not trigger BKB",function()
    for _,v in ipairs({"attack","ally","nil"}) do local s=SCENARIO();local a=s:ability("sven_storm_bolt");
        if v=="attack" then a.caster=enemy(s) end;s.projectiles={{is_attack=v=="attack",ability=v~="nil" and a or nil}};
        s:item("item_black_king_bar",0);eq(s:mod("threats").Tick(s.bot,s.state),false);
    end;
end);
test("linear intersection predicts threat and ignores departing missile",function()
    for _,dir in ipairs({-1,1}) do local s=SCENARIO();local a=s:ability("lion_impale");a.caster=enemy(s);
        s.linear={{ability=a,location={x=300,y=0},velocity={x=dir*500,y=0},radius=80}};
        s:item("item_black_king_bar",0);eq(s:mod("threats").Tick(s.bot,s.state),dir==-1);
    end;
end);
test("visible cast phase and target hint can trigger BKB",function()
    local s=SCENARIO();local e=enemy(s);local a=s:ability("lion_voodoo");a.phase=true;a.caster=e;e.active=a;e.target=s.bot;
    s:item("item_black_king_bar",0);eq(s:mod("threats").Tick(s.bot,s.state),true);
end);
test("magical burst potential plus recent own damage triggers conservative BKB",function()
    local s=SCENARIO();local e=enemy(s);e.GetEstimatedDamageToTarget=function() return 300 end;
    s.hp=300;s.recent=.2;s:item("item_black_king_bar",0);eq(s:mod("threats").Tick(s.bot,s.state),true);
end);
test("BKB unavailable, backpack, active modifier, or stun prevents order",function()
    for _,v in ipairs({"cooldown","slot","modifier","stun"}) do
        local s=SCENARIO();local a=s:ability("sven_storm_bolt");a.caster=enemy(s);s.projectiles={{is_attack=false,ability=a}};
        local it=s:item("item_black_king_bar",v=="slot" and 6 or 0);
        if v=="cooldown" then it.cd=10 elseif v=="modifier" then s.bot.modifiers.modifier_black_king_bar_immune=true elseif v=="stun" then s.stunned=true end;
        eq(s:mod("threats").Tick(s.bot,s.state),false);eq(#s.orders,0);
    end;
end);
test("urgent BKB may clear only owned requiem then use item next tick",function()
    local s=SCENARIO();local e=enemy(s);ownRequiem(s,e);local a=s:ability("sven_storm_bolt");a.caster=e;s.projectiles={{is_attack=false,ability=a}};
    s:item("item_black_king_bar",0);local t=s:mod("threats");eq(t.Tick(s.bot,s.state),true);eq(s.orders[1].kind,"clear");
    s:advance();eq(t.Tick(s.bot,s.state),true);eq(s.orders[2].ability,"item_black_king_bar");
end);
test("BKB never interrupts unowned cast or channel",function()
    local s=SCENARIO();local a=s:ability("sven_storm_bolt");a.caster=enemy(s);s.projectiles={{is_attack=false,ability=a}};s.using=true;s.active=s.abilities.nevermore_frenzy;
    s:item("item_black_king_bar",0);eq(s:mod("threats").Tick(s.bot,s.state),false);eq(#s.orders,0);
end);
test("PT preparation reads actual state and reaches INT with bounded toggles",function()
    local s=SCENARIO();local pt=s:item("item_power_treads",0,{stat=1});local t=s:mod("treads");local a=s.abilities.nevermore_shadowraze1;
    eq(t.PrepareMana(s.bot,s.state,a),false);eq(pt.stat,0);s:advance();eq(t.PrepareMana(s.bot,s.state,a),false);eq(pt.stat,2);
    s:advance();eq(t.PrepareMana(s.bot,s.state,a),true);eq(#s.orders,2);
end);
test("PT restores AGI after confirmed release",function()
    local s=SCENARIO();local pt=s:item("item_power_treads",0,{stat=2});local t=s:mod("treads");local a=s.abilities.nevermore_shadowraze1;
    eq(t.PrepareMana(s.bot,s.state,a),true);t.NoteCast(s.state,a);s:release(a);s:advance();eq(t.Tick(s.bot,s.state),true);eq(pt.stat,1);
end);
test("low HP never selects STR when survival toggling is disabled",function()
    local s=SCENARIO();local pt=s:item("item_power_treads",0,{stat=1});s.hp=250;s.recent=.5;
    eq(s:mod("treads").Tick(s.bot,s.state),false);eq(pt.stat,1);
end);
test("PT cannot toggle during an ability or channel",function()
    local s=SCENARIO();s:item("item_power_treads",0,{stat=1});s.using=true;eq(s:mod("treads").PrepareMana(s.bot,s.state,s.abilities.nevermore_shadowraze1),false);eq(#s.orders,0);
end);
test("PT failed readback cannot loop forever or block spell forever",function()
    local s=SCENARIO();s:item("item_power_treads",0,{stat=1});s.pt_stuck=true;local t=s:mod("treads");local a=s.abilities.nevermore_shadowraze1;
    for i=1,3 do t.PrepareMana(s.bot,s.state,a);s:advance(.1) end;eq(#s.orders,1);
    s:advance(.8);eq(t.PrepareMana(s.bot,s.state,a),true);eq(#s.orders,1);
end);
test("neutral raze chosen while already farming camp",function()
    local s=SCENARIO();s.mode=5;s.mana=600;local a=s.unit("neutral",4,450,0);a.hp=600;local b=s.unit("neutral",4,500,50);b.hp=600;s.neutrals={a,b};
    s.abilities.nevermore_frenzy.cd=10;local p=s:mod("neutrals").Consider(s.bot);assert(p and p.location);assert(p.count>=2);
end);
test("neutral Feast chosen only with enough mana for following raze and reserve",function()
    local s=SCENARIO();s.mode=5;s.mana=600;local a=s.unit("neutral",4,450,0);a.hp=600;local b=s.unit("neutral",4,500,20);b.hp=600;s.neutrals={a,b};
    local p=s:mod("neutrals").Consider(s.bot);eq(p.ability.name,"nevermore_frenzy");
    s.mana=200;eq(s:mod("neutrals").Consider(s.bot),nil);
end);
test("neutral farming yields to visible lane or enemy hero",function()
    for _,v in ipairs({"lane","hero"}) do local s=SCENARIO();s.mode=5;s.neutrals={s.unit("neutral",4,450,0)};
        if v=="lane" then s.creeps={s.unit("creep",3,450,0)} else enemy(s) end;eq(s:mod("neutrals").Consider(s.bot),nil);
    end;
end);
test("neutral resistance affects useful damage rather than raw HP rule",function()
    local s=SCENARIO();s.mode=5;local a=s.unit("neutral",4,450,0);a.magic_factor=0;s.neutrals={a};s.abilities.nevermore_frenzy.cd=10;
    eq(s:mod("neutrals").Consider(s.bot),nil);
end);
test("no neutral path or attack order introduced",function()
    local s=SCENARIO();s.neutrals={s.unit("neutral",4,450,0)};s.mode=1;eq(s:mod("neutrals").Consider(s.bot),nil);eq(#s.orders,0);
end);
test("observer uses high cliff with rune and lane coverage",function()
    local s=SCENARIO();s:item("item_ward_observer",0);local p=s:mod("wards").Plan(s.bot);
    assert(p);eq(p.kind,"observer");eq(p.height,3);assert(p.rune_location);assert(p.lane);
end);
test("observer accepts ward cliff that is not walkable",function()
    local s=SCENARIO();s:item("item_ward_observer",0);local p=s:mod("wards").Plan(s.bot);assert(p);eq(s.env.IsLocationPassable(p.location),false);
end);
test("ordinary bank or low ground never substitutes for observer cliff",function()
    local s=SCENARIO();s:item("item_ward_observer",0);s.height_fn=function(p) return math.abs(p.y)>200 and 2 or 1 end;
    -- Force banks to level2 as well: candidate must be strictly higher.
    s.height_fn=function(p) if math.abs(p.x)>=400 and math.abs(p.y)<100 then return 2 end;return 1 end;
    eq(s:mod("wards").Plan(s.bot),nil);
end);
test("observer cannot claim unreachable rune coverage",function()
    local s=SCENARIO();s:item("item_ward_observer",0);s.env.GetRuneSpawnLocation=function(id) return {x=0,y=id==0 and 5000 or -5000} end;
    eq(s:mod("wards").Plan(s.bot),nil);
end);
test("unknown tree or terrain data skips observer",function()
    for _,v in ipairs({"tree","height"}) do local s=SCENARIO();s:item("item_ward_observer",0);
        if v=="tree" then s.env.GetAllTrees=nil else s.env.GetHeightLevel=nil end;eq(s:mod("wards").Plan(s.bot),nil);
    end;
end);
test("sentry location is river mid center",function()
    local s=SCENARIO();s:item("item_ward_sentry",0);local p=s:mod("wards").Plan(s.bot);assert(p);eq(p.kind,"sentry");eq(p.location.x,0);eq(p.location.y,0);eq(p.height,1);
end);
test("dispenser true mode matches real-log observer calibration",function()
    local s=SCENARIO();s:item("item_ward_dispenser",0,{toggle=true,charges=1,secondary=1});eq(s:mod("wards").Tick(s.bot,s.state),true);eq(s.orders[1].kind,"ward");eq(s.orders[1].ward_kind,"observer");
end);
test("dispenser toggles and reads back before placing a different kind",function()
    local s=SCENARIO();s:item("item_ward_dispenser",0,{toggle=false,charges=1,secondary=1});local w=s:mod("wards");
    w.Tick(s.bot,s.state);eq(s.orders[1].kind,"self");s:advance(1.1);w.Tick(s.bot,s.state);eq(s.orders[2].kind,"ward");eq(s.orders[2].ward_kind,"observer");
end);
test("ward placement gets charge/entity evidence and quality readback",function()
    local s=SCENARIO();s:item("item_ward_observer",0);local w=s:mod("wards");w.Tick(s.bot,s.state);assert(s.state.ward_pending);
    s:advance();w.Poll(s.bot,s.state);eq(s.state.ward_pending,nil);assert(table.concat(s.logs):find("ward_placement_observed",1,true));
end);
test("existing observer blocks a duplicate placement",function()
    local s=SCENARIO();s:item("item_ward_observer",0);local w=s.unit("npc_dota_observer_wards",2,0,350);s.wards={w};eq(s:mod("wards").Plan(s.bot),nil);
end);
test("ward planner preserves native attacks and unknown actions",function()
    for _,action in ipairs({3,99}) do local s=SCENARIO();s:item("item_ward_observer",0);s.action=action;eq(s:mod("wards").Plan(s.bot),nil);eq(#s.orders,0) end;
end);
test("basic bottle and wand support is retained in active tactical controller",function()
    local s=SCENARIO();s.mana=40;s:item("item_bottle",0,{behavior=8,charges=3});eq(s:mod("items").Tick(s.bot,s.state),true);eq(s.orders[1].ability,"item_bottle");
    local t=SCENARIO();t.hp=150;enemy(t);t:item("item_magic_wand",0,{charges=10});eq(t:mod("items").Tick(t.bot,t.state),true);eq(t.orders[1].kind,"self");
end);
test("basic salve works only in safe state",function()
    local s=SCENARIO();s.hp=300;s:item("item_flask",0,{behavior=8});eq(s:mod("items").Tick(s.bot,s.state),true);
end);
test("actual PR43 root binds and still casts real-target requiem",function()
    local s=SCENARIO();enemy(s);local ok=s:bind();eq(ok,true);s.env.AbilityUsageThink();eq(#s.orders,1);eq(s.orders[1].ability,"nevermore_requiem");assert(s.state.requiem);
end);
test("actual callback observes running own requiem then cancels escaped target",function()
    local s=SCENARIO();local e=enemy(s);s:bind();s.env.AbilityUsageThink();e.x=1400;s:advance(.2);s.env.AbilityUsageThink();s:advance(.2);s.env.AbilityUsageThink();eq(s.orders[#s.orders].kind,"clear");eq(#s.orders,2);
end);
test("actual root wrapper blocks illusions from all ability/item orders",function()
    local s=SCENARIO();enemy(s);s:item("item_enchanted_mango",0);s.mana=50;s:bind();s.bot.illusion=true;s.env.AbilityUsageThink();s.env.ItemUsageThink();eq(#s.orders,0);
end);
test("BKB and spell cannot issue two orders in same callback tick",function()
    local s=SCENARIO();local e=enemy(s);local a=s:ability("sven_storm_bolt");a.caster=e;s.projectiles={{is_attack=false,ability=a}};
    s:item("item_black_king_bar",0);s:bind();s.env.AbilityUsageThink();s.env.ItemUsageThink();eq(#s.orders,1);eq(s.orders[1].ability,"item_black_king_bar");
end);
test("actual root casts requiem immediately regardless of PT state",function()
    for _,stat in ipairs({0,1,2}) do
        local s=SCENARIO();enemy(s);local pt=s:item("item_power_treads",0,{stat=stat});s:bind();
        s.env.ItemUsageThink();s.env.AbilityUsageThink();eq(#s.orders,1);eq(s.orders[1].ability,"nevermore_requiem");eq(pt.stat,stat);
    end;
end);
test("unsafe clarity cannot be used by the delegated legacy callback",function()
    local s=SCENARIO();s.mana=50;s:item("item_clarity",0,{behavior=8});enemy(s,950);s:bind();s.env.ItemUsageThink();eq(#s.orders,0);
end);
test("idempotent binding never nests callback wrappers",function()
    local s=SCENARIO();s:bind();local before=s.env.AbilityUsageThink;local ok,reason=s:mod("entry").BindLegacy(s.env);eq(ok,true);eq(reason,"already_bound");eq(s.env.AbilityUsageThink,before);
end);
test("unknown callback contract leaves original functions untouched",function()
    local s=SCENARIO();s.env.AbilityUsageThink=function() end;local before=s.env.AbilityUsageThink;
    eq(s:mod("entry").BindLegacy(s.env),false);eq(s.env.AbilityUsageThink,before);
end);
test("missing observer contract leaves callbacks untouched",function()
    local s=SCENARIO();s.observer_missing=true;eq(s:bind(),false);eq(s.env.MIDBOT_TACTICAL_BOUND,nil);
end);
test("disabled profile delegates exact original callback",function()
    local s=SCENARIO();s:bind();s.config.enabled=false;local countOld=0;
    s.env.MIDBOT_TACTICAL_BOUND.originals.ItemUsageThink=function() countOld=countOld+1 end;
    s.env.ItemUsageThink();eq(countOld,1);
end);
test("logger and unknown-after-action failures never create double orders",function()
    local s=SCENARIO();s.mana=50;enemy(s);s:item("item_enchanted_mango",0);s.logger_error=true;s.action_throw=true;s:bind();
    s.env.ItemUsageThink();s.env.AbilityUsageThink();eq(#s.orders,1);
end);
test("state resets on clock rewind instead of keeping stale ownership",function()
    local s=SCENARIO();s.state.requiem={};s.time=1;local n=s.broker.State(s.bot);eq(n.requiem,nil);assert(n~=s.state);
end);
test("a hidden handle reporting dead still cannot authorize cancelling requiem",function()
    local s=SCENARIO();local e=enemy(s);local q=ownRequiem(s,e);e.visible=false;e.hp=0;e.x=1300;
    q.Tick(s.bot,s.state);s:advance(.3);q.Tick(s.bot,s.state);eq(#s.orders,0);
end);
test("resource preparation expires without ever selecting STR",function()
    local s=SCENARIO();local pt=s:item("item_power_treads",0,{stat=1});local t=s:mod("treads");
    s.state.pt_spell={ability=s.abilities.nevermore_requiem,selected_at=s.time};s.hp=250;s.recent=.1;
    eq(t.Tick(s.bot,s.state),false);eq(pt.stat,1);eq(#s.orders,0);
    s:advance(1.6);eq(t.Tick(s.bot,s.state),false);eq(pt.stat,1);
end);
test("a low bank cannot pass observer checks even if both sampled banks are river",function()
    local s=SCENARIO();s:item("item_ward_observer",0);s.height_fn=function(p) return math.abs(p.y)>200 and 2 or 1 end;
    eq(s:mod("wards").Plan(s.bot),nil);
end);
test("unknown dispenser mode is never guessed",function()
    local s=SCENARIO();local it=s:item("item_ward_dispenser",0,{toggle=true,charges=1,secondary=1});it.GetToggleState=nil;
    eq(s:mod("wards").Plan(s.bot),nil);eq(#s.orders,0);
end);
test("failed dispenser toggle readback is bounded",function()
    local s=SCENARIO();local it=s:item("item_ward_dispenser",0,{toggle=false,charges=1,secondary=1});it.GetToggleState=function() return false end;
    local w=s:mod("wards");for i=1,5 do w.Tick(s.bot,s.state);s:advance(1.1) end;eq(#s.orders,2);
end);
test("a toggle consuming a charge disables further ward execution",function()
    local s=SCENARIO();local it=s:item("item_ward_dispenser",0,{toggle=false,charges=1,secondary=1});local w=s:mod("wards");
    w.Tick(s.bot,s.state);it.charges=0;s:advance();w.Poll(s.bot,s.state);eq(s.state.ward_disabled,true);eq(w.Tick(s.bot,s.state),false);
end);
test("ward confirmation does not claim exclusive visibility attribution",function()
    local s=SCENARIO();s.location_visible=false;s:item("item_ward_observer",0);local w=s:mod("wards");w.Tick(s.bot,s.state);s:advance();w.Poll(s.bot,s.state);
    local log=table.concat(s.logs);assert(log:find('"rune_visible":false',1,true));assert(log:find("team_visibility_not_exclusive_ward_credit",1,true));
end);
test("unknown bottle safety data cannot accidentally authorize drinking",function()
    local s=SCENARIO();s.enemies_unknown=true;s.mana=20;s:item("item_bottle",0,{behavior=8,charges=3});eq(s:mod("items").Tick(s.bot,s.state),false);
end);
test("API exception after item submission never retries same frame",function()
    local s=SCENARIO();s.mana=50;enemy(s);s:item("item_enchanted_mango",0);s.action_throw=true;
    local m=s:mod("mana");eq(m.Tick(s.bot,s.state),true);eq(m.Tick(s.bot,s.state),false);eq(#s.orders,1);
end);
test("neutral execution uses live raze range and requires alignment",function()
    local s=SCENARIO();local n=s:mod("neutrals");local a=s.abilities.nevermore_shadowraze2;
    eq(n.Execute(s.bot,s.state,{ability=a,location={x=450,y=0},reason="test"}),true);eq(s.orders[1].kind,"self");
    local t=SCENARIO();t.env.IsLocationPassable=function() return true end;
    eq(t:mod("neutrals").Execute(t.bot,t.state,{ability=t.abilities.nevermore_shadowraze2,location={x=0,y=450},reason="test"}),true);eq(t.orders[1].kind,"face");
    local p=t.orders[1].location;assert(math.sqrt(p.x*p.x+p.y*p.y)<=48.001);
end);
test("blocked neutral facing step cannot become a full camp chase",function()
    local s=SCENARIO();s.env.IsLocationPassable=function() return false end;
    eq(s:mod("neutrals").Execute(s.bot,s.state,{ability=s.abilities.nevermore_shadowraze2,location={x=0,y=450},reason="test"}),false);eq(#s.orders,0);
end);
test("actual attached root can cast a neutral raze on its first callback",function()
    local s=SCENARIO();s.mode=5;s.mana=600;s.abilities.nevermore_frenzy.cd=10;
    local a=s.unit("neutral",4,450,0);a.hp=600;local b=s.unit("neutral",4,500,0);b.hp=600;s.neutrals={a,b};s:bind();
    s.env.AbilityUsageThink();eq(#s.orders,1);assert(s.orders[1].ability:find("nevermore_shadowraze",1,true));
end);
test("multiple bots keep separate tactical ownership and item budgets",function()
    local s=SCENARIO();local other=s.unit("npc_dota_hero_nevermore",2,0,0);other.id=9;
    local one=s.broker.State(s.bot);local two=s.broker.State(other);s.broker.Mark(one);eq(s.broker.Free(two),true);assert(one~=two);
end);
test("mango can restore mana outside combat when no calm alternative exists",function()
    local s=SCENARIO();s.mana=50;s:item("item_enchanted_mango",0);eq(s:mod("mana").Tick(s.bot,s.state),true);
end);
test("calm active regen preserves mango instead of stacking consumables",function()
    local s=SCENARIO();s.mana=50;s:item("item_enchanted_mango",0);s.bot.modifiers.modifier_clarity_potion=true;
    eq(s:mod("mana").Tick(s.bot,s.state),false);
end);
test("PT raw-state mapping is independent of hero DOTA attribute enums",function()
    local s=SCENARIO();s.env.ATTRIBUTE_STRENGTH=nil;s.env.ATTRIBUTE_AGILITY=nil;s.env.ATTRIBUTE_INTELLECT=nil;
    s.env.DOTA_ATTRIBUTE_STRENGTH=0;s.env.DOTA_ATTRIBUTE_AGILITY=1;s.env.DOTA_ATTRIBUTE_INTELLECT=2;
    local pt=s:item("item_power_treads",0,{stat=0});eq(s:mod("treads").PrepareMana(s.bot,s.state,s.abilities.nevermore_shadowraze1),false);eq(pt.stat,2);
end);
print("TACTICAL PASSED "..count.." cases (synthetic API; live Dota not tested)");
