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
    if C.operation ~= "observe" and C.operation ~= "execute" and C.operation ~= "probe_attack" and C.operation ~= "probe_raze" then return nil end;
    if C.stage ~= "attacks" and C.stage ~= "raze" and C.stage ~= "combos" then return nil end;
    local ctx = actors[key];
    if ctx and now < ctx.last_time then Bridge.Unregister( bot, "clock_reset" ); actors[key], ctx = nil, nil end;
    if not ctx then ctx = { backend = Backend.New( C ), next_poll = -math.huge, next_error = -math.huge }; actors[key] = ctx end;
    ctx.last_time = now;
    if ctx.snapshot and ctx.snapshot.integration.channel_ready ~= Guard.ChannelReady( bot, now ) then ctx.next_poll = -math.huge end;
    if now >= ctx.next_poll then
        local ok, snapshot = pcall( ctx.backend.Snapshot, bot );
        ctx.snapshot = ok and snapshot or nil; ctx.next_poll = now + C.collect_interval_s;
        if ctx.snapshot then
            ctx.planning = ctx.backend.Filter( bot, ctx.snapshot, Planner.Build( ctx.snapshot, PolicyConfig ) );
            ctx.backend.Record( ctx.snapshot, ctx.planning, { status = C.operation == "observe" and "observed_no_orders"
                or ( Guard.ChannelReady( bot, now ) and "channel_observed" or "awaiting_ability_hook" ) } );
        elseif now >= ctx.next_error then
            print( "[MIDBOT runtime] collector_unavailable: " .. tostring( ctx.backend.snapshot_error or "api_failure" ) );
            ctx.next_error = now + C.log_interval_s;
        end
    end
    return ctx;
end
function M.Desire( bot )
    local ctx = ensure( bot ); if not ctx then return 0 end;
    local s, backend, now = ctx.snapshot, ctx.backend, A.Time();
    if not s or s.danger or s.time < 0 or s.time > 600 or C.operation == "observe" or not Guard.ChannelReady( bot, now ) then
        Bridge.Cancel( bot, "runtime_yield" ); backend.Release( bot, "runtime_yield" ); return 0;
    end
    if not Bridge.IsReady( bot:GetPlayerID() ) then
        -- Это результат реального двустороннего heartbeat в общем состоянии, не конфигурационный флаг.
        backend.joint_executor_verified = true;
        local ok = Bridge.Register( bot:GetPlayerID(), backend ); if not ok then return 0 end;
    end
    if Bridge.IsActive( bot:GetPlayerID() ) then return BOT_MODE_DESIRE_MODERATE end;
    local selected = ctx.planning and ctx.planning.selected;
    if not selected or not selected.available or #selected.steps == 0 or s.hero.casting then
        backend.Release( bot, "no_available_action" ); return 0;
    end
    return BOT_MODE_DESIRE_MODERATE;
end
function M.Think( bot )
    if M.Desire( bot ) <= 0 then return { status = "runtime_yield" } end;
    return Bridge.Think( bot );
end
function M.Leave( bot )
    Bridge.Cancel( bot, "lane_mode_ended" );
    local ctx = actors[Guard.Actor( bot )]; if ctx then ctx.backend.Release( bot, "lane_mode_ended" ) end;
end
return M;
