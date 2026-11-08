-- Вызывается mode_laning: collector работает и при observe/нулевом desire.
local A = require( GetScriptDirectory() .. "/laning/runtime/api" );
local C = require( GetScriptDirectory() .. "/laning/runtime/config" );
local Backend = require( GetScriptDirectory() .. "/laning/runtime/backend" );
local Guard = require( GetScriptDirectory() .. "/laning/runtime/guard" );
local Bridge = require( GetScriptDirectory() .. "/laning/advanced/bridge" );
local Planner = require( GetScriptDirectory() .. "/laning/advanced/planner" );
local PolicyConfig = require( GetScriptDirectory() .. "/laning/advanced/config" );
local M, actors = {}, {};
local function ensure( bot )
    local key, now = Guard.Actor( bot ), A.Time();
    if not key or not now then return nil end;
    if C.operation ~= "observe" and C.operation ~= "execute" and C.operation ~= "probe_attack" and C.operation ~= "probe_raze" and C.operation ~= "lane_probe" then
        print( "[MIDBOT runtime] invalid_operation: " .. tostring( C.operation ) ); return nil;
    end;
    if C.stage ~= "attacks" and C.stage ~= "raze" and C.stage ~= "combos" then return nil end;
    local ctx = actors[key];
    if ctx and now < ctx.last_time then Bridge.Unregister( bot, "clock_reset" ); actors[key], ctx = nil, nil end;
    if not ctx then ctx = { backend = Backend.New( C ), next_poll = -math.huge, next_error = -math.huge,
        driver = { desire_calls = 0, think_calls = 0, leave_calls = 0 } }; actors[key] = ctx end;
    ctx.driver.desire_calls = ctx.driver.desire_calls + 1;
    ctx.backend.driver = ctx.driver;
    ctx.last_time = now;
    if ctx.snapshot and ctx.snapshot.integration.channel_ready ~= Guard.ChannelReady( bot, now ) then ctx.next_poll = -math.huge end;
    if ctx.snapshot and ctx.snapshot.hero.active_mode ~= A.Call( bot, "GetActiveMode" ) then ctx.next_poll = -math.huge end;
    if now >= ctx.next_poll then
        local ok, snapshot = pcall( ctx.backend.Snapshot, bot );
        ctx.snapshot = ok and snapshot or nil; ctx.next_poll = now + C.collect_interval_s;
        if ctx.snapshot then
            ctx.snapshot.driver = ctx.driver;
            ctx.planning = ctx.backend.Filter( bot, ctx.snapshot, Planner.Build( ctx.snapshot, PolicyConfig ) );
        elseif now >= ctx.next_error then
            print( "[MIDBOT runtime] collector_unavailable: " .. tostring( not ok and snapshot or ctx.backend.snapshot_error or "api_failure" ) );
            ctx.next_error = now + C.log_interval_s;
        end
    end
    return ctx;
end
function M.Desire( bot )
    local ctx = ensure( bot ); if not ctx then return 0 end;
    local s, backend, now = ctx.snapshot, ctx.backend, A.Time();
    local reason = not s and "snapshot_missing" or ( C.operation == "observe" and "observe_has_no_orders"
        or ( s.danger and "safety_yield" or ( s.time < 0 and "pregame" or ( s.time > 600 and "lane_window_ended"
            or ( not Guard.ChannelReady( bot, now ) and "ability_heartbeat_not_ready" or nil ) ) ) ) );
    if ( not reason or reason == "ability_heartbeat_not_ready" ) and C.operation == "lane_probe" and not backend.lane_probe_safe then reason = "lane_probe_unsafe" end;
    if reason then
        Bridge.Cancel( bot, reason ); backend.Release( bot, reason );
        if s then backend.Record( s, ctx.planning, { status = C.operation == "observe" and "observed_no_orders" or "runtime_yield", reason = reason } ) end;
        -- В диагностическом lane probe держим выбор lane mode даже в паузе
        -- heartbeat. Это НЕ владение приказами: Think ниже ждёт свежий канал/ACK.
        if C.operation == "lane_probe" and reason == "ability_heartbeat_not_ready" then
            return BOT_MODE_DESIRE_HIGH or BOT_MODE_DESIRE_MODERATE;
        end;
        return 0;
    end
    if not Bridge.IsReady( bot:GetPlayerID() ) then
        -- Это результат реального двустороннего heartbeat в общем состоянии, не конфигурационный флаг.
        backend.joint_executor_verified = true;
        local ok, err = Bridge.Register( bot:GetPlayerID(), backend );
        if not ok then backend.Record( s, ctx.planning, { status = "runtime_yield", reason = err } ); return 0 end;
    end
    local desire = C.operation == "lane_probe" and ( BOT_MODE_DESIRE_HIGH or BOT_MODE_DESIRE_MODERATE ) or BOT_MODE_DESIRE_MODERATE;
    if Bridge.IsActive( bot:GetPlayerID() ) then
        backend.Record( s, ctx.planning, { status = "lane_plan_active" } ); return desire;
    end;
    local selected = ctx.planning and ctx.planning.selected;
    if not selected or not selected.available or #selected.steps == 0 or s.hero.casting then
        backend.Release( bot, "no_available_action" );
        backend.Record( s, ctx.planning, { status = "no_available_action",
            reason = s.hero.casting and "current_action_busy" or ( selected and selected.mask_reason or "no_executable_steps" ) } );
        if C.operation == "lane_probe" then return desire end; -- держим lane mode, не отдаём героя рунам между пробами
        return 0;
    end
    backend.Record( s, ctx.planning, { status = "lane_action_available" } );
    return desire;
end
function M.Think( bot )
    if M.Desire( bot ) <= 0 then return { status = "runtime_yield" } end;
    local ctx = actors[Guard.Actor( bot )]; ctx.driver.think_calls = ctx.driver.think_calls + 1;
    if not Guard.ChannelReady( bot, A.Time() ) then
        local result = { status = "waiting_owner", reason = "ability_heartbeat_not_ready" };
        ctx.backend.Record( ctx.snapshot, ctx.planning, result ); return result;
    end;
    local result = Bridge.Think( bot );
    -- Bridge может вернуть waiting_owner без собственного Record. Это важно для диагностики ACK.
    if result.status == "waiting_owner" or result.status == "no_executable_plan" then
        ctx.backend.Record( ctx.backend.snapshot or ctx.snapshot, ctx.planning, result );
    end;
    return result;
end
function M.Leave( bot )
    Bridge.Cancel( bot, "lane_mode_ended" );
    local ctx = actors[Guard.Actor( bot )];
    if ctx then
        ctx.driver.leave_calls = ctx.driver.leave_calls + 1;
        ctx.backend.Release( bot, "lane_mode_ended" );
        if ctx.snapshot then ctx.backend.Record( ctx.snapshot, ctx.planning, { status = "lane_mode_ended" } ) end;
    end;
end
return M;
