local Actor = require( GetScriptDirectory() .. "/laning/integration/actor" );
-- Только rune mode SF. Другие режимы и обычные атаки остаются Valve.
local A = require( GetScriptDirectory() .. "/laning/runtime/api" );
local C = require( GetScriptDirectory() .. "/laning/economy/config" );
local Profile = require( GetScriptDirectory() .. "/laning/profile" );
local O = require( GetScriptDirectory() .. "/laning/observer/core" );
local M, states = {}, setmetatable( {}, { __mode = "k" } );
local function global( name, ... ) return O.Global( name, ... ) end;
-- T029: эффективный deadline попытки — базовый (distance/280+3) плюс продление
-- от РЕАЛЬНОГО старта pickup движком. Матч 9082458295, t=130.5: продление
-- вычислялось только в Think, а GetDesire срабатывал раньше на 0.07с — гонка.
function M.Deadline( s )
    local d = s.deadline or ( s.started_at and s.started_at + C.rune_order_timeout_s ) or nil;
    if d and s.pickup_seen_at then
        local ext = s.pickup_seen_at + C.rune_commit_extend_s;
        if ext > d then d = ext end;
    end;
    return d;
end;
function M.Decide( bot )
    if not Actor.Real(bot) then return nil,"not_real_sf" end;
    local now = A.Time();
    if Profile.economy_enabled ~= true then return nil, "profile_disabled" end;
    local prior = states[bot];
    -- T027 (гайд Олега 09.11): пустая бутылка (0 зарядов) + маны меньше одного
    -- рейза (< rune_bottle_mana) + потенциальная руна = идём ВСЕГДА: слепое окно
    -- шире (tmod >= 100), дистанция до rune_distance_desperate, без cap 15 минут,
    -- близкие крипы не блокируют. Гейты опасности (враги рядом/у руны, вышки,
    -- hp, taken, combat/retreat) продолжают работать — «если руну забрали или
    -- нас убивают» поход отменяется.
    local desperate = false;
    local mana0 = A.Call( bot, "GetMana" );
    if A.Number( mana0 ) and mana0 < C.rune_bottle_mana then
        for slot = 0, 5 do
            local item = A.Call( bot, "GetItemInSlot", slot );
            if item ~= nil then
                local okn, name = pcall( function() return item:GetName() end );
                if okn and name == "item_bottle" then
                    local okc, charges = pcall( function() return item:GetCurrentCharges() end );
                    desperate = ( okc and A.Number( charges ) and charges <= 0 ) or false;
                    break;
                end;
            end;
        end;
    end;
    if not now or now < 0 or ( now > C.rune_window_end and not desperate ) then return nil, "outside_rune_window" end;
    if prior and now < ( prior.retry_after or -math.huge ) then return nil, "rune_retry_cooldown" end;
    -- T028: таймаут считается по deadline попытки (distance/280+3 при заказе,
    -- продлевается после реального старта pickup движком), а не тупо от первого
    -- приказа — матч 9082444290: pickup, начатый движком после спавна, убивался
    -- ClearActions ровно на 8с у порога руны.
    local prior_deadline = prior and M.Deadline( prior ) or nil;
    if prior and prior.owned_order and prior_deadline and now >= prior_deadline then
        return nil, "rune_pickup_timeout";
    end;
    if A.Call( bot, "IsAlive" ) ~= true then return nil, "not_alive" end;
    -- T026 (матч 9082418779): заказанный pickup ДОВОДИМ до конца. В матче
    -- 8 приказов → 8 отмен: транзиентные гейты ниже (крип в 250, ATTACK-режим
    -- на долю секунды, враг в scan) роняли desire мгновенно, режим схлопывался
    -- и наш же OnEnd/Think отменял приказ; один pickup был убит уже в пути
    -- (current_action=PICK_UP_RUNE + ClearActions). Пока попытка наша, цель
    -- та же и не истёк deadline — держим desire, даже через каст рейза в пути
    -- (IsUsingAbility) и короткий стан: движок продолжит движение сам.
    -- Снимаем попытку только смертью (выше), таймаутом (выше), низким hp,
    -- руной, забранной на глазах, или после факта подбора.
    local committed = prior ~= nil and prior.owned_order == true and prior.started_at ~= nil
        and prior.rune ~= nil and prior_deadline ~= nil and now < prior_deadline;
    if committed then
        if prior.pickup_seen then
            local act = A.Call( bot, "GetCurrentActionType" );
            if BOT_ACTION_TYPE_PICK_UP_RUNE ~= nil and act ~= BOT_ACTION_TYPE_PICK_UP_RUNE
                and A.Call( bot, "NumQueuedActions" ) == 0 then
                return nil, "rune_attempt_finished"; -- подобрал (или точка пуста) — назад на линию
            end;
        else
            -- T028: ждать руну на пустой точке нормально (слепое окно), но если
            -- она на глазах ЗАБРАНА — уходим немедленно, не стоим до таймаута.
            -- T029 (матч 9082458295): ДО спавна (tmod >= 100) статус «нет руны»
            -- это MISSING, а не «забрали» — 4 подхода убиты ложным taken.
            if ( now % 120 ) < 100 then
                local loc0 = global( "GetRuneSpawnLocation", prior.rune );
                local st0 = loc0 and global( "GetRuneStatus", prior.rune ) or nil;
                if loc0 and global( "IsLocationVisible", loc0 ) == true and RUNE_STATUS_AVAILABLE ~= nil
                    and A.Number( st0 ) and st0 ~= RUNE_STATUS_AVAILABLE then
                    return nil, "rune_taken_while_committed";
                end;
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
    -- T027: при пустой бутылке и низкой мане крипы не блокируют поход вовсе.
    local bp0 = A.Position( bot );
    if not desperate then
        for _, creep in ipairs( creeps ) do
            if A.Visible( creep ) then
                local cp = A.Position( creep );
                if not cp or not bp0 or A.Distance( bp0, cp ) <= C.rune_creep_block_radius then return nil, "lane_creeps_first" end;
            end;
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
    -- T027: с пустой бутылкой выходим ещё раньше (tmod >= 100, ~20с на дальний
    -- подход) и достаём руны с любой позиции на миде.
    if desperate then blind_window = now >= 100 and ( tmod >= 100 or tmod <= 45 ) end;
    local max_distance = desperate and C.rune_distance_desperate or C.rune_distance;
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
        elseif d > max_distance then fail = "too_far"
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
    return { rune = best, distance = distance, desire = C.rune_desire },
        desperate and "bottle_empty_rune_run" or "nearby_river_rune_after_lane";
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
    local st = states[bot] or {}; states[bot] = st; st.last_reason = reason; -- T028: причина для rune_cancel
    pcall( M.Report, bot, plan, reason );
    return plan and plan.desire or 0;
