-- Preserve the old one-salve allowance as optional supply, not a core build stage.
-- Does not move the hero or use items; existing courier/item logic owns those actions.
local A=require(GetScriptDirectory().."/laning/runtime/api");
local O=require(GetScriptDirectory().."/laning/observer/core");
local P=require(GetScriptDirectory().."/laning/profile");
local Inventory=require(GetScriptDirectory().."/laning/economy/mana");
local states=setmetatable({},{__mode="k"});local M={};
function M.TryPurchase(bot)
    if P.economy_enabled~=true then return false end;
    local now=A.Time();if not A.Number(now) or now<0 or now>600 or A.Call(bot,"IsAlive")~=true then return false end;
    local s=states[bot] or {};states[bot]=s;
    if s.spent or now<(s.retry or -math.huge) then return false end;
    local hp,maxhp=A.Call(bot,"GetHealth"),A.Call(bot,"GetMaxHealth");
    if not A.Number(hp) or not A.Number(maxhp) or maxhp<=0 or hp/maxhp>=.5 or maxhp-hp<250 then return false end;
    local inv=Inventory.Inventory(bot);if not inv or not inv.bottle then return false end;
    for _,name in ipairs({"item_tango","item_tango_single","item_flask"}) do
        if inv.owned[name] then return false end;
    end;
    for slot=0,14 do
        local item=A.Call(bot,"GetItemInSlot",slot);
        if item and A.Call(item,"GetName")=="item_bottle" then
            local charges=A.Call(item,"GetCurrentCharges");
            if not A.Number(charges) or charges>0 then return false end;
        end;
    end;
    for _,mod in ipairs({"modifier_flask_healing","modifier_tango_heal","modifier_bottle_regeneration"}) do
        if A.Call(bot,"HasModifier",mod)~=false then return false end;
    end;
    local cost=O.Global("GetItemCost","item_flask");local gold=A.Call(bot,"GetGold");
    if PURCHASE_ITEM_SUCCESS==nil or not A.Number(cost) or cost<0 or not A.Number(gold) or gold<cost then return false end;
    s.retry=now+5;
    -- Unknown may mean the purchase already happened; never double-spend its one-salve budget.
    s.spent=true;
    local ok,result=pcall(function() return bot:ActionImmediate_PurchaseItem("item_flask") end);
    if ok and A.Number(result) and result~=PURCHASE_ITEM_SUCCESS then s.spent=false end;
    pcall(function() O.Emit(O.State(bot),"health_supply_purchase",{item="item_flask",result=result,
        api_returned=ok,outcome="purchase_not_delivery",allowance="one_optional_salve_after_bottle"}) end);
    return true;
end;
return M;
