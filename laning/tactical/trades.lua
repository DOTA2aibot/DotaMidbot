-- A resource-backed Raze opportunity, not a new attack/movement controller.
local U=require(GetScriptDirectory().."/laning/tactical/util");
local C=require(GetScriptDirectory().."/laning/tactical/config");
local R=require(GetScriptDirectory().."/laning/tactical/resources");
local B=require(GetScriptDirectory().."/laning/tactical/broker");
local M={};
function M.Consider(bot,s)
    if C.enabled~=true or not U.CanUse(bot) or U.Call(bot,"IsSilenced")~=false or s.ward_pending or s.vision_phase or s.vision_support then return end;
    local mode=U.Call(bot,"GetActiveMode");
    if mode==nil or mode==BOT_MODE_RETREAT or (BOT_MODE_RUNE~=nil and mode==BOT_MODE_RUNE)
        or (BOT_MODE_EVASIVE_MANEUVERS~=nil and mode==BOT_MODE_EVASIVE_MANEUVERS) then return end;
    local resources=R.Read(bot,s);local p=U.Pos(bot);
    if not R.TradeCharged(resources)
        or resources.hp/resources.max_hp<C.wand_trade_min_hp or resources.potential_hp/resources.max_hp<C.wand_trade_potential_hp or not p then return end;
    local enemies=U.Call(bot,"GetNearbyHeroes",1200,true,BOT_MODE_NONE);local towers=U.Call(bot,"GetNearbyTowers",1599,true);
    if type(enemies)~="table" or type(towers)~="table" then return end;
    local target;local count=0;for _,e in ipairs(enemies) do if U.Enemy(bot,e) then count=count+1;target=e end end;
    if count~=1 or U.Call(target,"IsInvulnerable")~=false or U.Call(target,"IsMagicImmune")~=false then return end;
    for _,t in ipairs(towers) do if U.Visible(t) then local range=U.Call(t,"GetAttackRange");
        if not U.Number(range) or not U.Pos(t) or U.Distance(p,U.Pos(t))<=range+200 then return end;
    end end;
    -- Spell geometry and current castability remain mandatory, potential mana cannot cast a spell.
    for i=1,3 do local a=U.Call(bot,"GetAbilityByName","nevermore_shadowraze"..i);
        local cost=U.Cost(a);local range=U.Special(a,{"shadowraze_range"});local radius=U.Special(a,{"shadowraze_radius"});
        local point=U.Call(a,"GetCastPoint");local q=U.Number(point) and U.Point(U.Call(target,"GetExtrapolatedLocation",point));
        if U.Ready(a) and cost and cost>0 and resources.mana>=cost and resources.potential_mana>=2*cost and range and radius and q
            and math.abs(U.Distance(p,q)-range)<=radius-40 then
            if U.Now()>=(s.trade_report_after or -math.huge) then
                B.Emit(s,"charged_wand_trade",{charges=resources.charges,actual_mana=resources.mana,potential_mana=resources.potential_mana,
                    potential_hp=resources.potential_hp,ability=U.Call(a,"GetName"),movement_owner="unchanged_native"});s.trade_report_after=U.Now()+2;
            end;
            return BOT_ACTION_DESIRE_HIGH,q,a;
        end;
    end;
end;
return M;
