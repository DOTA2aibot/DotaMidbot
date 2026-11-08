local count=0;
local function eq(a,b) assert(a==b,tostring(a).." ~= "..tostring(b)) end;
local function test(name,fn) fn();count=count+1;print("PASS VISION "..name) end;
local function scenario()
    local s=SCENARIO();s.env.TEAM_RADIANT=2;s.time=0;s.bot.x=-200;s.couriers={};s.buys={};s.buyResult=0;
    s.env.GetHeightLevel=function(p) return p.x < -100 and 2 or 0 end;
    s.env.GetNumCouriers=function() return #s.couriers end;
    s.env.GetCourier=function(i) return s.couriers[i+1] end;
    s.env.GetItemCost=function() return 0 end;s.env.PURCHASE_ITEM_SUCCESS=0;s.env.PURCHASE_ITEM_OUT_OF_STOCK=100;
    s.bot.GetGold=function() return 1000 end;
    s.bot.ActionImmediate_PurchaseItem=function(_,name)
        s.buys[#s.buys+1]=name;if s.buyThrow then error("unknown after purchase") end;return s.buyResult;
    end;
    s.bot.ActionImmediate_SwapItems=function(_,from,to) s.items[from],s.items[to]=s.items[to],s.items[from] end;
    s.state=s.broker.State(s.bot);
    local profile=s.env.require("bots/laning/profile");profile.wards_enabled=true;profile.runtime_enabled=false;
    function s:vision(name) return self.env.require("bots/laning/vision/"..name) end;
    return s;
end;
test("Radiant site is stable across bot movements and covers a rune geometrically",function()
    local s=scenario();local site=s:vision("site");local a=assert(site.Get(s.bot));
    assert(a.height>0);assert(s.env.GetUnitToLocationDistance(s.bot,a.rune_location)<1600);
    local distance=math.sqrt((a.location.x-a.rune_location.x)^2+(a.location.y-a.rune_location.y)^2);assert(distance<=1480);
    s.bot.x=-1000;local b=site.Get(s.bot);eq(a.location.x,b.location.x);eq(a.location.y,b.location.y);
end);
test("no river fallback when a bank or tree geometry is unknown",function()
    local s=scenario();s.env.GetHeightLevel=function() return 0 end;local p,why=s:vision("site").Get(s.bot);eq(p,nil);eq(why,"radiant_bank_geometry_unknown");
    local t=scenario();t.env.GetAllTrees=nil;local q,reason=t:vision("site").Get(t.bot);eq(q,nil);eq(reason,"tree_geometry_unknown");
end);
test("Dire illusion dead off-mid and post15min cannot buy recurring observers",function()
    for _,variant in ipairs({"dire","illusion","dead","away","late"}) do
        local s=scenario();
        if variant=="dire" then s.bot.team=3 elseif variant=="illusion" then s.bot.illusion=true
        elseif variant=="dead" then s.hp=0 elseif variant=="away" then s.bot.x=5000 else s.time=900.1 end;
        eq(s:vision("supply").TryPurchase(s.bot),false);eq(#s.buys,0);
    end;
end);
test("one initial yellow purchase, no sentry and no repeated unknown pending",function()
    for _,unknown in ipairs({false,true}) do
        local s=scenario();if unknown then s.buyResult=nil end;
        local supply=s:vision("supply");eq(supply.TryPurchase(s.bot),true);eq(s.buys[1],"item_ward_observer");
        for _,t in ipairs({1,30,100,200}) do s.time=t;eq(supply.TryPurchase(s.bot),false) end;eq(#s.buys,1);
    end;
end);
test("exception after purchase cannot cause another ward purchase",function()
    local s=scenario();s.buyThrow=true;local m=s:vision("supply");eq(m.TryPurchase(s.bot),true);s.time=200;eq(m.TryPurchase(s.bot),false);eq(#s.buys,1);
end);
test("observer in inventory backpack stash or own courier prevents duplicates",function()
    for _,slot in ipairs({0,6,9}) do local s=scenario();s:item("item_ward_observer",slot);eq(s:vision("supply").TryPurchase(s.bot),false);eq(#s.buys,0) end;
    local t=scenario();local it=t:item("item_ward_observer",9);t.items[9]=nil;
    t.couriers={{GetPlayerID=function() return 7 end,GetItemInSlot=function(_,slot) if slot==0 then return it end end}};
    eq(t:vision("supply").TryPurchase(t.bot),false);eq(#t.buys,0);
end);
test("another player's courier does not supply this bot",function()
    local s=scenario();s.couriers={{GetPlayerID=function() return 8 end,GetItemInSlot=function() error("other courier inventory must not be read") end}};
    eq(s:vision("supply").TryPurchase(s.bot),true);eq(#s.buys,1);
end);
test("out of stock retries after30s without busy-looping",function()
    local s=scenario();s.buyResult=100;local m=s:vision("supply");eq(m.TryPurchase(s.bot),true);
    s.time=1;eq(m.TryPurchase(s.bot),false);s.time=30;eq(m.TryPurchase(s.bot),true);eq(#s.buys,2);
end);
test("unknown courier API or unknown charge counts never buy",function()
    local s=scenario();s.env.GetNumCouriers=nil;eq(s:vision("supply").TryPurchase(s.bot),false);
    local t=scenario();local it=t:item("item_ward_observer",6);it.GetCurrentCharges=nil;eq(t:vision("supply").TryPurchase(t.bot),false);
end);
local function place(s)
    s:item("item_ward_observer",0);local ward=s:mod("wards");assert(ward.Tick(s.bot,s.state));eq(s.orders[1].kind,"ward");
    s:advance();ward.Poll(s.bot,s.state);s.items[0]=nil;return ward;
end;
test("confirmed placement tracks360s and orders replacement30s before expiry",function()
    local s=scenario();local w=place(s);eq(s.state.ward_pending,nil);local m=s:vision("supply");
    s.time=329;eq(m.TryPurchase(s.bot),false);s.time=331;eq(m.TryPurchase(s.bot),true);eq(#s.buys,1);
    s:item("item_ward_observer",0);s.time=332;eq(m.TryPurchase(s.bot),false);
    local p,why=w.Plan(s.bot);eq(p,nil);eq(why,"fixed_observer_already_alive");
    s.wards={};s.time=361;s:advance();eq(w.Tick(s.bot,s.state),true);eq(#s.orders,2);
end);
test("deward triggers resupply and external allied ward prevents overlap",function()
    local s=scenario();place(s);s.wards={};s.time=20;eq(s:vision("supply").TryPurchase(s.bot),true);
    local t=scenario();local spot=t:vision("site").Get(t.bot);local allied=t.unit("npc_dota_observer_wards",2,spot.location.x,spot.location.y);t.wards={allied};
    eq(t:vision("supply").TryPurchase(t.bot),false);
end);
test("fixed observer uses bank height2 without old cliff3 requirement",function()
    local s=scenario();s:item("item_ward_observer",0);local p=assert(s:mod("wards").Plan(s.bot));eq(p.height,2);eq(p.fixed,true);eq(p.kind,"observer");
end);
test("only the same fixed point is used after the first ward disappears",function()
    local s=scenario();local w=place(s);local first=s.orders[1].location;s.wards={};s:item("item_ward_observer",0);s.time=370;s:advance();s.bot.y=50;
    assert(w.Tick(s.bot,s.state));eq(s.orders[2].location.x,first.x);eq(s.orders[2].location.y,first.y);
end);
test("fixed placement never issues move chase or a sentry",function()
    local s=scenario();s:item("item_ward_sentry",0);eq(s:mod("wards").Tick(s.bot,s.state),false);eq(#s.orders,0);
    local t=scenario();t.bot.x=-1800;t:item("item_ward_observer",0);eq(t:mod("wards").Tick(t.bot,t.state),false);eq(#t.orders,0);
end);
test("fixed placement preserves attacks casts retreats and nearby enemies",function()
    for _,variant in ipairs({"attack","cast","retreat","enemy"}) do local s=scenario();s:item("item_ward_observer",0);
        if variant=="attack" then s.action=3 elseif variant=="cast" then s.using=true
        elseif variant=="retreat" then s.mode=4 else s.heroes={s.unit("npc_dota_hero_lina",3,-100,0)} end;
        eq(s:mod("wards").Tick(s.bot,s.state),false);eq(#s.orders,0);
    end;
end);
test("backpack observer is equipped with readback and passive is restored after use",function()
    local s=scenario();for slot=0,5 do s:item(slot==0 and "item_wraith_band" or "item_black_king_bar",slot) end;
    local passive=s.items[0];s:item("item_ward_observer",6);local inv=s:vision("inventory");
    eq(inv.Tick(s.bot,s.state),true);eq(s.items[0].name,"item_ward_observer");eq(s.items[6],passive);
    s:advance();s.items[0]=nil;eq(inv.Tick(s.bot,s.state),true);eq(s.items[0],passive);eq(s.items[6],nil);
end);
test("backpack equip never displaces BKB PT bottle or wand",function()
    local s=scenario();for slot=0,5 do s:item((slot%2==0) and "item_black_king_bar" or "item_power_treads",slot) end;
    s:item("item_ward_observer",6);eq(s:vision("inventory").Tick(s.bot,s.state),false);eq(s.items[6].name,"item_ward_observer");eq(#s.orders,0);
end);
test("unsafe backpack swap preserves inventory and issues no orders",function()
    for _,variant in ipairs({"hp","damage","cast","attack","retreat","enemy"}) do
        local s=scenario();s:item("item_ward_observer",6);
        if variant=="hp" then s.hp=300 elseif variant=="damage" then s.recent=1
        elseif variant=="cast" then s.using=true elseif variant=="attack" then s.action=3
        elseif variant=="retreat" then s.mode=4 else s.heroes={s.unit("npc_dota_hero_lina",3,-100,0)} end;
        eq(s:vision("inventory").Tick(s.bot,s.state),false);eq(s.items[6].name,"item_ward_observer");eq(#s.orders,0);
    end;
end);
test("consumed item handle plus new owned entity confirms placement",function()
    local s=scenario();local item=s:item("item_ward_observer",0);local original=s.bot.Action_UseAbilityOnLocation;
    s.bot.Action_UseAbilityOnLocation=function(bot,it,p) original(bot,it,p);s.items[0]=nil;it.GetCurrentCharges=nil end;
    local w=s:mod("wards");eq(w.Tick(s.bot,s.state),true);s:advance();w.Poll(s.bot,s.state);
    assert(table.concat(s.logs,"\n"):find('new_owned_ward_and_item_consumed',1,true));
    assert(table.concat(s.logs,"\n"):find('vision_lifetime',1,true));eq(s.state.ward_pending,nil);
end);
local function purchaseRoot(s)
    s.env.GetItemComponents=function() return {} end;s.bot.SetNextItemPurchaseValue=function() end;
    local f=assert(loadfile("item_purchase_nevermore.lua"));setfenv(f,s.env);f();
end;
test("actual purchase root buys one Observer and then preserves its normal queue",function()
    local s=scenario();purchaseRoot(s);s.env.ItemPurchaseThink();eq(s.buys[1],"item_ward_observer");
    s:item("item_ward_observer",9);s.time=1;s.env.ItemPurchaseThink();eq(s.buys[2],"item_tango");
    assert(not table.concat(s.logs,"\n"):find("ERROR",1,true));
end);
test("existing courier callback fetches the Observer from stash",function()
    local s=scenario();s:item("item_ward_observer",9);local transfers=0;
    s.couriers={{GetPlayerID=function() return 7 end,GetItemInSlot=function() return nil end}};
    s.env.COURIER_ACTION_TAKE_AND_TRANSFER_ITEMS=6;s.env.COURIER_STATE_IDLE=0;s.env.COURIER_STATE_AT_BASE=1;
    s.env.GetCourierState=function() return 0 end;
    s.bot.ActionImmediate_Courier=function(_,c,action) eq(c,s.couriers[1]);eq(action,6);transfers=transfers+1 end;
    purchaseRoot(s);s.env.ItemPurchaseThink();eq(transfers,1);eq(s.buys[1],"item_tango");
end);
test("disabled wards or diagnostic profile cannot buy or place fixed observers",function()
    for _,kind in ipairs({"disabled","diagnostic"}) do
        local s=scenario();local profile=s.env.require("bots/laning/profile");
        if kind=="disabled" then profile.wards_enabled=false else profile.runtime_enabled=true end;
        eq(s:vision("supply").TryPurchase(s.bot),false);s:item("item_ward_observer",0);
        eq(s:mod("wards").Tick(s.bot,s.state),false);eq(#s.buys,0);eq(#s.orders,0);
    end;
end);
print("VISION PASSED "..count.." cases (mock API; real rune vision unverified)");
