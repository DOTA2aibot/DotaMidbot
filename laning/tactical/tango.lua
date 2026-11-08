local U=require(GetScriptDirectory().."/laning/tactical/util");
local B=require(GetScriptDirectory().."/laning/tactical/broker");
local M={};
function M.Tick(bot,s)
    if not U.CanUse(bot) or not B.Free(s) or s.ward_pending then return false end;
    local fountain=U.Call(bot,"DistanceFromFountain");if U.Number(fountain) and fountain<600 then return false end;
    local hp,max=U.Call(bot,"GetHealth"),U.Call(bot,"GetMaxHealth");
    if not U.Number(hp) or not U.Number(max) or max<=0 or hp/max>=.85 or max-hp<90 then return false end;
    for _,modifier in ipairs({"modifier_tango_heal","modifier_flask_healing","modifier_bottle_regeneration"}) do
        if U.Call(bot,"HasModifier",modifier)~=false then return false end;
    end;
    local action=U.Call(bot,"GetCurrentActionType");
    if action==nil or (BOT_ACTION_TYPE_ATTACK~=nil and action==BOT_ACTION_TYPE_ATTACK) then return false end;
    local item=U.Item(bot,"item_tango") or U.Item(bot,"item_tango_single");
    local name=U.Call(item,"GetName");local charges=U.Call(item,"GetCurrentCharges");local range=U.Call(item,"GetCastRange");
    if not U.Ready(item) or not U.Number(charges) or charges<=0 or not B.RetryReady(s,name)
        or not U.Number(range) or range<=0 or type(bot.Action_UseAbilityOnTree)~="function" then return false end;
    local trees=U.Call(bot,"GetNearbyTrees",math.min(range,1599));local origin=U.Pos(bot);
    if type(trees)~="table" or not origin then return false end;
    local best,distance;
    for _,id in ipairs(trees) do if U.Number(id) and id>=0 then
        local p=U.Point(U.Global("GetTreeLocation",id));local d=U.Distance(origin,p);
        if d<=range-5 and (not distance or d<distance) then best,distance=id,d end;
    end end;
    if not best then return false end;
    B.Emit(s,"tango_decision",{tree=best,missing_hp=max-hp,distance=distance,reason="nearby_tree_regen"});
    return B.Fire(bot,s,"tango_tree",item,"nearby_tree_regen",function() return bot:Action_UseAbilityOnTree(item,best) end,true);
end;
return M;
