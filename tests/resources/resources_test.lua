local count=0;
local function eq(a,b) assert(a==b,tostring(a).." ~= "..tostring(b)) end;
local function test(name,fn) fn();count=count+1;print("PASS RESOURCES "..name) end;
local function scenario()
    local s=SCENARIO();s.mana=50;s.maxmana=300;
    s.resources=s:mod("resources");s.pt=s:mod("treads");s.finisher=s:mod("finisher");
    s.enemy=s.unit("npc_dota_hero_lina",3,200,0);s.enemy.hp=100;s.enemy.GetHealthRegen=function() return 0 end;s.heroes={s.enemy};
    function s:wand(n,slot) return self:item("item_magic_wand",slot or 0,{charges=n,special={restore_per_charge=15}}) end;
    function s:boots(stat) return self:item("item_power_treads",1,{stat=stat or 1}) end;
    return s;
end;
test("one charge and empty wand cannot be confused",function()
    local s=scenario();local wand=s:wand(1);local p=s.resources.Read(s.bot,s.state);eq(p.charges,1);eq(p.mana_gain,15);eq(p.potential_mana,65);
    wand.charges=0;p=s.resources.Read(s.bot,s.state);eq(p.item,nil);eq(s.resources.Emergency(s.bot,s.state),false);eq(#s.orders,0);
end);
test("potential resources are capped at missing HP and mana",function()
    local s=scenario();s:wand(20);s.mana=290;s.hp=990;local p=s.resources.Read(s.bot,s.state);eq(p.health_gain,10);eq(p.mana_gain,10);eq(p.potential_mana,300);eq(p.potential_hp,1000);
end);
test("unknown charges cooldown and inactive slots do not count as usable mana",function()
    for _,why in ipairs({"unknown","cooldown","backpack","stash"}) do local s=scenario();local it=s:wand(10,why=="backpack" and 6 or (why=="stash" and 9 or 0));
        if why=="unknown" then it.GetCurrentCharges=function() return nil end elseif why=="cooldown" then it.cd=5 end;
        eq(s.resources.Read(s.bot,s.state).item,nil);eq(#s.orders,0);
    end;
end);
test("unknown per-charge restoration is not guessed for a lethal cast",function()
    local s=scenario();s:item("item_magic_wand",0,{charges=10});local p=s.resources.Read(s.bot,s.state);eq(p.known,false);eq(p.potential_mana,50);eq(s.finisher.Tick(s.bot,s.state),false);eq(#s.orders,0);
end);
test("combat HP15 percent consumes even one charge",function()
    local s=scenario();s.hp=150;s:wand(1);eq(s.resources.Emergency(s.bot,s.state),true);eq(s.orders[1].ability,"item_magic_wand");
end);
test("wand is preserved outside combat and above emergency threshold",function()
    for _,why in ipairs({"calm","healthy"}) do local s=scenario();s:wand(10);s.hp=why=="calm" and 100 or 160;
        if why=="calm" then s.heroes={};s.recent=100 end;
        eq(s.resources.Emergency(s.bot,s.state),false);eq(#s.orders,0);
    end;
end);
test("empty wand can never submit an item action even under lethal damage",function()
    local s=scenario();s.hp=50;local it=s:wand(1);local p=s.resources.Read(s.bot,s.state);it.charges=0;
    eq(s.resources.Use(s.bot,s.state,p,"stale_plan"),false);eq(#s.orders,0);
end);
test("known charge mana is used for a visible lethal Raze deficit",function()
    local s=scenario();s:wand(2);local p=s.finisher.Consider(s.bot,s.state);assert(p);eq(p.cost,75);eq(s.finisher.Tick(s.bot,s.state),true);eq(s.orders[1].ability,"item_magic_wand");
    s:advance();eq(s.finisher.Tick(s.bot,s.state),false);eq(#s.orders,1); -- cooldown/readback guard
end);
test("insufficient potential mana does not waste charges",function()
    local s=scenario();s:wand(1);eq(s.finisher.Tick(s.bot,s.state),false);eq(#s.orders,0);
end);
test("no lethal mana spending on illusion hidden immune distant or healthy targets",function()
    for _,why in ipairs({"illusion","hidden","immune","distant","healthy","cooldown","silenced"}) do local s=scenario();s:wand(20);
        if why=="illusion" then s.enemy.illusion=true elseif why=="hidden" then s.enemy.visible=false
        elseif why=="immune" then s.enemy.IsMagicImmune=function() return true end
        elseif why=="distant" then s.enemy.x=1100 elseif why=="healthy" then s.enemy.hp=900
        elseif why=="cooldown" then for _,a in pairs(s.abilities) do a.cd=10 end
        else s.bot.IsSilenced=function() return true end end;
        eq(s.finisher.Tick(s.bot,s.state),false);eq(#s.orders,0);
    end;
end);
test("full cast mana preserves the wand",function()
    local s=scenario();s.mana=200;s:wand(20);eq(s.finisher.Tick(s.bot,s.state),false);eq(#s.orders,0);
end);
test("spell ticket exists before first toggle and idle ticks cannot undo it",function()
    local s=scenario();s.mana=200;local pt=s:boots(1);local a=s.abilities.nevermore_shadowraze1;
    eq(s.pt.Before(s.bot,s.state,a),false);assert(s.state.pt_spell);eq(pt.stat,0);
    for i=1,4 do s:advance(.02);eq(s.pt.Tick(s.bot,s.state),false);eq(pt.stat,0);eq(s.pt.Before(s.bot,s.state,a),false) end;
    eq(#s.orders,1);s:advance(.03);eq(s.pt.Before(s.bot,s.state,a),false);eq(pt.stat,2);
    s:advance(.11);eq(s.pt.Before(s.bot,s.state,a),true);eq(#s.orders,2);
end);
test("INT is held until cast readback then restored once to AGI",function()
    local s=scenario();local pt=s:boots(2);local a=s.abilities.nevermore_shadowraze1;s.pt.Before(s.bot,s.state,a);
    for i=1,20 do s:advance(.03);s.pt.Tick(s.bot,s.state) end;eq(#s.orders,0);eq(pt.stat,2);
    s.pt.NoteCast(s.state,a);a.cd=10;s:advance(.11);s.pt.Tick(s.bot,s.state);eq(pt.stat,1);eq(#s.orders,1);
    for i=1,30 do s:advance(.03);s.pt.Tick(s.bot,s.state) end;eq(#s.orders,1);
end);
test("missing toggle readback issues once then times out instead of spamming",function()
    local s=scenario();s:boots(1);s.pt_stuck=true;local a=s.abilities.nevermore_shadowraze1;s.pt.Before(s.bot,s.state,a);
    for i=1,30 do s:advance(.01);s.pt.Before(s.bot,s.state,a);s.pt.Tick(s.bot,s.state) end;eq(#s.orders,1);
    s:advance(.8);eq(s.pt.Before(s.bot,s.state,a),true);eq(#s.orders,1);
end);
test("low HP does not redirect a prepared finishing spell to STR",function()
    local s=scenario();s.hp=100;s.recent=.1;local pt=s:boots(0);s.pt.Before(s.bot,s.state,s.abilities.nevermore_shadowraze1);eq(pt.stat,2);
    s:advance(.11);s.pt.Tick(s.bot,s.state);eq(pt.stat,2);
end);
test("low-mana finisher tries INT and uses actual observed mana",function()
    local s=scenario();s.mana=70;local pt=s:boots(0);local old=s.bot.Action_UseAbility;
    s.bot.Action_UseAbility=function(bot,it) old(bot,it);if it==pt and pt.stat==2 then s.mana=98;s.maxmana=420 end end;
    eq(s.finisher.Tick(s.bot,s.state),true);eq(pt.stat,2);eq(s.mana,98);s:advance(.11);eq(s.finisher.Consider(s.bot,s.state),nil);eq(#s.orders,1);
end);
test("unsuccessful INT mana preparation cannot restart every frame",function()
    local s=scenario();local pt=s:boots(0);eq(s.finisher.Tick(s.bot,s.state),true);eq(pt.stat,2);
    for i=1,30 do s:advance(.01);s.finisher.Tick(s.bot,s.state);s.pt.Tick(s.bot,s.state) end;
    assert(#s.orders<=2); -- at most INT and a later bounded restore, no INT/AGI fight
end);
test("bottle and fountain regeneration use AGI",function()
    local s=scenario();local pt=s:boots(2);s:item("item_bottle",0,{charges=3});s.mana=20;
    eq(s:mod("items").Tick(s.bot,s.state),true);eq(pt.stat,1);eq(#s.orders,1);
    s:advance(.11);eq(s:mod("items").Tick(s.bot,s.state),true);eq(s.orders[2].ability,"item_bottle");
    local t=scenario();t.hp=100;t.recent=.1;t.bot.modifiers.modifier_fountain_aura_buff=true;local b=t:boots(2);t.pt.Tick(t.bot,t.state);eq(b.stat,1);
end);
test("cast channel queue and stale empty resource plan submit no orders",function()
    for _,why in ipairs({"cast","channel","queue"}) do local s=scenario();s:wand(10);s.hp=100;
        if why=="cast" then s.using=true elseif why=="channel" then s.channel=true else s.queued=1 end;
        eq(s.resources.Emergency(s.bot,s.state),false);eq(s.finisher.Tick(s.bot,s.state),false);eq(#s.orders,0);
    end;
end);
test("actual root emergency wand precedes optional PT changes",function()
    local s=scenario();s:wand(1);s:boots(2);s.hp=100;s:bind();s.env.AbilityUsageThink();eq(#s.orders,1);eq(s.orders[1].ability,"item_magic_wand");
end);
test("PT disabled or unknown stat constants cannot block bottle use",function()
    for _,why in ipairs({"disabled","unknown"}) do local s=scenario();s:boots(2);s:item("item_bottle",0,{charges=3});s.heroes={};s.mana=20;
        if why=="disabled" then s.config.treads=false else s.env.ATTRIBUTE_AGILITY=nil;s.env.DOTA_ATTRIBUTE_AGILITY=nil end;
        eq(s:mod("items").Tick(s.bot,s.state),true);eq(s.orders[1].ability,"item_bottle");
    end;
end);
test("free INT mana preparation is attempted before spending wand charges",function()
    local s=scenario();s:wand(2);local pt=s:boots(0);eq(s.finisher.Tick(s.bot,s.state),true);eq(s.orders[1].ability,"item_power_treads");eq(pt.stat,2);
end);
print("RESOURCES PASSED "..count.." cases (live PT/restore/client ownership still require a match)");
