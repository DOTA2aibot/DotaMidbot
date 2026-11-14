-- An explicit, opt-in replacement of SF ROAM; ordinary native lane/attack modes remain available.
local U=require(GetScriptDirectory().."/laning/tactical/util");
local B=require(GetScriptDirectory().."/laning/tactical/broker");
local Raze=require(GetScriptDirectory().."/laning/tactical/raze");
local O=require(GetScriptDirectory().."/laning/observer/core");
local Risk=require(GetScriptDirectory().."/laning/pressure/risk");
local C=require(GetScriptDirectory().."/laning/pressure/config");
local Profile=require(GetScriptDirectory().."/laning/profile");
local M={};
local function state(bot) return B.State(bot) end;
local function enabled(bot) return Profile.tower_pressure_enabled==true and U.Actor(bot) end;
function M.Holds(bot) local s=enabled(bot) and state(bot);return s and s.pressure~=nil or false end;
function M.Exiting(bot) local s=enabled(bot) and state(bot);return s and s.pressure and s.pressure.exiting==true or false end;
local function report(s,reason,plan)
    if U.Now()<(s.pressure_report_after or -math.huge) and s.pressure_report_reason==reason then return end;
    s.pressure_report_after=U.Now()+2;s.pressure_report_reason=reason;
    B.Emit(s,"tower_pressure_decision",{reason=reason,allowed=plan~=nil,lethal=plan and plan.lethal,
        tower_shots=plan and plan.tower_shots,damage_estimate=plan and plan.damage,
        incoming_estimate=plan and plan.incoming,reserve=plan and plan.reserve,
        hp_after_estimate=plan and plan.hp_after_estimate,escape_seconds=plan and plan.escape_seconds,
        covered=plan and plan.cover~=nil,kill="unproven",safety="estimate_not_guarantee"});
end;
local function beginExit(bot,s,reason)
    local phase=s.pressure;if not phase or phase.exiting then return end;
    phase.exiting=true;phase.exit_started=U.Now();phase.exit=Risk.Exit(bot,phase.tower) or phase.exit;
    if phase.drop then B.Emit(s,"tower_deaggro_readback",{confirmed=false,reason="exit_before_ack"});phase.drop=nil end;
    B.Emit(s,"tower_pressure_exit",{reason=reason,has_exit=phase.exit~=nil});
end;
function M.Leave(bot,reason)
    local s=state(bot);if not s then return end;
    if s.pressure then B.Emit(s,"tower_pressure_end",{reason=reason or "mode_ended",kill="unknown"}) end;
    s.pressure=nil;s.pressure_candidate=nil;s.pressure_retry=U.Now()+C.retry_s;
    -- Never ClearActions on mode exit: a new native action, BKB or cast may already own the bot.
end;
local function farmDue(bot)
    local creeps=U.Call(bot,"GetNearbyLaneCreeps",1200,true);local p=U.Pos(bot);
    local damage,range=U.Call(bot,"GetAttackDamage"),U.Call(bot,"GetAttackRange");
    if type(creeps)~="table" or not p or not U.Number(damage) or not U.Number(range) then return true end;
    for _,c in ipairs(creeps) do if U.Visible(c) then
        local hp=U.Call(c,"GetHealth");local actual=U.Call(c,"GetActualIncomingDamage",damage,DAMAGE_TYPE_PHYSICAL);
        if not U.Number(hp) or not U.Number(actual) then return true end;
        if U.Distance(p,U.Pos(c))<=range+50 and hp<=actual*1.5 then return true end;
    end end;
    return false;
