-- Протокол исполнения plans, без вызовов Dota Action_*. Реальный executor -- интеграция T016.
local M = {};
function M.New() return { active = nil, leases = {}, next_execution = 0 } end;
function M.Claim( self, actor, owner, plan_id, now, ttl )
    local lease = self.leases[actor];
    if lease and lease.until_s > now and lease.owner ~= owner then return false, "actor_already_owned" end;
    self.leases[actor] = { owner = owner, plan_id = plan_id, until_s = now + ttl };
    return true;
end
function M.Begin( self, actor, owner, plan, now, cfg, capabilities )
    if self.active then return false, "plan_already_active" end;
    if not plan.available then return false, "masked_plan" end;
    for _, step in ipairs( plan.steps ) do
        if step.kind == "raze" and not capabilities.joint_executor then return false, "joint_executor_not_integrated" end;
    end
    -- candidate_key стабилен для ML; execution_id уникален для каждой попытки.
    -- Иначе запоздалый release прошлого исполнения мог бы продвинуть новый план.
    self.next_execution = self.next_execution + 1;
    local id = tostring( actor ) .. ":" .. tostring( self.next_execution ) .. ":" .. ( plan.candidate_key or plan.option_key );
    local ok, err = M.Claim( self, actor, owner, id, now, cfg.max_plan_horizon_s );
    if not ok then return false, err end;
    self.active = { actor = actor, owner = owner, plan = plan, execution_id = id, step = 1, started_at = now, step_ready_at = now,
        snapshot_time = now, deadline = now + cfg.max_plan_horizon_s, phase = "ready" };
    return true;
end
function M.Abort( self, reason )
    if self.active then self.leases[self.active.actor] = nil end;
    self.active = nil;
    return { status = "aborted", reason = reason, replan = true };
end
function M.Next( self, observation, cfg )
    local a = self.active;
    if not a then return { status = "idle" } end;
    if observation.emergency then return M.Abort( self, "emergency" ) end;
    if observation.time > a.deadline then return M.Abort( self, "deadline" ) end;
    if observation.time - observation.snapshot_time > cfg.max_snapshot_age_s then return M.Abort( self, "stale_snapshot" ) end;
    local lease = self.leases[a.actor];
    if not lease or lease.until_s <= observation.time or lease.owner ~= a.owner
        or lease.plan_id ~= a.execution_id then return M.Abort( self, "lease_lost" ) end;
    if a.phase ~= "ready" then return { status = "waiting_event", phase = a.phase } end;
    a.last_observation_at = observation.time;
    local step = a.plan.steps[a.step];
    if not step then
        self.leases[a.actor], self.active = nil, nil;
        return { status = "plan_finished", outcome = "not_attributed" };
    end
    if step.kind == "observe" and observation.time < a.step_ready_at + ( step.duration_s or 0 ) then
        return { status = "waiting_window", until_s = a.step_ready_at + step.duration_s };
    end
    if step.target_id and not ( observation.valid_targets or {} )[step.target_id] then return M.Abort( self, "target_invalid" ) end;
    if observation.casting or observation.attack_windup then return { status = "waiting_current_action" } end;
    if step.kind == "raze" then
        if not ( observation.ability_ready or {} )[step.ability_id] then return M.Abort( self, "cooldown_or_mana_changed" ) end;
        if not observation.facing_ready then return { status = "need_face_then_reobserve", step = step } end;
        if not observation.geometry_valid then return M.Abort( self, "geometry_changed" ) end;
    end
    a.phase = "submitted";
    return { status = "submit", step = step, step_id = a.step, plan_id = a.execution_id };
end
function M.Event( self, event )
    local a = self.active;
    if not a or event.step_id ~= a.step or event.actor ~= a.actor
        or event.plan_id ~= a.execution_id then return false, "unmatched_event" end;
    if event.status == "cancelled" or event.status == "rejected" then return M.Abort( self, event.status ) end;
    if a.phase ~= "submitted" then return false, "no_submission" end;
    local step = a.plan.steps[a.step];
    local expected = step.kind == "attack" and "attack_released" or ( step.kind == "raze" and "cast_completed" or "observed" );
    if event.status ~= expected then return false, "not_a_release_confirmation" end;
    a.step, a.phase, a.step_ready_at = a.step + 1, "ready", a.last_observation_at;
    return true;
end
return M;
