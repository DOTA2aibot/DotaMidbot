local U=require(GetScriptDirectory().."/laning/tactical/util");
local C=require(GetScriptDirectory().."/laning/tactical/config");
local B=require(GetScriptDirectory().."/laning/tactical/broker");
local M={};
function M.Consider(bot,s)
    if not U.Actor(bot) or U.Call(bot,"IsAlive")~=true or U.Now()<(s.requiem_block_until or -math.huge) then return 0 end;
    local a=U.Call(bot,"GetAbilityByName","nevermore_requiem");if not U.Ready(a) then return 0 end;
    local hp=U.HP(bot);local enemies=U.Call(bot,"GetNearbyHeroes",C.requiem_start_radius,true,BOT_MODE_NONE);
    if not hp or type(enemies)~="table" then return 0 end;
    local target,score,targets;
    targets={};
    for _,e in ipairs(enemies) do if U.Enemy(bot,e) and U.Call(e,"IsInvulnerable")==false then
        local p=U.HP(e);local value=0;
        if p and p<=C.requiem_enemy_hp then value=BOT_ACTION_DESIRE_HIGH or .75 end;
        if hp<=C.requiem_self_hp and U.Call(bot,"WasRecentlyDamagedByHero",e,2)==true then value=BOT_ACTION_DESIRE_VERYHIGH or .9 end;
        if value>0 then targets[#targets+1]=e;if not target or value>score then target,score=e,value end end;
    end end;
    if target then return score,target,{ability=a,targets=targets} end;return 0;
end;
function M.Submitted(bot,s,a,selection)
    if not selection or selection.ability~=a or not U.Actor(bot) then return end;
    s.requiem={ability=a,targets=selection.targets,at=U.Now(),phase_seen=false};
    B.Emit(s,"requiem_submitted",{target_count=#selection.targets,ownership="own_legacy_action_notification"});
end;
function M.Cancel(bot,s,reason)
    local q=s.requiem;local active=U.Call(bot,"GetCurrentActiveAbility");
    if not q or not U.Actor(bot) or active~=q.ability or U.Call(q.ability,"IsInAbilityPhase")~=true
        or U.Call(bot,"IsChanneling")~=false or U.Call(bot,"NumQueuedActions")~=0 then return false end;
    local done=B.Fire(bot,s,"cancel_requiem",q.ability,reason,function() return bot:Action_ClearActions(true) end,false);
    if done then
        s.requiem_block_until=U.Now()+C.requiem_recast_delay;s.cancel_check={ability=q.ability,at=U.Now()};s.requiem=nil;
    end;
    return done;
end;
function M.Tick(bot,s)
    local now=U.Now();
    if s.cancel_check then
        local p=U.Call(s.cancel_check.ability,"IsInAbilityPhase");
        if p==false then B.Emit(s,"requiem_phase_ended_after_cancel",{evidence="phase_false",resource_refund="not_inferred"});s.cancel_check=nil
        elseif now-s.cancel_check.at>.5 then B.Emit(s,"requiem_cancel_unknown",{reason="phase_end_not_observed"});s.cancel_check=nil end;
    end;
    local q=s.requiem;if not q then return false end;
    local phase=U.Call(q.ability,"IsInAbilityPhase");
    if phase==false then
        if q.phase_seen or now-q.at>C.requiem_unknown_timeout then
            B.Emit(s,"requiem_tracking_end",{reason=q.phase_seen and "phase_ended_release_or_interrupt_unknown" or "phase_not_observed"});s.requiem=nil;
        end;
        return false;
    end;
    if phase~=true or U.Call(bot,"GetCurrentActiveAbility")~=q.ability then return false end;
    q.phase_seen=true;
    if not C.requiem_cancel then return false end;
    local radius=U.Special(q.ability,{"requiem_radius","travel_distance","requiem_distance"});
    local cast=U.Call(q.ability,"GetCastPoint");local p=U.Pos(bot);
    if not radius or not p or not U.Number(cast) or cast<=0 then return false end;
    local remaining=math.max(0,cast-(now-q.at));
    local nearby=U.Call(bot,"GetNearbyHeroes",1599,true,BOT_MODE_NONE);if type(nearby)~="table" then return false end;
    local seen={};local keep=false;local unknown=false;
    local function check(e)
        if seen[e] then return end;seen[e]=true;
        if U.Call(e,"CanBeSeen")~=true then unknown=true;return end;
        if U.Call(e,"IsAlive")==false then return end;
        -- Fog never means escape. Even the original target must remain observable.
        if not U.Visible(e) or not U.Enemy(bot,e) then unknown=true;return end;
        local pos=U.Pos(e);local future=U.Point(U.Call(e,"GetExtrapolatedLocation",remaining));
        if not pos or not future then unknown=true;return end;
        if U.Distance(pos,p)<=radius+C.requiem_far_margin or U.Distance(future,p)<=radius+C.requiem_far_margin then keep=true end;
    end;
    for _,e in ipairs(q.targets) do check(e) end;
    for _,e in ipairs(nearby) do if U.Enemy(bot,e) then check(e) end end;
    if keep or unknown then q.far_since=nil;return false end;
    q.far_since=q.far_since or now;
    if now-q.far_since<C.requiem_far_hold then return false end;
    return M.Cancel(bot,s,"all_tracked_real_targets_confirmed_outside_requiem");
end;
return M;
