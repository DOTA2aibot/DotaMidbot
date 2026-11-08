-- Один require-path в обоих callbacks. Никаких допущений о shared Lua VM:
-- без видимых heartbeat/ACK в этом же состоянии приказов не будет.
local A = require( GetScriptDirectory() .. "/laning/runtime/api" );
local C = require( GetScriptDirectory() .. "/laning/runtime/config" );
local Profile = require( GetScriptDirectory() .. "/laning/profile" );
local M, actors, calls, serial = {}, {}, {}, 0;
function M.Actor( bot )
    local id, team = A.Call( bot, "GetPlayerID" ), A.Call( bot, "GetTeam" );
    if id == nil or team == nil then return nil end;
    return tostring( team ) .. ":" .. tostring( id );
end
function M.LanePulse( bot, now )
    if Profile.runtime_enabled ~= true then M.Release( bot ); return nil end;
    local actor = M.Actor( bot ); if not actor or not A.Number( now ) then return nil end;
    local s = actors[actor];
    if not s or now < s.lane_at then serial = serial + 1; s = { nonce = actor .. ":channel:" .. serial, lane_at = now }; actors[actor] = s end;
    s.lane_at = now;
    if s.lease and s.lease.until_s > now then s.lease.until_s = now + C.owner_ttl_s end;
    return s.nonce;
end
function M.ChannelReady( bot, now )
    if Profile.runtime_enabled ~= true then return false end;
    if not A.Number( now ) then return false end;
    local s = actors[M.Actor( bot )];
    return s ~= nil and s.ability_nonce == s.nonce and s.ability_at ~= nil
        and now >= s.ability_at and now - s.ability_at <= C.owner_ttl_s;
end
function M.AbilityGate( bot )
    if Profile.runtime_enabled ~= true then M.Release( bot ); return false end;
    local now, actor = A.Time(), M.Actor( bot );
    if now and actor then
        local c = calls[actor] or { count = 0 }; calls[actor] = c;
        c.count, c.at = c.count + 1, now; -- видим вызов даже при ещё неготовом heartbeat
    end;
    local s = actor and actors[actor];
    if not now or not s or now < s.lane_at or now - s.lane_at > C.owner_ttl_s then return false end;
    s.ability_at, s.ability_nonce = now, s.nonce;
    if not s.lease or s.lease.until_s <= now then s.lease = nil; return false end;
    if A.Call( bot, "IsAlive" ) ~= true or ( BOT_MODE_RETREAT ~= nil and A.Call( bot, "GetActiveMode" ) == BOT_MODE_RETREAT ) then
        s.lease = nil; return false;
    end
    s.lease.ack = s.lease.token;
    return true; -- подготовка/исполнение плана: самостоятельный каст Kimi уступает управление
end
function M.Diagnostics( bot, now )
    local actor = M.Actor( bot ); local s, c = actors[actor], calls[actor];
    local ready = M.ChannelReady( bot, now );
    local function age( at ) return A.Number( now ) and A.Number( at ) and now >= at and now - at or nil end;
    local lease = s and s.lease;
    return { channel_ready = ready, owner_ttl_s = C.owner_ttl_s,
        controller_profile = Profile.name, runtime_enabled = Profile.runtime_enabled == true,
        lane_age_s = s and age( s.lane_at ), ability_seen_age_s = c and age( c.at ),
        ability_accepted_age_s = s and age( s.ability_at ), ability_calls = c and c.count or 0,
        channel_reason = ready and "ready" or ( not c and "ability_callback_not_seen"
            or ( not s and "lane_callback_not_seen" or "heartbeat_not_fresh" ) ),
        lease_state = not lease and "none" or ( lease.until_s <= now and "expired"
            or ( lease.ack == lease.token and "acked" or "awaiting_plan_ack" ) ),
        lease_remaining_s = lease and math.max( 0, lease.until_s - now ) or nil };
end
function M.Acquire( bot, key, now )
    if Profile.runtime_enabled ~= true then return false, "runtime_profile_disabled" end;
    local s = actors[M.Actor( bot )];
    if not M.ChannelReady( bot, now ) then return false, "ability_hook_not_observed" end;
    if s.lease and s.lease.until_s <= now then s.lease = nil end;
    if s.lease and s.lease.key ~= key then return false, "different_plan_owns_actor" end;
    if not s.lease then
        serial = serial + 1;
        s.lease = { key = key, token = s.nonce .. ":plan:" .. serial, until_s = now + C.owner_ttl_s };
    end
    if s.lease.ack ~= s.lease.token then return false, "awaiting_ability_plan_ack" end;
    s.lease.until_s = now + C.owner_ttl_s;
    return true, s.lease.token;
end
function M.Owns( bot, token, now )
    local s = actors[M.Actor( bot )];
    return M.ChannelReady( bot, now ) and s.lease ~= nil and s.lease.until_s > now
        and s.lease.token == token and s.lease.ack == token;
end
function M.Release( bot, token )
    local s = actors[M.Actor( bot )];
    if s and s.lease and ( token == nil or s.lease.token == token ) then s.lease = nil end;
end
return M;
