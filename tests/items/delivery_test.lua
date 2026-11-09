local n=0;
local function eq(a,b) assert(a==b,tostring(a).." ~= "..tostring(b)) end;
local function test(name,fn) fn();n=n+1;print("PASS STATIONARY_DELIVERY "..name) end;
local function scenario()
    local s=SCENARIO();s.env.BOT_MODE_ITEM=6;s.mode=1;
    s.profile=s.env.require("bots/laning/profile");s.profile.stationary_delivery_enabled=true;
    s.drops={};s.env.GetDroppedItemList=function() return s.drops end;
    s.modeModule=s.env.require("bots/laning/items/delivery_mode");
    function s:drop(name,distance,owner)
        local it=self:item(name or 'item_rapier',8);self.items[8]=nil;
        it.IsItem=function() return true end;it.IsNull=function() return false end;
        self.drops={{item=it,owner=owner or self.bot,location={x=distance or 100,y=0,z=0}}};return it;
    end;
    s.bot.Action_PickUpItem=function(_,it) s.orders[#s.orders+1]={kind='pickup',item=it};if s.pickupWorks then s.items[0]=it end end;
    function s:start() assert(self.modeModule.GetDesire(self.bot)>0);self.mode=6;self.modeModule.Start(self.bot) end;
    return s;
end;
test("courier cargo alone never produces a mode desire or hero order",function()
    local s=scenario();local courier=s.unit('npc_dota_courier',2,3000,0);courier.id=7;
    local it=s:item('item_branches',9);s.items[9]=nil;courier.GetItemInSlot=function(_,i) if i==0 then return it end end;
    s.env.GetNumCouriers=function() return 1 end;s.env.GetCourier=function() return courier end;
    for i=1,10 do eq(s.modeModule.GetDesire(s.bot),0);s.modeModule.Think(s.bot);s:advance() end;
    eq(#s.orders,0);
end);
test("nearby owned ground pickup confirms only after inventory readback",function()
    local s=scenario();local it=s:drop('item_branches',100);s.pickupWorks=true;s:start();s.modeModule.Think(s.bot);
    eq(s.orders[1].kind,'pickup');eq(s.orders[1].item,it);s:advance();eq(s.modeModule.GetDesire(s.bot),0);
    assert(table.concat(s.logs,'\n'):find('inventory_readback',1,true));eq(#s.orders,1);
end);
test("an owned pickup action keeps bounded ownership without per-frame repeats",function()
    local s=scenario();s:drop();s.env.BOT_ACTION_TYPE_PICK_UP_ITEM=14;s:start();s.modeModule.Think(s.bot);
    s.action=14;s:advance(.1);assert(s.modeModule.GetDesire(s.bot)>0);s.modeModule.Think(s.bot);eq(#s.orders,1);
    s:advance(3);eq(s.modeModule.GetDesire(s.bot),0);eq(#s.orders,1);
end);
test("public Rapier pickup is retained but allied unowned consumables are left alone",function()
    local s=scenario();s:drop('item_rapier',120,{});assert(s.modeModule.GetDesire(s.bot)>0);
    local t=scenario();t:drop('item_tango',120,{});eq(t.modeModule.GetDesire(t.bot),0);
end);
test("distant hidden invalid and carried item handles never generate a pickup",function()
    for _,why in ipairs({'far','hidden','null','notitem','carried','unknown'}) do local s=scenario();local it=s:drop();
        if why=='far' then s.drops[1].location.x=161 elseif why=='hidden' then s.env.IsLocationVisible=function() return false end
        elseif why=='null' then it.IsNull=function() return true end elseif why=='notitem' then it.IsItem=function() return false end
        elseif why=='carried' then s.items[0]=it else s.env.GetDroppedItemList=nil end;
        eq(s.modeModule.GetDesire(s.bot),0);eq(#s.orders,0);
    end;
end);
test("farm combat rune danger ward phase casting and full inventory retain priority",function()
    for _,why in ipairs({'creep','enemy','tower','retreat','rune','attack','ward','pending','cast','queue','dead','lowhp','recent','full'}) do
        local s=scenario();s:drop();
        if why=='creep' then s.creeps={s.unit('npc_dota_creep_lane',3,100,0)}
        elseif why=='enemy' then s.heroes={s.unit('npc_dota_hero_lina',3,100,0)}
        elseif why=='tower' then s.towers={s.unit('npc_dota_tower',3,100,0)}
        elseif why=='retreat' then s.mode=4 elseif why=='rune' then s.mode=7 elseif why=='attack' then s.mode=2
        elseif why=='ward' then s.state.vision_phase={} elseif why=='pending' then s.state.ward_pending={}
        elseif why=='cast' then s.using=true elseif why=='queue' then s.queued=1 elseif why=='dead' then s.hp=0
        elseif why=='lowhp' then s.hp=600 elseif why=='recent' then s.recent=1
        else for i=0,8 do s:item('item_branches',i) end end;
        eq(s.modeModule.GetDesire(s.bot),0);eq(#s.orders,0);
    end;
end);
test("pickup attempts are bounded and disappearing item is not recorded as success",function()
    local s=scenario();s:drop();s:start();s.modeModule.Think(s.bot);s:advance(.1);s.modeModule.Think(s.bot);eq(#s.orders,1);
    s:advance(1);s.modeModule.Think(s.bot);eq(#s.orders,2);s:advance(1.1);s.modeModule.Think(s.bot);eq(#s.orders,2);
    s.drops={};s:advance(.1);eq(s.modeModule.GetDesire(s.bot),0);assert(not table.concat(s.logs,'\n'):find('inventory_readback',1,true));
end);
test("Think revalidates location and safety after mode starts",function()
    for _,why in ipairs({'far','rune','ward'}) do local s=scenario();s:drop();s:start();
        if why=='far' then s.drops[1].location.x=1000 elseif why=='rune' then s.mode=7 else s.state.vision_phase={} end;
        s.modeModule.Think(s.bot);eq(#s.orders,0);eq(s.state.delivery_pickup,nil);
    end;
end);
test("disabled profile illusion and nonSF cannot own ITEM mode",function()
    for _,why in ipairs({'flag','probe','illusion','other'}) do local s=scenario();s:drop();
        if why=='flag' then s.profile.stationary_delivery_enabled=false elseif why=='probe' then s.profile.runtime_enabled=true
        elseif why=='illusion' then s.bot.illusion=true else s.bot.name='npc_dota_hero_lina' end;
        eq(s.modeModule.GetDesire(s.bot),0);s.modeModule.Start(s.bot);s.modeModule.Think(s.bot);eq(#s.orders,0);
    end;
end);
test("trajectory observer records both positions once a second without orders",function()
    local s=scenario();local c=s.unit('npc_dota_courier',2,1200,0);c.id=7;local it=s:drop();s.drops={};
    c.GetItemInSlot=function(_,i) if i==0 then return it end end;s.env.GetNumCouriers=function() return 1 end;s.env.GetCourier=function() return c end;
    s.env.GetCourierState=function() return 3 end;s.modeModule.Observe(s.bot,s.state);local count=#s.logs;
    s:advance(.1);s.modeModule.Observe(s.bot,s.state);eq(#s.logs,count);s:advance(1);s.modeModule.Observe(s.bot,s.state);eq(#s.logs,count+1);eq(#s.orders,0);
    assert(table.concat(s.logs,'\n'):find('courier_trajectory',1,true));
end);
test("actual ability callback samples courier even while hero is dead",function()
    local s=scenario();local c=s.unit('npc_dota_courier',2,1200,0);c.id=7;c.GetItemInSlot=function(_,i) if i==0 then return {} end end;
    s.env.GetNumCouriers=function() return 1 end;s.env.GetCourier=function() return c end;s:bind();s.hp=0;s.env.AbilityUsageThink();
    assert(table.concat(s.logs,'\n'):find('courier_trajectory',1,true));eq(#s.orders,0);
end);
test("packaged ITEM entry exposes complete callback lifecycle",function()
    local s=scenario();s:drop();local f=assert(loadfile('profiles/all_test/mode_item_nevermore.lua'));setfenv(f,s.env);f();
    assert(s.env.GetDesire()>0);s.mode=6;s.env.OnStart();s.env.Think();s.env.OnEnd();eq(s.state.delivery_pickup,nil);eq(#s.orders,1);
end);
print("STATIONARY_DELIVERY PASSED "..n.." cases (native dispatcher and movement require a client run)");
