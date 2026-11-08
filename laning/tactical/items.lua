-- Complete the existing basic item slice, so legacy mango/clarity cannot bypass
-- the new safety/mana gates. The original callback is retained for disabled mode.
local U=require(GetScriptDirectory().."/laning/tactical/util");
local B=require(GetScriptDirectory().."/laning/tactical/broker");
local Mana=require(GetScriptDirectory().."/laning/tactical/mana");
local M={};
function M.Tick(bot,s)
    if not U.CanUse(bot) or s.ward_pending or not B.Free(s) then return false end;
    local hp=U.HP(bot);local mana,max=U.Call(bot,"GetMana"),U.Call(bot,"GetMaxMana");
    if not hp or not U.Number(mana) or not U.Number(max) or max<=0 then return false end;
    for _,name in ipairs({"item_magic_wand","item_magic_stick"}) do
        local item=U.Item(bot,name);local charges=U.Call(item,"GetCurrentCharges");
        if U.Ready(item) and U.Number(charges) and charges>=8 and B.RetryReady(s,name)
            and (hp<.4 or (hp<.6 and mana/max<.25)) then return B.Self(bot,s,item,"basic_emergency_wand",true) end;
    end;
    if Mana.Tick(bot,s) then return true end;
    local bottle=U.Item(bot,"item_bottle");local charges=U.Call(bottle,"GetCurrentCharges");
    if U.Ready(bottle) and U.Number(charges) and charges>0 and B.RetryReady(s,"item_bottle")
        and U.Call(bot,"HasModifier","modifier_bottle_regeneration")==false then
        local enemies=U.Call(bot,"GetNearbyHeroes",700,true,BOT_MODE_NONE);local calm=type(enemies)=="table" and #enemies==0;
        local first=U.Call(bot,"GetAbilityByName","nevermore_shadowraze1");local cost=U.Cost(first);
        if type(enemies)=="table" and ((calm and (mana/max<.45 or hp<.50)) or (not calm and cost and mana<cost)) then
            return B.Self(bot,s,bottle,"basic_bottle_resource",true);
        end;
    end;
    local salve=U.Item(bot,"item_flask");
    if U.Ready(salve) and hp<.5 and B.RetryReady(s,"item_flask")
        and U.Call(bot,"HasModifier","modifier_flask_healing")==false and Mana.Safe(bot) then
        return B.Self(bot,s,salve,"basic_safe_salve",true);
    end;
    return false;
end;
return M;
