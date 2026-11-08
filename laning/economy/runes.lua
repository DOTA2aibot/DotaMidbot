-- Только rune mode SF. Другие режимы и обычные атаки остаются Valve.
local A = require( GetScriptDirectory() .. "/laning/runtime/api" );
local C = require( GetScriptDirectory() .. "/laning/economy/config" );
local Profile = require( GetScriptDirectory() .. "/laning/profile" );
local O = require( GetScriptDirectory() .. "/laning/observer/core" );
local M, states = {}, setmetatable( {}, { __mode = "k" } );
local function global( name, ... ) return O.Global( name, ... ) end;
function M.Decide( bot )
    local now = A.Time();
    if Profile.economy_enabled ~= true then return nil, "profile_disabled" end;
    if not now or now < 0 or now > C.rune_window_end then return nil, "outside_rune_window" end;
    if A.Call( bot, "IsAlive" ) ~= true then return nil, "not_alive" end;
    for _, method in ipairs( { "IsUsingAbility", "IsChanneling", "IsStunned", "IsHexed" } ) do
        if A.Call( bot, method ) ~= false then return nil, "busy_or_unknown" end;
    end;
    local mode = A.Call( bot, "GetActiveMode" );
    if mode == nil or BOT_MODE_RETREAT == nil or BOT_MODE_ATTACK == nil then return nil, "mode_unknown" end;
    if mode == BOT_MODE_RETREAT or mode == BOT_MODE_ATTACK then return nil, "combat_or_retreat" end;
    local action = A.Call( bot, "GetCurrentActionType" );
    if action == nil or ( BOT_ACTION_TYPE_ATTACK ~= nil and action == BOT_ACTION_TYPE_ATTACK ) then return nil, "attack_or_action_unknown" end;
    local hp, maxhp = A.Call( bot, "GetHealth" ), A.Call( bot, "GetMaxHealth" );
    if not A.Number( hp ) or not A.Number( maxhp ) or maxhp <= 0 or hp / maxhp < C.rune_min_hp then return nil, "health_or_unknown" end;
    local creeps = A.Call( bot, "GetNearbyLaneCreeps", C.lane_radius, true );
    if type( creeps ) ~= "table" then return nil, "lane_unknown" end;
    for _, creep in ipairs( creeps ) do
        if A.Visible( creep ) then return nil, "lane_creeps_first" end;
    end;
    local target = A.Call( bot, "GetTarget" );
    if target and A.Call( target, "IsHero" ) == true then return nil, "hero_target_first" end;
    local enemies = A.Call( bot, "GetNearbyHeroes", C.rune_enemy_radius, true, BOT_MODE_NONE );
    if type( enemies ) ~= "table" then return nil, "enemy_data_unknown" end;
    for _, enemy in ipairs( enemies ) do if A.Visible( enemy ) then return nil, "enemy_nearby" end end;
    local p = A.Position( bot ); if not p then return nil, "position_unknown" end;
    if RUNE_POWERUP_1 == nil or RUNE_POWERUP_2 == nil or RUNE_STATUS_AVAILABLE == nil then return nil, "rune_constants_unknown" end;
    local towers = A.Call( bot, "GetNearbyTowers", 1600, true );
    if type( towers ) ~= "table" then return nil, "tower_data_unknown" end;
    local best, distance;
    for _, rune in ipairs( { RUNE_POWERUP_1, RUNE_POWERUP_2 } ) do
        local location = global( "GetRuneSpawnLocation", rune );
        local valid, d = pcall( function() return location and A.Distance( p, location ) end );
        local safe = true;
        if valid and location then
            for _, tower in ipairs( towers ) do
                if A.Visible( tower ) then
                    local tp, range = A.Position( tower ), A.Call( tower, "GetAttackRange" );
                    if not tp or not A.Number( range ) or A.Distance( tp, location ) <= range + 150
                        or A.Distance( tp, p ) <= range + 150 then safe = false end;
                end;
            end;
        end;
        if valid and safe and A.Number( d ) and d <= C.rune_distance
            and global( "IsLocationPassable", location ) == true
            and global( "IsLocationVisible", location ) == true
            and global( "GetRuneStatus", rune ) == RUNE_STATUS_AVAILABLE
            and ( not distance or d < distance ) then best, distance = rune, d end;
    end;
    if not best then return nil, "no_nearby_visible_available_river_rune" end;
    return { rune = best, distance = distance, desire = C.rune_desire }, "nearby_river_rune_after_lane";
end;
function M.Report( bot, plan, reason )
    local now = A.Time(); if not now then return end;
    local s = states[bot] or {}; states[bot] = s;
    if now < ( s.next_report or -math.huge ) then return end;
    s.next_report = now + 5;
    O.Emit( O.State( bot ), "rune_priority", { reason = reason, desire = plan and plan.desire or 0,
        rune = plan and plan.rune, distance = plan and plan.distance, owner = "midbot_rune_only",
        policy = "lane_and_combat_before_nearby_river_rune" } );
end;
function M.GetDesire( bot )
    local ok, plan, reason = pcall( M.Decide, bot );
    if not ok then plan, reason = nil, "decision_unavailable_no_orders" end;
    pcall( M.Report, bot, plan, reason );
    return plan and plan.desire or 0;
end;
function M.Think( bot )
    local ok, plan = pcall( M.Decide, bot );
    if not ok or not plan or BOT_MODE_RUNE == nil or A.Call( bot, "GetActiveMode" ) ~= BOT_MODE_RUNE then return end;
    -- Свежая проверка каждый Think; не идём искать руны за пределами650.
    local now = A.Time(); local s = states[bot] or {}; states[bot] = s;
    if not now or now < ( s.next_order or -math.huge ) then return end;
    s.next_order = now + 1;
    local called = pcall( function() bot:Action_PickUpRune( plan.rune ) end );
    pcall( function() O.Emit( O.State( bot ), "rune_order", { rune = plan.rune, distance = plan.distance,
        submitted = called, outcome = "unknown", owner = "midbot_rune_only" } ) end );
end;
return M;