end;
function M.Leave( bot, reason )
    local s = states[bot]; if not s or not s.owned_order then return end;
    local seen, decide_reason = s.pickup_seen, s.last_reason;
    s.owned_order = false; s.pickup_seen = nil; s.pickup_seen_at = nil; s.deadline = nil; s.close_tries = nil;
    local now = A.Time(); if now then s.retry_after = now + C.rune_retry_s end;
    local action = A.Call( bot, "GetCurrentActionType" );
    local can_cancel = BOT_ACTION_TYPE_PICK_UP_RUNE ~= nil and action == BOT_ACTION_TYPE_PICK_UP_RUNE
        and A.Call( bot, "NumQueuedActions" ) == 0
        and A.Call( bot, "IsUsingAbility" ) == false and A.Call( bot, "IsChanneling" ) == false;
    local submitted = false;
    if can_cancel then submitted = pcall( function() bot:Action_ClearActions( true ) end ) end;
    pcall( function() O.Emit( O.State( bot ), "rune_cancel", { reason = reason or "mode_ended",
        submitted = submitted, current_action = action, owner = "midbot_rune_only", outcome = "unknown",
        last_decide_reason = decide_reason, pickup_seen = seen,
        guard = can_cancel and "owned_pickup_empty_queue_no_cast" or "preserve_other_or_unknown_action" } ) end );
end;
-- T028 (матч 9082444290): движок молча отклоняет Action_PickUpRune ДО СПАВНА
-- руны и часто издалека (8 перевыдач за 8с — бот стоял IDLE). Теперь до точки
-- ИДЁМ через Action_MoveToLocation, а PickUp отдаём только в rune_pickup_range.
function M.Approach( bot, s, distance, reason, reissue )
    local d = distance;
    if not A.Number( d ) then
        local okd, dd = pcall( function()
            local p, loc = A.Position( bot ), global( "GetRuneSpawnLocation", s.rune );
            return loc and A.Distance( p, loc ) or nil;
        end );
        if okd and A.Number( dd ) then d = dd end;
    end;
    local called, kind = false, "pickup";
    local loc = global( "GetRuneSpawnLocation", s.rune );
    if A.Number( d ) and d > C.rune_pickup_range and loc then
        kind = "move"; called = pcall( function() bot:Action_MoveToLocation( loc ) end );
    elseif A.Number( d ) and d < C.rune_pickup_min and loc then
        -- T030 (матч 9082480212): стоим ТОЧНО на споте (d≈0) — движок молча
        -- отклоняет pickup (5 эпизодов: t=137, 236, 354, 476, 596). Отступаем
        -- от точки к центру реки на rune_backoff_dist, следующий тик выдаст
        -- pickup с рабочей дистанции.
        kind = "backoff";
        called = pcall( function()
            local px, py = -loc.x, -loc.y;
            local n = math.sqrt( px * px + py * py ); if n < 1 then px, py, n = 1, 0, 1 end;
            local bx, by = loc.x + px / n * C.rune_backoff_dist, loc.y + py / n * C.rune_backoff_dist;
            local okv, back = pcall( Vector, bx, by, loc.z or 0 );
            bot:Action_MoveToLocation( okv and back or { x = bx, y = by } );
        end );
    end;
    if kind == "pickup" then called = pcall( function() bot:Action_PickUpRune( s.rune ) end ) end;
    -- T029: статус и видимость точки в событии — матч 9082458295, t=297-306:
    -- бот стоял НА споте (d=1.0), 4 pickup молча отклонены движком.
    pcall( function() O.Emit( O.State( bot ), "rune_order", { rune = s.rune, distance = d,
        submitted = called, kind = kind, rule = reason, reissue = reissue or nil,
        rune_status = global( "GetRuneStatus", s.rune ),
        spot_visible = loc ~= nil and global( "IsLocationVisible", loc ) or nil,
        outcome = "unknown", owner = "midbot_rune_only" } ) end );
    return d, kind;
