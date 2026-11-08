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
    local prior = states[bot];
    if prior and now < ( prior.retry_after or -math.huge ) then return nil, "rune_retry_cooldown" end;
    if prior and prior.owned_order and prior.started_at and now - prior.started_at >= C.rune_order_timeout_s then
        return nil, "rune_pickup_timeout";
    end;
    if A.Call( bot, "IsAlive" ) ~= true then return nil, "not_alive" end;
    for _, method in ipairs( { "IsUsingAbility", "IsChanneling", "IsStunned", "IsHexed", "IsRooted" } ) do
        if A.Call( bot, method ) ~= false then return nil, "busy_or_unknown" end;
    end;
    local mode = A.Call( bot, "GetActiveMode" );
    if mode == nil or BOT_MODE_RETREAT == nil or BOT_MODE_ATTACK == nil then return nil, "mode_unknown" end;
    if mode == BOT_MODE_RETREAT or mode == BOT_MODE_ATTACK then return nil, "combat_or_retreat" end;
    if BOT_MODE_EVASIVE_MANEUVERS ~= nil and mode == BOT_MODE_EVASIVE_MANEUVERS then return nil, "evasion_first" end;
    -- T022: текущая атака больше не блокирует руну — бот на линии почти всегда
    -- в ATTACK, из-за этого гейта режим не включался никогда. Блокируем только
    -- неизвестное действие: отдавать приказ pickup поверх непонятного состояния
    -- небезопасно. Свежий pickup поверх атаки движок принимает штатно.
    local action = A.Call( bot, "GetCurrentActionType" );
    if action == nil then return nil, "action_unknown" end;
    if BOT_ACTION_TYPE_PICK_UP_RUNE == nil or A.Call( bot, "NumQueuedActions" ) ~= 0 then return nil, "rune_cancel_or_queue_unavailable" end;
    if prior and prior.owned_order and action ~= BOT_ACTION_TYPE_PICK_UP_RUNE then return nil, "rune_order_replaced_or_action_type_unknown" end;
    if action == BOT_ACTION_TYPE_PICK_UP_RUNE and not ( states[bot] and states[bot].owned_order ) then return nil, "unowned_rune_order" end;
    local hp, maxhp = A.Call( bot, "GetHealth" ), A.Call( bot, "GetMaxHealth" );
    if not A.Number( hp ) or not A.Number( maxhp ) or maxhp <= 0 or hp / maxhp < C.rune_min_hp then return nil, "health_or_unknown" end;
    local creeps = A.Call( bot, "GetNearbyLaneCreeps", C.lane_radius, true );
    if type( creeps ) ~= "table" then return nil, "lane_unknown" end;
    -- T022: блокируют только крипы ВПЛОТНУЮ к боту (rune_creep_block_radius).
    -- Раньше любой видимый крип в lane_radius=1200 отменял руну — на миде крипы
    -- видны почти всегда, поэтому desire ни разу не поднялся выше 0.
    local bp0 = A.Position( bot );
    for _, creep in ipairs( creeps ) do
        if A.Visible( creep ) then
            local cp = A.Position( creep );
            if not cp or not bp0 or A.Distance( bp0, cp ) <= C.rune_creep_block_radius then return nil, "lane_creeps_first" end;
        end;
    end;
    local target = A.Call( bot, "GetTarget" );
    if A.Visible( target ) and A.Call( target, "IsHero" ) == true then
        local tp, bp = A.Position( target ), A.Position( bot );
        if not tp or not bp or A.Distance( tp, bp ) <= C.lane_radius then return nil, "hero_target_first" end;
    end;
    local scan_radius = C.rune_distance + C.rune_enemy_radius;
    if scan_radius > 1600 then return nil, "enemy_scan_radius_unsupported" end;
    local enemies = A.Call( bot, "GetNearbyHeroes", scan_radius, true, BOT_MODE_NONE );
    if type( enemies ) ~= "table" then return nil, "enemy_data_unknown" end;
    local p = A.Position( bot ); if not p then return nil, "position_unknown" end;
    local enemy_positions = {};
    for _, enemy in ipairs( enemies ) do
        if A.Visible( enemy ) then
            local ep = A.Position( enemy ); if not ep then return nil, "enemy_position_unknown" end;
            if A.Distance( p, ep ) <= C.rune_enemy_radius then return nil, "enemy_nearby" end;
            enemy_positions[#enemy_positions + 1] = ep;
        end;
    end;
    if RUNE_POWERUP_1 == nil or RUNE_POWERUP_2 == nil or RUNE_STATUS_AVAILABLE == nil then return nil, "rune_constants_unknown" end;
    -- T022: силовые руны спавнятся каждые 120 сек начиная с 6:00 (360 % 120 == 0).
    -- Вардов у бота нет, руну он не видит, IsLocationVisible/GetRuneStatus всегда
    -- отвечают «нет» — поэтому в коротком окне после спавна идём «вслепую».
    -- Безопасность уже отфильтрована выше (враги, вышки, hp, крипы вплотную);
    -- если руны на месте нет, pickup timeout и Leave вернут бота на линию.
    local blind_window = now >= 360 and ( now % 120 ) >= 5 and ( now % 120 ) <= 45;
    local towers = A.Call( bot, "GetNearbyTowers", 1600, true );
    if type( towers ) ~= "table" then return nil, "tower_data_unknown" end;
    local best, distance;
    for _, rune in ipairs( { RUNE_POWERUP_1, RUNE_POWERUP_2 } ) do
        local location = global( "GetRuneSpawnLocation", rune );
        local valid, d = pcall( function() return location and A.Distance( p, location ) end );
        local safe = true;
        if valid and location then
            for _, ep in ipairs( enemy_positions ) do
                if A.Distance( ep, location ) <= C.rune_enemy_radius then safe = false end;
            end;
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
            and ( blind_window
                or ( global( "IsLocationVisible", location ) == true
                    and global( "GetRuneStatus", rune ) == RUNE_STATUS_AVAILABLE ) )
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
        policy = "safe_rune_window_outranks_lane_close_creeps_combat_block" } );