end;
function M.Decide(bot)
    if not enabled(bot) then return nil,"profile_disabled" end;
    local s=state(bot);local now=U.Now();if not now or now<30 then return nil,"startup_first" end;
    if s.pressure then
        local phase=s.pressure;local p=U.Pos(bot);local tp=U.Pos(phase.tower);local range=U.Call(phase.tower,"GetAttackRange");
        if U.Call(bot,"IsAlive")~=true then M.Leave(bot,"dead");return nil,"dead" end;
        if not p or not tp or not U.Number(range) then M.Leave(bot,"tower_or_position_lost");return nil,"position_unknown" end;
        if not phase.exiting then
            local plan,reason=Risk.Evaluate(bot,phase.target,phase.tower,phase.was_covered);
            local mode=U.Call(bot,"GetActiveMode");
            if mode==BOT_MODE_RETREAT or mode==BOT_MODE_EVASIVE_MANEUVERS then beginExit(bot,s,"native_danger")
            elseif now-phase.started>C.max_session_s then beginExit(bot,s,"bounded_session")
            elseif U.Distance(U.Pos(phase.target),phase.target_start)>C.max_chase then beginExit(bot,s,"chase_limit")
            elseif not plan then beginExit(bot,s,reason)
            else
                phase.plan=plan;
                if not plan.lethal and now-phase.started>C.covered_session_s then beginExit(bot,s,"covered_budget_finished") end;
            end;
        end;
        if phase.exiting then
            if U.Distance(p,tp)>range+C.exit_margin-40 or now-phase.exit_started>4 or not phase.exit then
                M.Leave(bot,"exit_complete_or_expired");return nil,"exit_complete_or_expired";
            end;
            return {phase="exit",desire=.88},"exit_to_native_lane";
        end;
        return {phase="pressure",desire=C.committed_desire},"committed_pressure";
    end;
    if now<(s.pressure_retry or -math.huge) or not U.CanUse(bot) or U.Call(bot,"IsRooted")~=false then return nil,"busy_or_retry" end;
    local mode=U.Call(bot,"GetActiveMode");
    if mode==nil or mode==BOT_MODE_RETREAT or mode==BOT_MODE_RUNE or mode==BOT_MODE_WARD
        or mode==BOT_MODE_EVASIVE_MANEUVERS or s.vision_phase or s.vision_support then return nil,"priority_mode" end;
    local tower=Risk.Tower(bot);if not tower then return nil,"no_visible_mid_t1" end;
    local position,range=U.Pos(bot),U.Call(tower,"GetAttackRange");
    if not position or not U.Number(range) or U.Distance(position,U.Pos(tower))>range+C.max_entry_distance then return nil,"outside_mid_t1" end;
    if farmDue(bot) then return nil,"last_hit_first" end;
    local ok,rune=pcall(require,GetScriptDirectory().."/laning/economy/runes");
    if not ok then return nil,"rune_first_or_unknown" end;
    local runeOK,runePlan=pcall(rune.Decide,bot);
    if not runeOK or runePlan then return nil,"rune_first_or_unknown" end;
    local heroes=U.Call(bot,"GetNearbyHeroes",1599,true,BOT_MODE_NONE);
    if type(heroes)~="table" then return nil,"heroes_unknown" end;
    local target;for _,h in ipairs(heroes) do if U.Enemy(bot,h) then
        if target then return nil,"multiple_enemies" end;target=h;
    end end;
    local plan,reason=Risk.Evaluate(bot,target,tower);report(s,reason,plan);
    if plan then s.pressure_candidate=plan;s.pressure_candidate_at=now;return {phase="pressure",desire=C.desire},reason end;
    return nil,reason;
end;
function M.GetDesire(bot)
    local ok,plan=pcall(M.Decide,bot);
    if not ok then M.Fail(bot,"pressure_desire",plan);return 0 end;
    return plan and plan.desire or 0;
end;
function M.Fail(bot,where,err)
    local s=state(bot);if not s then return end;
    if U.Now()>=(s.pressure_error_after or -math.huge) then
        B.Emit(s,"helper_error",{where=where,error=tostring(err):sub(1,180)});s.pressure_error_after=U.Now()+2;
    end;
    M.Leave(bot,"helper_error_release");
end;
function M.Start(bot)
    if not enabled(bot) then return end;
    local s=state(bot);if s.pressure then return end;
    local decision,reason=M.Decide(bot);local plan=s.pressure_candidate;
    if not decision or not plan or s.pressure_candidate_at~=U.Now() then report(s,reason);return end;
    s.pressure={target=plan.target,tower=plan.tower,plan=plan,was_covered=plan.cover~=nil,started=U.Now(),exit=plan.exit,
        target_start=U.Pos(plan.target),last_progress=U.Now(),last_position=U.Pos(bot)};
    B.Emit(s,"tower_pressure_start",{covered=plan.cover~=nil,lethal=plan.lethal,
        damage_estimate=plan.damage,tower_shots=plan.tower_shots,incoming_estimate=plan.incoming});
end;
local function dropTarget(bot,tower)
    return Risk.DeaggroTarget(bot,tower);
end;
local function protected(bot,s)
    if not U.CanUse(bot) or not B.Free(s) or Raze.Pending(bot) then return true end;
    if s.raze_facing and U.Now()-s.raze_facing.at<.2 then return true end;
    local observer=O.State(bot);
    return observer and observer.ability_order_at and U.Now()-observer.ability_order_at<.25;
end;
local function move(bot,s,phase,goal,reason)
    if not goal or U.Now()<(phase.next_move or -math.huge) then return end;
    if phase.last_goal and U.Distance(phase.last_goal,goal)<80 and U.Call(bot,"GetCurrentActionType")==BOT_ACTION_TYPE_MOVE_TO
        and U.Now()-phase.last_progress<C.stuck_s then return end;
    phase.next_move=U.Now()+C.move_interval_s;phase.last_goal=goal;
    B.Fire(bot,s,"tower_pressure_move",nil,reason,function() return bot:Action_MoveToLocation(U.Vector(goal)) end,false);
