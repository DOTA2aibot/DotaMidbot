local U=require(GetScriptDirectory().."/laning/tactical/util");
local C=require(GetScriptDirectory().."/laning/tactical/config");
local B=require(GetScriptDirectory().."/laning/tactical/broker");
local Q=require(GetScriptDirectory().."/laning/tactical/requiem");
local M={};
local function damage(a,bot)
    local raw=U.Call(a,"GetAbilityDamage");if not U.Number(raw) or raw<0 then return nil end;
    local dt=U.Call(a,"GetDamageType");if dt==nil then return nil end;
    local actual=U.Call(bot,"GetActualIncomingDamage",raw,dt);if U.Number(actual) and actual>=0 then return actual end;
end;
local function dangerous(a,bot)
    local name=U.Call(a,"GetName");local disable=name and C.control_spells[name] or false;
    local hp=U.Call(bot,"GetHealth");local max=U.Call(bot,"GetMaxHealth");local dmg=damage(a,bot);
    -- No assumptions about hidden cooldowns or every projectile being a stun.
    if disable then return true,"visible_control_threat",dmg end;
    if U.Number(hp) and U.Number(max) and max>0 and dmg and dmg>0
        and (dmg>=hp*.5 or (hp/max<=C.bkb_low_hp and dmg>=max*.08) or dmg>=max*C.bkb_burst_hp_fraction) then
        return true,"visible_damage_threat",dmg;
    end;
    return false;
end;
local function hostile(bot,a)
    local caster=U.Call(a,"GetCaster");local team=U.Call(caster,"GetTeam");local own=U.Call(bot,"GetTeam");
    return U.Number(team) and U.Number(own) and team~=own;
end;
function M.Consider(bot,s)
    local own=U.Pos(bot);if not own then return nil end;
    local ps=U.Call(bot,"GetIncomingTrackingProjectiles");
    for _,p in pairs(type(ps)=="table" and ps or {}) do
        if p.is_attack==false and p.ability and hostile(bot,p.ability) then
            local yes,reason,dmg=dangerous(p.ability,bot);
            if yes then return {reason=reason,ability=U.Call(p.ability,"GetName"),damage=dmg,evidence="incoming_tracking_spell_targeted_at_self"} end;
        end;
    end;
    local linear=U.Global("GetLinearProjectiles");
    for _,p in pairs(type(linear)=="table" and linear or {}) do
        local location,velocity=U.Point(p.location),U.Point(p.velocity);
        if p.ability and hostile(bot,p.ability) and location and velocity and U.Number(p.radius) then
            local vx,vy=velocity.x,velocity.y;local speed=vx*vx+vy*vy;
            if speed>1 then
                local dx,dy=own.x-location.x,own.y-location.y;local eta=(dx*vx+dy*vy)/speed;
                local collision=U.Call(bot,"GetBoundingRadius");if not U.Number(collision) then collision=24 end;
                local miss=math.sqrt((dx-vx*eta)^2+(dy-vy*eta)^2);
                if eta>=0 and eta<=C.bkb_threat_horizon and miss<=p.radius+collision then
                    local yes,reason,dmg=dangerous(p.ability,bot);
                    if yes then return {reason=reason,ability=U.Call(p.ability,"GetName"),damage=dmg,eta=eta,evidence="visible_linear_spell_intersection"} end;
                end;
            end;
        end;
    end;
    local enemies=U.Call(bot,"GetNearbyHeroes",1000,true,BOT_MODE_NONE);
    for _,e in ipairs(type(enemies)=="table" and enemies or {}) do
        if U.Enemy(bot,e) then
            local a=U.Call(e,"GetCurrentActiveAbility");local range=U.Call(a,"GetCastRange");
            if U.Call(a,"IsInAbilityPhase")==true and U.Call(e,"GetTarget")==bot
                and U.Number(range) and U.Distance(own,U.Pos(e))<=range+100 then
                local yes,reason,dmg=dangerous(a,bot);
                if yes then return {reason=reason,ability=U.Call(a,"GetName"),damage=dmg,evidence="visible_enemy_cast_phase_and_target_hint"} end;
            end;
        end;
    end;
    local hp,max=U.Call(bot,"GetHealth"),U.Call(bot,"GetMaxHealth");
    local recent=U.Call(bot,"WasRecentlyDamagedByAnyHero",1)==true;
    if s and U.Number(hp) and U.Number(max) and max>0 and recent and DAMAGE_TYPE_MAGICAL~=nil then
        local old=s.damage_sample;
        local burst=old and U.Now()-old.at<=.8 and old.max==max and old.hp-hp>=max*.12;
        if burst or hp/max<=.35 then
            for _,e in ipairs(type(enemies)=="table" and enemies or {}) do if U.Enemy(bot,e) then
                local potential=U.Call(e,"GetEstimatedDamageToTarget",true,bot,1,DAMAGE_TYPE_MAGICAL);
                if U.Number(potential) and potential>=max*.15 then
                    return {reason="recent_burst_with_visible_magic_potential",damage=potential,
                        evidence="own_damage_and_public_enemy_estimate",damage_type="not_proven",enemy_cooldowns="not_read"};
                end;
            end end;
        end;
    end;
end;
function M.Tick(bot,s)
    if not C.bkb or not U.Actor(bot) or U.Call(bot,"IsAlive")~=true then return false end;
    local item=U.Item(bot,"item_black_king_bar");
    if not U.Ready(item) or not B.RetryReady(s,"item_black_king_bar")
        or U.Call(bot,"HasModifier","modifier_black_king_bar_immune")~=false then return false end;
    local p=M.Consider(bot,s);
    local hp,max=U.Call(bot,"GetHealth"),U.Call(bot,"GetMaxHealth");
    if U.Number(hp) and U.Number(max) and (not s.damage_sample or U.Now()-s.damage_sample.at>=.15) then s.damage_sample={hp=hp,max=max,at=U.Now()} end;
    if not p then return false end;
    B.Emit(s,"bkb_decision",p);
    if not U.CanUse(bot) then
        -- Deliberately interrupt only an owned Requiem, never another caster/channel.
        if s.requiem then return Q.Cancel(bot,s,"defensive_bkb_before_incoming_threat") end;
        return false;
    end;
    return B.Self(bot,s,item,p.reason,true);
end;
return M;
