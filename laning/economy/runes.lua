local Actor = require( GetScriptDirectory() .. "/laning/integration/actor" );
-- Только rune mode SF. Другие режимы и обычные атаки остаются Valve.
local A = require( GetScriptDirectory() .. "/laning/runtime/api" );
local C = require( GetScriptDirectory() .. "/laning/economy/config" );
local Profile = require( GetScriptDirectory() .. "/laning/profile" );
local O = require( GetScriptDirectory() .. "/laning/observer/core" );
local M, states = {}, setmetatable( {}, { __mode = "k" } );
local function global( name, ... ) return O.Global( name, ... ) end;
function M.Decide( bot )
    if not Actor.Real(bot) then return nil,"not_real_sf" end;
    local now = A.Time();
    if Profile.economy_enabled ~= true then return nil, "profile_disabled" end;
    if not now or now < 0 or now > C.rune_window_end then return nil, "outside_rune_window" end;
    local prior = states[bot];
    if prior and now < ( prior.retry_after or -math.huge ) then return nil, "rune_retry_cooldown" end;
    if prior and prior.owned_order and prior.started_at and now - prior.started_at >= C.rune_order_timeout_s then
        return nil, "rune_pickup_timeout";
    end;
    if A.Call( bot, "IsAlive" ) ~= true then return nil, "not_alive" end;
    -- T026 (матч 9082418779): заказанный pickup ДОВОДИМ до конца. В матче
    -- 8 приказов → 8 отмен: транзиентные гейты ниже (крип в 250, ATTACK-режим
    -- на долю секунды, враг в scan) роняли desire мгновенно, режим схлопывался
    -- и наш же OnEnd/Think отменял приказ; один pickup был убит уже в пути
    -- (current_action=PICK_UP_RUNE + ClearActions). Пока попытка наша, цель
    -- та же и не истёк timeout — держим desire, даже через каст рейза в пути
    -- (IsUsingAbility) и короткий стан: движок продолжит движение сам.
    -- Снимаем попытку только смертью (выше), таймаутом (выше), низким hp
    -- или после факта подбора.
    local committed = prior ~= nil and prior.owned_order == true and prior.started_at ~= nil
        and prior.rune ~= nil and now - prior.started_at < C.rune_order_timeout_s;
    if committed then
        if prior.pickup_seen then
            local act = A.Call( bot, "GetCurrentActionType" );
            if BOT_ACTION_TYPE_PICK_UP_RUNE ~= nil and act ~= BOT_ACTION_TYPE_PICK_UP_RUNE
                and A.Call( bot, "NumQueuedActions" ) == 0 then
                return nil, "rune_attempt_finished"; -- подобрал (или точка пуста) — назад на линию
            end;
        end;
        local chp, cmaxhp = A.Call( bot, "GetHealth" ), A.Call( bot, "GetMaxHealth" );
        if A.Number( chp ) and A.Number( cmaxhp ) and cmaxhp > 0 and chp / cmaxhp < C.rune_min_hp then
            return nil, "commit_aborted_low_hp"; -- реальная опасность: отмена даже в пути
        end;
        return { rune = prior.rune, distance = nil, desire = C.rune_desire }, "rune_order_committed";
    end;
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
    -- T024b (матч 9082231706): после НАШЕГО pickup-приказа движку нужно время
    -- его начать — первые доли секунды current action ещё MOVE_TO, а очередь
    -- может быть непустой. Раньше гейты ниже схлопывали desire через 0.13с
    -- после приказа (rune_order → rune_cancel mode_ended), и бот так и не шёл
    -- на руну. Пока заказ наш и свежий (grace) — держим desire; гейты
    -- безопасности (hp/враги/крипы у вышки) ниже продолжают работать.
    local fresh_owned = prior ~= nil and prior.owned_order == true
        and prior.started_at ~= nil and now - prior.started_at < C.rune_order_grace_s;
    if not fresh_owned then
        if BOT_ACTION_TYPE_PICK_UP_RUNE == nil or A.Call( bot, "NumQueuedActions" ) ~= 0 then return nil, "rune_cancel_or_queue_unavailable" end;
        if prior and prior.owned_order and action ~= BOT_ACTION_TYPE_PICK_UP_RUNE then return nil, "rune_order_replaced_or_action_type_unknown" end;
        if action == BOT_ACTION_TYPE_PICK_UP_RUNE and not ( states[bot] and states[bot].owned_order ) then return nil, "unowned_rune_order" end;
    end;
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
    -- T024 (гайд Олега 08.11): если вражеская пачка уже у НАШЕЙ вышки/хг,
    -- сначала защищаем лайн — руна подождёт («приоритет убить крипов»).
    local ownTowers = A.Call( bot, "GetNearbyTowers", 1600, false );
    if type( ownTowers ) == "table" then
        for _, tower in ipairs( ownTowers ) do
            if A.Visible( tower ) then
                local tp = A.Position( tower );
                if tp then
                    for _, creep in ipairs( creeps ) do
                        if A.Visible( creep ) then
                            local cp = A.Position( creep );
                            if cp and A.Distance( tp, cp ) <= C.rune_lane_defense_radius then
                                return nil, "lane_defense_first";
                            end;
                        end;
                    end;
                end;
            end;
        end;
    end;
    -- T025: скан врагов ВСЕГДА на 1600 (предел API GetNearbyHeroes), чтобы
    -- rune_distance не был скован суммой с enemy_radius. Матч 9082384109:
    -- 71× no_nearby за 9 минут — с лимитом 1100 бот из mid-front до рун
    -- не доставал. Дистанция до руны теперь независима (см. config).
    local scan_radius = 1600;
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
    -- T024 (гайд Олега 08.11): окно покрывает и ВОДЯНЫЕ руны 2:00/4:00 (те же
    -- точки POWERUP_1/2), и выход ЗАРАНЕЕ — tmod >= 110 (1:50/3:50/5:50…),
    -- чтобы бот встречал руну, а не реагировал постфактум.
    local tmod = now % 120;
    local blind_window = now >= 110 and ( tmod >= 110 or tmod <= 45 );
    local towers = A.Call( bot, "GetNearbyTowers", 1600, true );
    if type( towers ) ~= "table" then return nil, "tower_data_unknown" end;
    local best, distance;
    -- T025: диагностика отказов — запоминаем, почему не подошла БЛИЖАЙШАЯ руна.
    -- Матч 9082384109: 71× «no_nearby» без деталей, причина была невидима.
    local dmin, dwhy = math.huge, "none_checked";
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
        local visible = global( "IsLocationVisible", location ) == true;
        local status = global( "GetRuneStatus", rune );
        -- T024 (гайд Олега 08.11): точку видно и руны там НЕТ — её уже забрал
        -- союзник или враг. В пустую точку не ходим даже в слепом окне;
        -- приоритет возвращается на харас/ластхит (desire падает в 0).
        local taken = visible and A.Number( status ) and status ~= RUNE_STATUS_AVAILABLE;
        local fail = nil;
        if not ( valid and location and A.Number( d ) ) then fail = "spawn_location_unknown"
        elseif not safe then fail = "unsafe"
        elseif d > C.rune_distance then fail = "too_far"
        elseif taken then fail = "taken"
        elseif global( "IsLocationPassable", location ) ~= true then fail = "not_passable"
        elseif not ( blind_window or ( visible and status == RUNE_STATUS_AVAILABLE ) ) then fail = "not_visible_outside_blind"
        end;
        -- T026 (review GPT PR53): причина без числовой дистанции
        -- (spawn_location_unknown) раньше терялась — dmin оставался math.huge
        -- и в лог уходило немое none_checked:d=?. Держим её как fallback.
        if fail then
            if A.Number( d ) then
                if d < dmin then dmin, dwhy = d, fail end;
            elseif dwhy == "none_checked" then dwhy = fail end;
        end;
        if not fail and ( not distance or d < distance ) then best, distance = rune, d end;
    end;
    if not best
    then
        local dd = ( dmin < math.huge ) and tostring( math.floor( dmin ) ) or "?";
        return nil, "no_nearby_river_rune:" .. dwhy .. ":d=" .. dd;
    end;
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
    s.owned_order = false; s.pickup_seen = nil;
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
    local now = A.Time(); local s = states[bot] or {}; states[bot] = s;
    -- T026 (матч 9082418779): пока попытка наша — НЕ отменяем её из-за
    -- транзиентных гейтов Decide: именно они сносили все 8 приказов матча
    -- (кластеры 0.2с — мгновенное схлопывание desire, 3с — конец grace без
    -- старта движка; один живой pickup убит ClearActions в пути).
    if s.owned_order then
        if not now or now - ( s.started_at or now ) >= C.rune_order_timeout_s then
            M.Leave( bot, "rune_pickup_timeout" ); return;
        end;
        local action = A.Call( bot, "GetCurrentActionType" );
        if BOT_ACTION_TYPE_PICK_UP_RUNE ~= nil and action == BOT_ACTION_TYPE_PICK_UP_RUNE then
            s.pickup_seen = true; return; -- движок в пути на руну — не трогаем
        end;
        if s.pickup_seen then
            -- pickup был и закончился (руна взята или исчезла) — отпускаем бота
            -- на линию без ClearActions: чужое/завершённое действие не трогаем.
            s.owned_order, s.pickup_seen = false, nil;
            s.retry_after = now + C.rune_retry_s;
            pcall( function() O.Emit( O.State( bot ), "rune_done", { rune = s.rune,
                owner = "midbot_rune_only", outcome = "unknown" } ) end );
            return;
        end;
        -- Приказ ещё не начался: движок терял его при мгновенном схлопывании
        -- режима (в матче — 3с IDLE после rune_order). Перевыдаём раз в
        -- секунду до таймаута вместо отмены попытки.
        if now >= ( s.next_order or -math.huge ) and s.rune ~= nil then
            s.next_order = now + 1;
            local called = pcall( function() bot:Action_PickUpRune( s.rune ) end );
            pcall( function() O.Emit( O.State( bot ), "rune_order", { rune = s.rune,
                submitted = called, outcome = "unknown", owner = "midbot_rune_only", reissue = true } ) end );
        end;
        return;
    end;
    local ok, plan = pcall( M.Decide, bot );
    if not ok or not plan or BOT_MODE_RUNE == nil or A.Call( bot, "GetActiveMode" ) ~= BOT_MODE_RUNE then
        M.Leave( bot, "plan_invalid_or_mode_changed" ); return;
    end;
    if not now or now < ( s.next_order or -math.huge ) then return end;
    s.next_order = now + 1;
    s.owned_order, s.rune, s.started_at, s.pickup_seen = true, plan.rune, now, nil; -- исключение после побочного эффекта требует guard
    local called = pcall( function() bot:Action_PickUpRune( plan.rune ) end );
    pcall( function() O.Emit( O.State( bot ), "rune_order", { rune = plan.rune, distance = plan.distance,
        submitted = called, outcome = "unknown", owner = "midbot_rune_only" } ) end );
end;
return M;
