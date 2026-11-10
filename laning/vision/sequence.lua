-- Sentry coverage -> bounded local enemy-Sentry cleanup -> idle Observer.
-- No lane controller, hidden-unit inference, chase, or attack/kill credit guess.
local U=require(GetScriptDirectory().."/laning/tactical/util");
local B=require(GetScriptDirectory().."/laning/tactical/broker");
local C=require(GetScriptDirectory().."/laning/vision/config");
local Sentry=require(GetScriptDirectory().."/laning/vision/sentry");
local I=require(GetScriptDirectory().."/laning/vision/ward_items");
local Deward=require(GetScriptDirectory().."/laning/vision/deward");
local M={};
function M.Enabled(bot)
    local now=U.Now();return C.sentry_first==true and Sentry.Enabled(bot) and now~=nil and now<C.recovery_end_s;
end;
function M.ObserverTransition(bot,s)
    return M.Enabled(bot) and Sentry.WaitingToggle(bot,s and s.observer_toggle_wait) or false;
end;
local function nearbyEnemy(bot,site)
    local list=UNIT_LIST_ENEMIES~=nil and U.Global("GetUnitList",UNIT_LIST_ENEMIES);
    if type(list)~="table" then return nil,"enemy_ward_list_unknown" end;
    local found={};
    for _,w in ipairs(list) do
        if Deward.Valid(bot,w) and I.Kind(U.Call(w,"GetUnitName"))=="sentry"
            and U.Distance(U.Pos(w),site)<=C.sentry_enemy_site_radius then found[#found+1]=w end;
    end;return found;
end;
function M.ObserverAllowed(bot)
    if not M.Enabled(bot) then return true end;
    local site,why=Sentry.Point();if not site then return false,why or "sentry_site_unknown" end;
    local wards,unknown=I.Allied("sentry",site,C.dedup_radius);
    if not wards then return false,unknown end;
    if #wards==0 then return false,"sentry_coverage_first" end;
    local s=B.State(bot);M.Poll(bot,s);local pending=s and s.sentry_followup;
    if pending and U.Now()<pending.deadline then return false,"sentry_local_cleanup_first" end;
    local enemies,why=nearbyEnemy(bot,site);if not enemies then return false,why end;
    if #enemies>0 then return false,"visible_enemy_sentry_first" end;
    return true;
end;
function M.Finish(bot,s,reason)
    local p=s and s.sentry_followup;if not p then return end;
    B.Emit(s,"sentry_followup_end",{reason=reason,attempts=p.attempts,health_drops=p.health_drops,
        own_kill_credit="unknown"});
    if s.vision_support==p then s.vision_support=nil end;
    s.sentry_followup=nil;
end;
function M.Begin(bot,s,job)
    if not M.Enabled(bot) or not job or not job.window then return end;
    local now=U.Now();local deadline=math.min(now+C.sentry_followup_s,job.window.finish);
    if now>=deadline then return end;
    s.sentry_followup={kind="sentry_followup",site=job.location,window=job.window,started=now,deadline=deadline,
        reveal_until=math.min(now+C.sentry_reveal_grace_s,deadline),attempts=0,health_drops=0,max_attempts=2,no_chase=true};
    B.Emit(s,"sentry_followup_armed",{deadline=deadline,site=job.location,policy="visible_in_attack_range_only"});
end;
local function inRange(bot,target)
    local range=U.Call(bot,"GetAttackRange");
    return U.Number(range) and range>0 and U.Distance(U.Pos(bot),U.Pos(target))<=range;
end;
function M.Safe(bot,p)
    if not M.Enabled(bot) or U.Call(bot,"IsAlive")~=true then return false,"disabled_or_dead" end;
    if not U.CanUse(bot) then return false,"busy" end;
    local mode=U.Call(bot,"GetActiveMode");
    if mode==nil or mode==BOT_MODE_RETREAT or mode==BOT_MODE_RUNE
        or (BOT_MODE_EVASIVE_MANEUVERS~=nil and mode==BOT_MODE_EVASIVE_MANEUVERS) then return false,"priority_mode" end;
    local hp=U.HP(bot);local recent=U.Call(bot,"TimeSinceDamagedByAnyHero");
    if not hp or hp<.55 or not U.Number(recent) or recent<1.5 then return false,"health_or_recent_damage" end;
    local pos=U.Pos(bot);local heroes=U.Call(bot,"GetNearbyHeroes",1599,true,BOT_MODE_NONE);
    local towers=U.Call(bot,"GetNearbyTowers",1599,true);local projectiles=U.Call(bot,"GetIncomingTrackingProjectiles");
    if not pos or type(heroes)~="table" or type(towers)~="table" or type(projectiles)~="table" then return false,"safety_unknown" end;
    for _,e in ipairs(heroes) do if U.Visible(e) then
        local distance=U.Distance(pos,U.Pos(e));local range=U.Call(e,"GetAttackRange");
        if distance<=450 or (U.Call(e,"GetAttackTarget")==bot and (not U.Number(range) or distance<=range+150))
            or (U.Call(e,"IsUsingAbility")==true and (U.Call(e,"GetTarget")==bot or U.Call(e,"GetAbilityTarget")==bot)) then
            return false,"direct_hero_threat";
        end;
    end end;
    for _,shot in ipairs(projectiles) do
        if shot.caster and U.Call(shot.caster,"IsHero")==true and U.Call(shot.caster,"GetTeam")~=U.Call(bot,"GetTeam") then return false,"incoming_hero_projectile" end;
    end;
    for _,t in ipairs(towers) do if U.Visible(t) then local range=U.Call(t,"GetAttackRange");
        if not U.Number(range) or U.Distance(pos,U.Pos(t))<=range+150 then return false,"tower_threat" end;
    end end;
    local action=U.Call(bot,"GetCurrentActionType");
    if action==BOT_ACTION_TYPE_ATTACK then
        local target=U.Call(bot,"GetAttackTarget");
        if target~=p.target and U.Call(target,"IsHero")~=false then return false,"hero_or_unknown_attack_priority" end;
    elseif action~=BOT_ACTION_TYPE_IDLE and action~=BOT_ACTION_TYPE_NONE and action~=BOT_ACTION_TYPE_MOVE_TO then return false,"native_action" end;
    -- Lane creeps intentionally do not preempt this one local completion step.
    if not Deward.Valid(bot,p.target) or not inRange(bot,p.target) then return false,"target_hidden_or_out_of_range" end;
    return true;
end;
function M.Poll(bot,s)
    local p=s and s.sentry_followup;if not p then return end;
    if not M.Enabled(bot) or U.Call(bot,"IsAlive")~=true or U.Now()>=p.deadline then M.Finish(bot,s,"expired_or_disabled");return end;
    if p.target then
        if Deward.Destroyed(bot,s,p) then M.Finish(bot,s,"ward_destroyed_observed");return end;
        if not Deward.Valid(bot,p.target) or not inRange(bot,p.target) then M.Finish(bot,s,"target_hidden_or_out_of_range");return end;
    else
        local enemies=nearbyEnemy(bot,p.site);local best,distance;
        for _,w in ipairs(enemies or {}) do local d=U.Distance(U.Pos(bot),U.Pos(w));
            if inRange(bot,w) and (not distance or d<distance) then best=w;distance=d end;
        end;
        if best then p.target=best;p.location=U.Pos(best);p.range=U.Call(bot,"GetAttackRange");
            B.Emit(s,"sentry_followup_target",{location=p.location,distance=distance});
        elseif U.Now()>=p.reveal_until then M.Finish(bot,s,enemies and "no_visible_sentry_in_attack_range" or "enemy_ward_list_unknown") end;
    end;
end;
function M.Candidate(bot,s)
    M.Poll(bot,s);local p=s.sentry_followup;
    if p and p.target and M.Safe(bot,p) then return p end;
end;
function M.Holds(bot,s,p)
    M.Poll(bot,s);if s.sentry_followup~=p then return false end;
    local safe,why=M.Safe(bot,p);if not safe then M.Finish(bot,s,why);return false end;
    return true;
end;
function M.Execute(bot,s,p)
    if not M.Holds(bot,s,p) or not B.Free(s) then return end;
    -- Recheck range before every order. This executor never calls Step/Move.
    Deward.Execute(bot,s,p);
end;
return M;