end;
function M.GetDesire( bot )
    local ok, plan, reason = pcall( M.Decide, bot );
    if not ok then plan, reason = nil, "decision_unavailable_no_orders" end;
    pcall( M.Report, bot, plan, reason );
    return plan and plan.desire or 0;
end;
function M.Leave( bot, reason )
    local s = states[bot]; if not s or not s.owned_order then return end;
    s.owned_order = false;
    local now = A.Time(); if now then s.retry_after = now + C.rune_retry_s end;
    local action = A.Call( bot, "GetCurrentActionType" );
    local can_cancel = BOT_ACTION_TYPE_PICK_UP_RUNE ~= nil and action == BOT_ACTION_TYPE_PICK_UP_RUNE
        and A.Call( bot, "NumQueuedActions" ) == 0
        and A.Call( bot, "IsUsingAbility" ) == false and A.Call( bot, "IsChanneling" ) == false;
    local submitted = false;
    if can_cancel then submitted = pcall( function() bot:Action_ClearActions( true ) end ) end;
    pcall( function() O.Emit( O.State( bot ), "rune_cancel", { reason = reason or "mode_ended",
        submitted = submitted, current_action = action, owner = "midbot_rune_only", outcome = "unknown",
        guard = can_cancel and "owned_pickup_empty_queue_no_cast" or "preserve_other_or_unknown_action" } ) end );
end;
function M.Think( bot )
    local ok, plan = pcall( M.Decide, bot );
    if not ok or not plan or BOT_MODE_RUNE == nil or A.Call( bot, "GetActiveMode" ) ~= BOT_MODE_RUNE then
        M.Leave( bot, "plan_invalid_or_mode_changed" ); return;
    end;
    -- Свежая проверка каждый Think; не идём искать руны за пределами650.
    local now = A.Time(); local s = states[bot] or {}; states[bot] = s;
    if s.owned_order then
        if A.Call( bot, "GetCurrentActionType" ) == BOT_ACTION_TYPE_PICK_UP_RUNE then
            if s.rune ~= plan.rune then M.Leave( bot, "rune_target_changed" ) end;
            return; -- не перезапускаем уже идущий pickup каждый1с
        end;
        s.owned_order = false;
    end;
    if not now or now < ( s.next_order or -math.huge ) then return end;
    s.next_order = now + 1;
    s.owned_order, s.rune, s.started_at = true, plan.rune, now; -- исключение после побочного эффекта требует guard
    local called = pcall( function() bot:Action_PickUpRune( plan.rune ) end );
    pcall( function() O.Emit( O.State( bot ), "rune_order", { rune = plan.rune, distance = plan.distance,
        submitted = called, outcome = "unknown", owner = "midbot_rune_only" } ) end );
end;
return M;