end;
function M.Think(bot)
    if not enabled(bot) then return end;
    local s=state(bot);local plan=M.Decide(bot);if not plan then return end;
    if not s.pressure then M.Start(bot) end;
    local phase=s.pressure;if not phase or protected(bot,s) then return end;
    local p=U.Pos(bot);if not p then return end;
    local focus=U.Call(phase.tower,"GetAttackTarget");
    if not phase.focus_seen or phase.last_focus~=focus then
        phase.focus_seen=true;phase.last_focus=focus;
        B.Emit(s,"tower_focus_observed",{on_self=focus==bot,target=U.Call(focus,"GetUnitName") or "unknown",
            current_hp=U.Call(bot,"GetHealth"),airborne_tower_shots=phase.plan.airborne_tower_shots});
    end;
    if U.Distance(p,phase.last_position)>=C.progress_distance then phase.last_position=p;phase.last_progress=U.Now() end;
    if phase.exiting then move(bot,s,phase,phase.exit,"leave_tower_budget");return end;
    if phase.drop then
        local target=U.Call(phase.tower,"GetAttackTarget");
        if target~=bot and U.Visible(target) and U.Call(target,"GetTeam")==U.Call(bot,"GetTeam") then
            B.Emit(s,"tower_deaggro_readback",{confirmed=true});phase.drop=nil;
        elseif U.Now()-phase.drop.at>=C.deaggro_readback_s then
            B.Emit(s,"tower_deaggro_readback",{confirmed=false});phase.drop=nil;beginExit(bot,s,"deaggro_not_confirmed");return;
        else return end;
    end;
    if U.Call(phase.tower,"GetAttackTarget")==bot then
        local ally=dropTarget(bot,phase.tower);
        if ally and U.Now()>=(s.next_deaggro or -math.huge) then
            s.next_deaggro=U.Now()+C.deaggro_interval_s;phase.drop={at=U.Now(),target=ally};
            B.Fire(bot,s,"tower_deaggro_attempt",nil,"attack_closer_allied_creep",function() return bot:Action_AttackUnit(ally,true) end,false);
            return;
        elseif not phase.plan.lethal then beginExit(bot,s,"focused_without_deaggro");return end;
    end;
    local range=U.Call(bot,"GetAttackRange");
    if not U.Number(range) then beginExit(bot,s,"attack_range_unknown");return end;
    local nearRaze=U.Call(bot,"GetAbilityByName","nevermore_shadowraze1");
    local needClose=U.Ready(nearRaze) and U.Distance(p,U.Pos(phase.target))>390;
    if U.Distance(p,U.Pos(phase.target))<=range and not needClose then
        if U.Call(bot,"GetCurrentActionType")==BOT_ACTION_TYPE_ATTACK then return end;
        B.Fire(bot,s,"tower_pressure_attack",nil,"bounded_hero_pressure",function() return bot:Action_AttackUnit(phase.target,false) end,false);
    elseif U.Now()-phase.last_progress>=C.stuck_s then beginExit(bot,s,"approach_no_progress")
    else move(bot,s,phase,phase.plan.goal,"approach_short_raze") end;
end;
function M.Raze(bot)
    local s=enabled(bot) and state(bot);local phase=s and s.pressure;
    if not phase or phase.exiting or phase.drop or not U.CanUse(bot) then return end;
    local target=phase.target;if not U.Enemy(bot,target) then return end;
    local safe,reason=Risk.Evaluate(bot,target,phase.tower,phase.was_covered);
    if not safe then beginExit(bot,s,reason);return end;
    for i=1,3 do local a=U.Call(bot,"GetAbilityByName","nevermore_shadowraze"..i);
        local range,radius,cast=U.Special(a,{"shadowraze_range"}),U.Special(a,{"shadowraze_radius"}),U.Call(a,"GetCastPoint");
        local aim=U.Number(cast) and U.Point(U.Call(target,"GetExtrapolatedLocation",cast));
        if U.Ready(a) and range and radius and aim and math.abs(U.Distance(U.Pos(bot),aim)-range)<=radius-40 then
            return .85,aim,a;
        end;
    end;
end;
function M.AllowStep(bot,step,tower)
    local s=enabled(bot) and state(bot);local phase=s and s.pressure;
    if not s or not step then return false end;
    if phase and (phase.exiting or phase.drop or phase.tower~=tower) then return false end;
    local target=phase and phase.target or U.Call(bot,"GetTarget");
    if tower~=Risk.Tower(bot) then return false end;
    local plan=Risk.Evaluate(bot,target,tower,phase and phase.was_covered);
    return plan~=nil and U.Distance(U.Point(step),plan.goal)<=500;
end;
return M;
