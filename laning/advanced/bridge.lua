-- Единственная точка связи T007 с backend T016. Без регистрации backend приказы не выдаются.
local Planner = require( GetScriptDirectory() .. "/laning/advanced/planner" );
local Scheduler = require( GetScriptDirectory() .. "/laning/advanced/scheduler" );
local C = require( GetScriptDirectory() .. "/laning/advanced/config" );
local M = {};
local actors = {};
local function record( backend, snapshot, planning, event )
    local ok = pcall( backend.Record, snapshot, planning, event );
    if not ok then print( "[MIDBOT options] diagnostic record failed; gameplay state retained" ) end;
end
function M.Register( actor_id, backend )
    if backend.schema ~= C.schema or not backend.joint_executor_verified then return false, "integration_probe_required" end;
    for _, method in ipairs( { "Snapshot", "Validate", "Submit", "Events", "Record" } ) do
        if type( backend[method] ) ~= "function" then return false, "backend_missing:" .. method end;
    end
    if actors[actor_id] then return false, "actor_backend_already_registered" end;
    actors[actor_id] = { backend = backend, scheduler = Scheduler.New(), next_plan_at = -math.huge };
    return true;
end
function M.IsReady( actor_id ) return actors[actor_id] ~= nil end;
function M.IsActive( actor_id ) return actors[actor_id] ~= nil and actors[actor_id].scheduler.active ~= nil end;
function M.HasActivePlan( actor_id ) return M.IsActive( actor_id ) end; -- статус для T016; не заменяет per-plan ACK
function M.Unregister( bot, reason ) M.Cancel( bot, reason ); actors[bot:GetPlayerID()] = nil end;
function M.Cancel( bot, reason )
    local a = actors[bot:GetPlayerID()]; if not a then return { status = "idle" } end;
    local result = Scheduler.Abort( a.scheduler, reason );
    if a.backend.Release then a.backend.Release( bot, reason ) end;
    return result;
end
function M.Desire( bot )
    local a = actors[bot:GetPlayerID()];
    if not a then return 0 end;
    local s = a.backend.Snapshot( bot );
    if not s or s.danger or s.hero.disabled or s.time < 0 or s.time > 600 then M.Cancel( bot, "yield" ); return 0 end;
    -- Свой cast внутри плана не должен терять lane ownership на время ожидания completion.
    if s.hero.casting and not a.scheduler.active then return 0 end;
    return BOT_MODE_DESIRE_MODERATE;
end
function M.Think( bot )
    local a = actors[bot:GetPlayerID()];
    if not a then return { status = "awaiting_T016_backend" } end;
    local backend, scheduler = a.backend, a.scheduler;
    local s = backend.Snapshot( bot );
    if not s then return M.Cancel( bot, "snapshot_missing" ) end;
    s.capabilities = s.capabilities or {};
    s.capabilities.joint_executor = backend.joint_executor_verified;
    for _, event in ipairs( backend.Events( bot ) ) do
        local accepted = Scheduler.Event( scheduler, event );
        if accepted then record( backend, s, a.planning, event ) end;
        if type( accepted ) == "table" and accepted.status == "aborted" then
            if backend.Release then backend.Release( bot, event.status ) end;
            return accepted;
        end
    end
    if s.danger then return M.Cancel( bot, "emergency" ) end;
    if not scheduler.active then
        if s.time < a.next_plan_at then return { status = "decision_interval" } end;
        a.next_plan_at = s.time + 0.15;
        a.planning = Planner.Build( s, C );
        if backend.Filter then a.planning = backend.Filter( bot, s, a.planning ) end;
        local selected = a.planning.selected;
        record( backend, s, a.planning, { status = "selected_not_executed" } );
        if not selected or not selected.available or #selected.steps == 0 then
            if backend.Release then backend.Release( bot, "no_executable_plan" ) end;
            return { status = "no_executable_plan" };
        end;
        if backend.Acquire then
            local owned, reason = backend.Acquire( bot, selected );
            if not owned then return { status = "waiting_owner", reason = reason } end;
        end
        local ok, err = Scheduler.Begin( scheduler, bot:GetPlayerID(), "joint", selected, s.time, C, s.capabilities );
        if not ok then if backend.Release then backend.Release( bot, err ) end; return { status = "rejected", reason = err } end;
    end
    local active = scheduler.active;
    local step = active and active.plan.steps[active.step] or nil;
    local observation = backend.Validate( bot, step, s );
    local order = Scheduler.Next( scheduler, observation, C );
    if order.status == "submit" then
        if order.step.kind == "observe" then
            Scheduler.Event( scheduler, { actor = bot:GetPlayerID(), plan_id = order.plan_id,
                step_id = order.step_id, status = "observed" } );
        else
            local ok, reason = backend.Submit( bot, order );
            if not ok then order = M.Cancel( bot, reason or "backend_rejected" ) end;
        end
    elseif order.status == "need_face_then_reobserve" and backend.Prepare then
        local ok, reason = backend.Prepare( bot, order.step );
        if not ok then order = M.Cancel( bot, reason or "face_preparation_rejected" ) end;
    end
    if ( order.status == "aborted" or order.status == "plan_finished" ) and backend.Release then backend.Release( bot, order.status ) end;
    record( backend, s, a.planning, order );
    return order;
end
return M;
