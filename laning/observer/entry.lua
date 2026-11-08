local A = require( GetScriptDirectory() .. "/laning/runtime/api" );
local O = require( GetScriptDirectory() .. "/laning/observer/core" );
local C = require( GetScriptDirectory() .. "/laning/observer/config" );
local Profile = require( GetScriptDirectory() .. "/laning/profile" );
local Shadow = require( GetScriptDirectory() .. "/laning/hybrid/shadow" );
local Wards = require( GetScriptDirectory() .. "/laning/hybrid/wards" );
local KillChat;
do
    local ok, helper = pcall( require, GetScriptDirectory() .. "/laning/social/kill_chat" );
    if ok then KillChat = helper end;
end;
local M = {};
function M.Tick( bot )
    -- Отдельный cosmetic dispatch; core Capture/Shadow остаются read-only.
    if KillChat and Profile.runtime_enabled ~= true then pcall( KillChat.Tick, bot ) end;
    if Profile.observer_enabled ~= true then return end;
    local s = O.State( bot ); local now = A.Time();
    if not s then return end;
    O.PollCasts( bot, s );
    O.PollAttacks( bot, s );
    if Profile.wards_enabled == true then Wards.Poll( bot, s ) end; -- подтверждение даже при using/retreat
    if now < s.next_sample then return end;
    s.next_sample = now + C.interval_s;
    local ok, snapshot = pcall( O.Capture, bot, s );
    if not ok or not snapshot then
        if now >= s.next_error then O.Emit( s, "capture_unavailable", { reason = "optional_api_or_capture_failure" } ); s.next_error = now + C.failure_interval_s end;
        return;
    end;
    local h = snapshot.hero;
    local delta = { attribution = "interval_only_not_action_credit" };
    for _, key in ipairs( { "last_hits", "denies", "deaths", "kills" } ) do
        if s.previous and A.Number( h[key] ) and A.Number( s.previous[key] ) then
            delta[key] = h[key] >= s.previous[key] and h[key] - s.previous[key] or nil;
        end;
    end;
    snapshot.deltas = delta; s.previous = h;
    O.Emit( s, "snapshot", snapshot );
    local snapshot_seq = s.sequence;
    if C.shadow_enabled then
        local success, decision = pcall( Shadow.Decide, bot, snapshot, s.handles );
        if success then decision.based_on_snapshot_seq = snapshot_seq; O.Emit( s, "shadow_decision", decision )
        else O.Emit( s, "shadow_unavailable", { reason = "selector_failed_no_orders" } ) end;
        local ready, plan, reason = pcall( Wards.Plan, bot, s );
        if ready then O.Emit( s, "ward_suggestion", { executed = false, available = plan ~= nil,
            reason = reason or "in_range_mid_highground", location = plan and plan.location,
            item_kind = plan and plan.kind, slot = plan and plan.slot, option_id = 15 } ) end;
    end;
end
function M.Action( ... )
    if Profile.observer_enabled == true then return O.Action( ... ) end;
end
function M.BeforeAction( ... )
    if Profile.observer_enabled == true then return O.BeforeAction( ... ) end;
end
function M.AfterAbilities( bot )
    if Profile.wards_enabled ~= true or Profile.observer_enabled ~= true then return end;
    local s = O.State( bot ); if s then Wards.Tick( bot, s ) end;
end
return M;
