-- Only restore mana for a visible, geometrically reachable, potentially lethal Raze.
local U=require(GetScriptDirectory().."/laning/tactical/util");
local B=require(GetScriptDirectory().."/laning/tactical/broker");
local C=require(GetScriptDirectory().."/laning/tactical/config");
local PT=require(GetScriptDirectory().."/laning/tactical/treads");
local Resources=require(GetScriptDirectory().."/laning/tactical/resources");
local M={};
function M.Consider(bot,s)
    if not U.CanUse(bot) or U.Call(bot,"IsSilenced")~=false then return nil end;
    local mana=U.Call(bot,"GetMana");local p=U.Pos(bot);local enemies=U.Call(bot,"GetNearbyHeroes",1200,true,BOT_MODE_NONE);
    if not U.Number(mana) or not p or type(enemies)~="table" then return nil end;
    for _,e in ipairs(enemies) do
        if U.Enemy(bot,e) and U.Call(e,"IsInvulnerable")==false and U.Call(e,"IsMagicImmune")==false then
            for i=1,3 do local a=U.Call(bot,"GetAbilityByName","nevermore_shadowraze"..i);
                local cd=U.Call(a,"GetCooldownTimeRemaining");local cost=U.Cost(a);
                local range=U.Special(a,{"shadowraze_range"});local radius=U.Special(a,{"shadowraze_radius"});
                local raw=U.Special(a,{"shadowraze_damage","damage"}) or U.Call(a,"GetAbilityDamage");
                local point=U.Call(a,"GetCastPoint");local q=U.Number(point) and U.Point(U.Call(e,"GetExtrapolatedLocation",point)) or nil;
                local hp=U.Call(e,"GetHealth");local regen=U.Call(e,"GetHealthRegen");
                local actual=U.Number(raw) and raw>0 and U.Call(e,"GetActualIncomingDamage",raw,DAMAGE_TYPE_MAGICAL);
                if U.Call(a,"GetLevel") and U.Call(a,"GetLevel")>0 and U.Call(a,"IsHidden")==false
                    and U.Number(cd) and cd<=0 and cost and mana<cost and range and radius and q
                    and math.abs(U.Distance(p,q)-range)<=radius-40 and U.Number(hp) and U.Number(actual)
                    and actual>=hp+(U.Number(regen) and math.max(0,regen)*point or 0)+10 then
                    return {ability=a,target=e,cost=cost,location=q,damage_estimate=actual};
                end;
            end;
        end;
    end;
end;
function M.Tick(bot,s)
    if not B.Free(s) or s.ward_pending or s.vision_phase or U.Now()<(s.finisher_retry or -math.huge) then return false end;
    local plan=M.Consider(bot,s);if not plan then return false end;
    local resources=Resources.Read(bot,s);if not resources then return false end;
    -- PT gain is not guessed from a fixed stat conversion: switch once, then reread actual mana.
    if PT.CanPrepareMana(bot) then
        local ready,issued=PT.Before(bot,s,plan.ability);
        if not ready then return true end;
        resources=Resources.Read(bot,s);
        if resources and resources.item and resources.known and resources.potential_mana>=plan.cost then
            return Resources.Use(bot,s,resources,"lethal_raze_after_int_readback");
        end;
        s.finisher_retry=U.Now()+C.finisher_retry_s;PT.Release(s);
        B.Emit(s,"combat_resource_skip",{reason="int_readback_still_insufficient",cost=plan.cost,mana=U.Call(bot,"GetMana")});
        return issued;
    end;
    if resources.item and resources.known and resources.potential_mana>=plan.cost then
        return Resources.Use(bot,s,resources,"lethal_raze_mana_deficit");
    end;
    s.finisher_retry=U.Now()+C.finisher_retry_s;return false;
end;
return M;