end;
function M.Think( bot )
    local now = A.Time(); local s = states[bot] or {}; states[bot] = s;
    -- T026 (матч 9082418779): пока попытка наша — НЕ отменяем её из-за
    -- транзиентных гейтов Decide: именно они сносили все 8 приказов матча
    -- (кластеры 0.2с — мгновенное схлопывание desire, 3с — конец grace без
    -- старта движка; один живой pickup убит ClearActions в пути).
    if s.owned_order then
        if not now or now >= ( M.Deadline( s ) or now ) then
            M.Leave( bot, "rune_pickup_timeout" ); return;
        end;
        local action = A.Call( bot, "GetCurrentActionType" );
        if BOT_ACTION_TYPE_PICK_UP_RUNE ~= nil and action == BOT_ACTION_TYPE_PICK_UP_RUNE then
            if not s.pickup_seen then s.pickup_seen, s.pickup_seen_at = true, now end;
            return; -- движок в пути на руну — не трогаем (продление через M.Deadline)
        end;
        if s.pickup_seen then
            -- pickup был и закончился (руна взята или исчезла) — отпускаем бота
            -- на линию без ClearActions: чужое/завершённое действие не трогаем.
            s.owned_order, s.pickup_seen, s.pickup_seen_at, s.deadline = false, nil, nil, nil;
            s.retry_after = now + C.rune_retry_s;
            pcall( function() O.Emit( O.State( bot ), "rune_done", { rune = s.rune,
                owner = "midbot_rune_only", outcome = "unknown" } ) end );
            return;
        end;
        -- Приказ ещё не начался: движок терял его при мгновенном схлопывании
        -- режима (в матче — 3с IDLE после rune_order). Перевыдаём раз в
        -- секунду до таймаута вместо отмены попытки; издалека идём MoveTo.
        if now >= ( s.next_order or -math.huge ) and s.rune ~= nil then
            -- T029 (матч 9082458295, t=297-306): стоим НА споте, движок молча
            -- отклоняет pickup — после спавна это пустая точка, не ждём таймаут.
            -- Лимит проверяем ДО перевыдачи: rune_close_reject_tries близких
            -- перевыдач без старта движка → закрываем попытку. До спавна
            -- (tmod >= 100) ожидание на точке — НОРМА, не считаем.
            if ( s.close_tries or 0 ) >= C.rune_close_reject_tries then
                M.Leave( bot, "pickup_rejected_at_point_blank" ); return;
            end;
            s.next_order = now + 1;
            local d, kind = M.Approach( bot, s, nil, nil, true );
            if kind == "pickup" and A.Number( d ) and d <= 250 and ( now % 120 ) < 100 then
                s.close_tries = ( s.close_tries or 0 ) + 1;
            else s.close_tries = 0 end;
        end;
        return;
    end;
    local ok, plan, reason = pcall( M.Decide, bot );
    if not ok or not plan or BOT_MODE_RUNE == nil or A.Call( bot, "GetActiveMode" ) ~= BOT_MODE_RUNE then
        M.Leave( bot, "plan_invalid_or_mode_changed" ); return;
    end;
    if not now or now < ( s.next_order or -math.huge ) then return end;
    s.next_order = now + 1;
    s.owned_order, s.rune, s.started_at, s.pickup_seen, s.pickup_seen_at, s.close_tries = true, plan.rune, now, nil, nil, 0; -- исключение после побочного эффекта требует guard
    -- T028: deadline по дистанции (пешком ~280 ед/с + запас 3с), минимум
    -- rune_order_timeout_s — дальние desperate-походы (3500)
    -- не умирают по 8с таймауту на полпути.
    local walk = A.Number( plan.distance ) and plan.distance / 280 + 3 or C.rune_order_timeout_s;
    -- T030 (матч 9082480212): дедлайн срезал ДОСПАВНОВОЕ ожидание на точке —
    -- t=357.5 за 2.5с до спавна, t=479.5 за 0.5с, t=600.0 ровно в спавн. Идём
    -- под спавн (tmod >= 100) → дедлайн покрывает ожидание до спавна + grace.
    local tmod = now % 120;
    if tmod >= 100 then
        local wait_spawn = ( 120 - tmod ) + C.rune_commit_extend_s;
        if walk < wait_spawn then walk = wait_spawn end;
    end;
    if walk < C.rune_order_timeout_s then walk = C.rune_order_timeout_s elseif walk > C.rune_deadline_max_s then walk = C.rune_deadline_max_s end;
    s.deadline = now + walk;
    M.Approach( bot, s, plan.distance, reason );
end;
return M;
