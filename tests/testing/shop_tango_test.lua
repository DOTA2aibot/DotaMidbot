local count=0;
local function eq(a,b) assert(a==b,tostring(a).." ~= "..tostring(b)) end;
local function test(name,fn) fn();count=count+1;print("PASS SHOP_TANGO "..name) end;
local function tango()
    local s=SCENARIO();s.hp=750;s.trees={{x=100,y=0}};s:item("item_tango",0,{charges=3,range=165});
    s.bot.GetNearbyTrees=function() return {1} end;
    s.bot.Action_UseAbilityOnTree=function(_,item,id)
        eq(id,1);s.orders[#s.orders+1]={kind="tree",ability=item.name,tree=id};item.charges=item.charges-1;
    end;return s;
end;
test("Tango is cast on a nearby tree and charge consumption is observed",function()
    local s=tango();eq(s:mod("tango").Tick(s.bot,s.state),true);eq(s.orders[1].kind,"tree");eq(s.items[0].charges,2);
    s:advance();s.broker.Poll(s.bot,s.state);assert(table.concat(s.logs):find("charges_decreased",1,true));
end);
test("healthy hero active regen and fountain preserve Tango",function()
    for _,kind in ipairs({"healthy","regen","fountain","small_missing"}) do
        local s=tango();if kind=="healthy" then s.hp=950 elseif kind=="regen" then s.bot.modifiers.modifier_tango_heal=true
        elseif kind=="fountain" then s.bot.DistanceFromFountain=function() return 0 end
        else s.hp=70;s.bot.GetMaxHealth=function() return 100 end end;
        eq(s:mod("tango").Tick(s.bot,s.state),false);eq(#s.orders,0);
    end;
end);
test("Tango never approaches a distant or missing tree",function()
    for _,kind in ipairs({"far","missing","api"}) do
        local s=tango();if kind=="far" then s.trees[1].x=500 elseif kind=="missing" then s.bot.GetNearbyTrees=function() return {} end
        else s.env.GetTreeLocation=nil end;
        eq(s:mod("tango").Tick(s.bot,s.state),false);eq(#s.orders,0);
    end;
end);
test("Tango preserves attacks casts channels queues and pending ward",function()
    for _,kind in ipairs({"attack","cast","channel","queue","ward"}) do
        local s=tango();if kind=="attack" then s.action=3 elseif kind=="cast" then s.using=true
        elseif kind=="channel" then s.channel=true elseif kind=="queue" then s.queued=1 else s.state.ward_pending={} end;
        eq(s:mod("tango").Tick(s.bot,s.state),false);eq(#s.orders,0);
    end;
end);
test("backpack Tango cannot be cast and callbacks share one order budget",function()
    local s=tango();s.items[6]=s.items[0];s.items[0]=nil;eq(s:mod("tango").Tick(s.bot,s.state),false);
    local t=tango();eq(t:mod("tango").Tick(t.bot,t.state),true);eq(t:mod("tango").Tick(t.bot,t.state),false);eq(#t.orders,1);
end);
test("actual tactical item callback uses Tango and no self/entity cast",function()
    local s=tango();s:bind();s.env.ItemUsageThink();eq(s.orders[1].kind,"tree");eq(#s.orders,1);
end);
local function shop(name)
    local s=SCENARIO();s.bot.name=name or "npc_dota_hero_lion";s.buy={};s.time=0;s.inventory={};s.couriers={};
    local profile=s.env.require("bots/laning/profile");profile.name="all_test";profile.ally_ward_free_shop=true;
    s.env.GetTeamPlayers=function() return {7,0} end;s.env.GetSelectedHeroName=function(id) return id==0 and "npc_dota_hero_nevermore" or s.bot.name end;
    s.env.IsPlayerBot=function() return true end;s.env.GetNumCouriers=function() return #s.couriers end;s.env.GetCourier=function(i) return s.couriers[i+1] end;
    s.env.GetItemComponents=function(item) if s.recipe then return s.recipe(item) end;return {} end;
    s.env.GetItemCost=function() return 50 end;s.env.PURCHASE_ITEM_SUCCESS=0;s.env.PURCHASE_ITEM_INVALID_ITEM_NAME=2;
    s.bot.GetGold=function() return s.gold or 100000 end;s.bot.SetNextItemPurchaseValue=function(_,v) s.purchaseValue=v end;
    s.bot.GetItemInSlot=function(_,slot) return s.inventory[slot] end;
    s.bot.ActionImmediate_PurchaseItem=function(_,item)
        assert(not item:find("ward",1,true));s.buy[#s.buy+1]=item;
        if s.buyThrow then error("unknown purchase") end;if s.unknown then return nil end;return s.result or 0;
    end;
    s.shop=s.env.require("bots/laning/testing/ally_shop");
    function s:tick(t) self.time=t or self.time+.5;self.shop.Tick(self.bot) end;
    return s;
end;
test("all four allies and unknown fallback buy ordinary items without wards",function()
    for _,name in ipairs({"lion","crystal_maiden","juggernaut","bristleback","lina"}) do
        local s=shop("npc_dota_hero_"..name);for i=1,50 do s:tick() end;
        assert(#s.buy>=6);eq(s.buy[1],"item_tango");eq(s.purchaseValue,0);
    end;
end);
test("generic shopping never controls SF humans illusions or non-test profiles",function()
    for _,kind in ipairs({"sf","human","illusion","profile","flag","team"}) do
        local s=shop();if kind=="sf" then s.bot.name="npc_dota_hero_nevermore"
        elseif kind=="human" then s.env.IsPlayerBot=function() return false end
        elseif kind=="illusion" then s.bot.illusion=true
        elseif kind=="profile" then s.env.require("bots/laning/profile").name="valve_play"
        elseif kind=="flag" then s.env.require("bots/laning/profile").ally_ward_free_shop=false
        else s.env.GetSelectedHeroName=function() return "npc_dota_hero_lina" end end;
        s:tick();eq(#s.buy,0);
    end;
end);
test("recipe components are paid once and ward recipe injection is rejected",function()
    local s=shop();s.recipe=function(name) if name=="item_magic_wand" then return {{"piece_a","piece_b","piece_a"}} end;return {} end;
    for i=1,50 do s:tick() end;local n=0;for _,name in ipairs(s.buy) do if name=="piece_a" then n=n+1 end end;eq(n,2);
    local t=shop();t.recipe=function(name) if name=="item_glimmer_cape" then return {{"item_ward_observer"}} end;return {} end;
    for i=1,50 do t:tick() end;assert(table.concat(t.logs):find("recipe_rejected",1,true));
end);
test("unknown purchase does not spend again until observed",function()
    for _,throws in ipairs({false,true}) do local s=shop();s.unknown=true;s.buyThrow=throws;
        for i=1,30 do s:tick() end;eq(#s.buy,1);
        s.inventory[0]={GetName=function() return "item_tango" end};s.unknown=false;s.buyThrow=false;s:tick();s:tick();eq(#s.buy,2);
    end;
end);
test("no gold means no purchase and temporary failures do not lock the whole build",function()
    local s=shop();s.gold=0;s:tick();eq(#s.buy,0);eq(s.purchaseValue,50);
    local t=shop();t.result=4;for i=1,12 do t:tick() end;t.result=0;t:tick(20);assert(t.buy[#t.buy]~="item_tango");
end);
test("generic callback runs shopping while personal SF remains separate",function()
    local s=shop();s.env.GetBot=function() return s.bot end;local f=assert(loadfile("profiles/all_test/item_purchase_generic.lua"));setfenv(f,s.env);f();
    s.env.ItemPurchaseThink();eq(s.buy[1],"item_tango");eq(#s.orders,0);
end);
test("nil leaf recipe is valid but throwing recipe API never spends",function()
    local s=shop();s.env.GetItemComponents=function() return nil end;s:tick();eq(s.buy[1],"item_tango");
    local t=shop();t.env.GetItemComponents=function() error("unknown recipe") end;t:tick();eq(#t.buy,0);
end);
test("owned recipe components and own courier are credited without reading another courier",function()
    local s=shop();s.recipe=function(name) if name=="item_magic_wand" then return {{"piece_a","piece_b"}} end;return {} end;
    s.inventory[9]={GetName=function() return "piece_a" end};
    s.couriers={{GetPlayerID=function() return 7 end,GetItemInSlot=function(_,slot) if slot==0 then return {GetName=function() return "piece_b" end} end end},
        {GetPlayerID=function() return 8 end,GetItemInSlot=function() error("other courier inventory") end}};
    for i=1,50 do s:tick() end;for _,name in ipairs(s.buy) do assert(name~="piece_a" and name~="piece_b") end;
end);
test("ally courier delivery uses only the owned idle courier",function()
    local s=shop();s.inventory[9]={GetName=function() return "piece_a" end};local c={GetPlayerID=function() return 7 end,GetItemInSlot=function() return nil end};s.couriers={c};
    s.env.COURIER_ACTION_TAKE_AND_TRANSFER_ITEMS=6;s.env.COURIER_STATE_IDLE=0;s.env.COURIER_STATE_AT_BASE=1;s.env.GetCourierState=function() return 0 end;
    local transfers=0;s.bot.ActionImmediate_Courier=function(_,unit,action) eq(unit,c);eq(action,6);transfers=transfers+1 end;
    s:tick();s:tick();eq(transfers,1);assert(#s.buy>0);
end);
print("SHOP_TANGO PASSED "..count.." cases (mock API; native fallback is not claimed)");
