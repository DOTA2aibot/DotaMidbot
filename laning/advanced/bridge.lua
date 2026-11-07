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
function M.Desire( bot )
    local a = actors[bot:GetPlayerID()];
    if not a then return 0 end;
    local s = a.backend.Snapshot( bot );
    if not s or s.danger or s.hero.disabled or s.hero.casting or s.time < 0 or s.time > 600 then return 0 end;
    return BOT_MODE_DESIRE_MODERATE;
end
function M.Think( bot )
    local a = actors[bot:GetPlayerID()];
    if not a then return { status = "awaiting_T016_backend" } end;
    local backend, scheduler = a.backend, a.scheduler;
    local s = backend.Snapshot( bot );
    if not s then return Scheduler.Abort( scheduler, "snapshot_missing" ) end;
    s.capabilities = s.capabilities or {};
    s.capabilities.joint_executor = backend.joint_executor_verified;
    for _, event in ipairs( backend.Events( bot ) ) do Scheduler.Event( scheduler, event ) end;
    if s.danger then return Scheduler.Abort( scheduler, "emergency" ) end;
    if not scheduler.active then
        if s.time < a.next_plan_at then return { status = "decision_interval" } end;
        a.next_plan_at = s.time + 0.15;
        a.planning = Planner.Build( s, C );
        local selected = a.planning.selected;
        record( backend, s, a.planning, { status = "selected_not_executed" } );
        if not selected or not selected.available or #selected.steps == 0 then return { status = "no_executable_plan" } end;
        local ok, err = Scheduler.Begin( scheduler, bot:GetPlayerID(), "joint", selected, s.time, C, s.capabilities );
        if not ok then return { status = "rejected", reason = err } end;
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
            if not ok then order = Scheduler.Abort( scheduler, reason or "backend_rejected" ) end;
        end
    end
    record( backend, s, a.planning, order );
    return order;
end
return M;
