-- Изолированный cosmetic hook. Единственный игровой вызов — all-chat.
local C = require( GetScriptDirectory() .. "/laning/social/kill_chat_config" );
local M, states = {}, {};
local function number( n ) return type( n ) == "number" and n == n and math.abs( n ) < math.huge end;
local function integer( n ) return number( n ) and n >= 0 and n % 1 == 0 end;
local function call( object, method, ... )
    local args = { ... };
    local ok, value = pcall( function() return object[method]( object, unpack( args ) ) end );
    if ok then return value end;
end;
local function global( name, ... )
    local fn = _G[name]; if type( fn ) ~= "function" then return nil end;
    local ok, value = pcall( fn, ... ); if ok then return value end;
end;
local function report( status, kill )
    pcall( print, "[MIDBOT kill-chat] version=" .. C.version .. " status=" .. status
        .. " kill_number=" .. tostring( kill ) .. " delivery=unknown" );
end;
local function baseline( previous, kills, game, real )
    return { kills = kills, game = game, real = real, queue = {}, next_poll = real + C.poll_interval_s,
        next_send = previous and real >= previous.real and math.max( real, previous.next_send ) or real };
end;
function M.Tick( bot )
    if C.enabled ~= true then states = {}; return end;
    if call( bot, "GetUnitName" ) ~= "npc_dota_hero_nevermore"
        or call( bot, "IsHero" ) ~= true or call( bot, "IsIllusion" ) ~= false then return end;
    local id = call( bot, "GetPlayerID" );
    if not integer( id ) or global( "IsPlayerBot", id ) ~= true then return end;
    local game, real = global( "DotaTime" ), global( "RealTime" );
    if not number( game ) or not number( real ) then return end;
    local s = states[id];
    if s and real >= s.real and game >= s.game and real < s.next_poll then return end;
    local kills = global( "GetHeroKills", id ); if not integer( kills ) then return end;
    if not s or game < 0 or game < s.game or real < s.real or kills < s.kills
        or game - s.game > C.freshness_gap_s or call( bot, "IsAlive" ) ~= true then
        states[id] = baseline( s, kills, game, real ); return;
    end;
    s.game, s.real, s.next_poll = game, real, real + C.poll_interval_s;
    local count = math.min( kills - s.kills, C.max_pending );
    for offset = 1, count do
        local kill = kills - count + offset;
        if #s.queue >= C.max_pending then table.remove( s.queue, 1 ) end;
        s.queue[#s.queue + 1] = { kill = kill, at = real };
    end;
    s.kills = kills; -- cursor до side effect: одна попытка даже при ошибке после отправки
    while s.queue[1] and real - s.queue[1].at > C.event_ttl_s do table.remove( s.queue, 1 ) end;
    if not s.queue[1] or real < s.next_send then return end;
    local event = table.remove( s.queue, 1 );
    s.next_send = real + C.chat_interval_s;
    local ok = pcall( function() bot:ActionImmediate_Chat( C.message, true ) end );
    report( ok and "chat_call_returned" or "chat_call_failed_no_retry", event.kill );
end;
return M;
