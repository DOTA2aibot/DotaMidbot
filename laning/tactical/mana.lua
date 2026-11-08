local U=require(GetScriptDirectory().."/laning/tactical/util");
local C=require(GetScriptDirectory().."/laning/tactical/config");
local B=require(GetScriptDirectory().."/laning/tactical/broker");
local M={};
function M.Budget(bot,combo)
    local total=0;local count=0;
    for i=1,3 do
        local a=U.Call(bot,"GetAbilityByName","nevermore_shadowraze"..i);
        if (U.Call(a,"GetLevel") or 0)>0 then
            local cost=U.Cost(a);if not cost then return nil end;total=total+cost;count=count+1;
        end;
    end;
    if count==0 then return nil end;
    if combo then
        for _,name in ipairs({"nevermore_requiem","nevermore_frenzy"}) do
            local a=U.Call(bot,"GetAbilityByName",name);local cd=U.Call(a,"GetCooldownTimeRemaining");
            if (U.Call(a,"GetLevel") or 0)>0 and U.Number(cd) and cd<=0 then
                local cost=U.Cost(a);if not cost then return nil end;total=total+cost;
            end;
        end;
    end;
    return total;
end;
function M.Safe(bot)
    local enemies=U.Call(bot,"GetNearbyHeroes",C.safe_enemy_radius,true,BOT_MODE_NONE);
    if type(enemies)~="table" then return false end;
    for _,e in ipairs(enemies) do if U.Visible(e) then return false end end;
    local gap=U.Call(bot,"TimeSinceDamagedByAnyHero");
    if not U.Number(gap) or gap<C.safe_damage_gap then return false end;
    local projectiles=U.Call(bot,"GetIncomingTrackingProjectiles");if type(projectiles)~="table" or #projectiles>0 then return false end;
    local towers=U.Call(bot,"GetNearbyTowers",1200,true);local p=U.Pos(bot);
    if not p or type(towers)~="table" then return false end;
    for _,t in ipairs(towers) do if U.Visible(t) then local range=U.Call(t,"GetAttackRange");
        if not U.Number(range) or U.Distance(p,U.Pos(t))<=range+100 then return false end;
    end end;
    return true;
end;
function M.Consider(bot,s)
    if not C.mana_items or not U.CanUse(bot) or s.ward_pending then return nil end;
    local mana,max=U.Call(bot,"GetMana"),U.Call(bot,"GetMaxMana");
    if not U.Number(mana) or not U.Number(max) or max<=0 then return nil end;
    local enemies=U.Call(bot,"GetNearbyHeroes",C.safe_enemy_radius,true,BOT_MODE_NONE);
    if type(enemies)~="table" then return nil end;
    local combat=false;for _,e in ipairs(enemies) do if U.Visible(e) then combat=true end end;
    local budget=M.Budget(bot,combat);if not budget then return nil end;
    local missing=max-mana;local deficit=math.min(max,budget)-mana;
    if deficit<=0 or missing<C.mana_min_missing then return nil end;
    local mango=U.Item(bot,"item_enchanted_mango");
    local clarity=U.Item(bot,"item_clarity");local bottle=U.Item(bot,"item_bottle");
    local bottleCharges=U.Call(bottle,"GetCurrentCharges");
    local haveBottle=U.Ready(bottle) and U.Number(bottleCharges) and bottleCharges>0;
    local noCalmAlternative=not U.Ready(clarity) and not haveBottle
        and U.Call(bot,"HasModifier","modifier_clarity_potion")==false
        and U.Call(bot,"HasModifier","modifier_bottle_regeneration")==false;
    if (combat or noCalmAlternative) and U.Ready(mango) and B.RetryReady(s,"item_enchanted_mango") then
        local restore=U.Special(mango,{"restore_mana","mana_restore","mana"});
        if missing>=C.mana_min_missing and (not restore or deficit>=math.min(C.mana_min_missing,restore*.5)) then
            return {item=mango,reason=combat and "combat_combo_mana_deficit" or "calm_mana_deficit_no_regen_alternative",budget=budget,deficit=deficit};
        end;
    end;
    if not combat and U.Ready(clarity) and B.RetryReady(s,"item_clarity")
        and U.Call(bot,"HasModifier","modifier_clarity_potion")==false and M.Safe(bot) then
        return {item=clarity,reason="safe_three_raze_mana_deficit",budget=budget,deficit=deficit};
    end;
end;
function M.Tick(bot,s)
    local p=M.Consider(bot,s);if not p then return false end;
    B.Emit(s,"mana_decision",{reason=p.reason,budget=p.budget,deficit=p.deficit,mana=U.Call(bot,"GetMana")});
    return B.Self(bot,s,p.item,p.reason,true);
end;
return M;
