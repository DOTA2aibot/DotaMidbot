-- Guard only our own no-target Raze. No lane movement or persistent control lease.
local U=require(GetScriptDirectory().."/laning/tactical/util");
local B=require(GetScriptDirectory().."/laning/tactical/broker");
local C=require(GetScriptDirectory().."/laning/tactical/config");
local M={};
local STABLE_S=.025; -- one fresh callback, not a timed spell-preparation sequence
local SAMPLE_MAX_S=.15;
local MAX_TURN_DEG=3;
local function geometry(bot,a,aim,range,radius)
    local p=U.Pos(bot);local facing=U.Call(bot,"GetFacing");
    range=U.Special(a,{"shadowraze_range"}) or range;
    radius=U.Special(a,{"shadowraze_radius"}) or radius;
    if not p or not U.Number(facing) or not range or not radius or not aim then return end;
    local angle=math.rad(facing);
    local impact={x=p.x+math.cos(angle)*range,y=p.y+math.sin(angle)*range};
    return {position=p,facing=facing,aim=U.Point(aim),impact=impact,range=range,radius=radius,
        aim_error=U.Distance(impact,aim),current_action=U.Call(bot,"GetCurrentActionType")};
end;
function M.Ready(bot,a,aim,range,radius)
    if not C.enabled then return true end;
    local s=B.State(bot);local now=U.Now();if not s or not now then return false end;
    if now<(s.raze_retry_until or -math.huge) then return false end;
    local g=geometry(bot,a,aim,range,radius);if not g or g.aim_error>g.radius-40 then return false end;
    local previous=s.raze_facing;
    -- A target may change while we turn. Never reuse stability from a different direction/ability.
    local sample={at=now,facing=g.facing,ability=a,aim=U.Point(aim)};
    if not previous or previous.ability~=a or U.Distance(previous.aim,aim)>80 then s.raze_facing=sample;return false end;
    local dt=now-previous.at;local turn=math.abs((g.facing-previous.facing+180)%360-180);
    if dt>SAMPLE_MAX_S or turn>MAX_TURN_DEG then s.raze_facing=sample;return false end;
    -- At >40 callbacks/sec retain the first sample until25ms have elapsed.
    if dt<STABLE_S then return false end;
    s.raze_facing=sample;
    return true;
end;
function M.Submitted(bot,a,aim,range,radius)
    if not C.enabled then return end;
    local s=B.State(bot);local g=geometry(bot,a,aim,range,radius);if not s or not g then return end;
    s.raze_cast={ability=a,aim=U.Point(aim),range=g.range,radius=g.radius,at=U.Now(),
        cd=U.Call(a,"GetCooldownTimeRemaining")};s.raze_facing=nil;
    g.ability=U.Call(a,"GetName");g.hit="unknown";B.Emit(s,"raze_aim_submitted",g);
end;
local function visibleHit(bot,g)
    -- Do not cancel a cast which still hits another visible enemy in its actual circle.
    for _,method in ipairs({"GetNearbyHeroes","GetNearbyLaneCreeps","GetNearbyNeutralCreeps"}) do
        local list=U.Call(bot,method,1599,true,BOT_MODE_NONE);
        if type(list)~="table" then return nil end;
        for _,u in ipairs(list) do
            if U.Visible(u) and U.Call(u,"IsInvulnerable")==false and U.Call(u,"IsMagicImmune")~=true
                and U.Distance(U.Pos(u),g.impact)<=g.radius+20 then return true end;
        end;
    end;return false;
end;
function M.Poll(bot,s)
    local p=s and s.raze_cast;if not C.enabled or not p then return false end;
    local now=U.Now();if not now then return false end;
    if not U.Actor(bot) or U.Call(bot,"IsAlive")~=true then s.raze_cast=nil;return false end;
    local g=geometry(bot,p.ability,p.aim,p.range,p.radius);
    local cd=U.Call(p.ability,"GetCooldownTimeRemaining");
    if U.Number(cd) and U.Number(p.cd) and cd>p.cd+.05 then
        if g then g.ability=U.Call(p.ability,"GetName");g.elapsed=now-p.at;g.hit="unknown";
            g.evidence="cooldown_increased_geometry_at_observation_not_damage_confirmation";
            B.Emit(s,"raze_release_observed",g) end;
        s.raze_cast=nil;return false;
    end;
    if now-p.at>2 then
        B.Emit(s,"raze_phase_lost",{ability=U.Call(p.ability,"GetName"),elapsed=now-p.at,outcome="unknown",reason="ownership_expired"});
        s.raze_cast=nil;return false;
    end;
    local phase=U.Call(p.ability,"IsInAbilityPhase");local active=U.Call(bot,"GetCurrentActiveAbility");
    if phase==true and active==p.ability then
        if not p.phase_seen and g then g.ability=U.Call(p.ability,"GetName");B.Emit(s,"raze_phase_observed",g) end;
        p.phase_seen=true;
        if g and now-p.at>=.08 and g.aim_error>g.radius+20 and visibleHit(bot,g)==false
            and U.Call(bot,"IsChanneling")==false and type(bot.Action_ClearActions)=="function" then
            local fired=B.Fire(bot,s,"cancel_raze",p.ability,"owned_raze_facing_drift_no_visible_hit",function()
                return bot:Action_ClearActions(true);
            end,false);
            if fired then g.ability=U.Call(p.ability,"GetName");B.Emit(s,"raze_drift_cancelled",g);
                s.raze_cast=nil;s.raze_facing=nil;s.raze_retry_until=now+.25 end;
            return fired;
        end;
    elseif p.phase_seen or now-p.at>1.5 then
        B.Emit(s,"raze_phase_lost",{ability=U.Call(p.ability,"GetName"),elapsed=now-p.at,outcome="unknown"});s.raze_cast=nil;
    end;
    return false;
end;
return M;
