-- Cases found by self-review of PR41. Shared fixture, real production callbacks.
local scenario = ECONOMY_REVIEW_SCENARIO;
assert( type( scenario ) == "function" );
local passed = 0;
local function eq( a, b ) assert( a == b, tostring( a ) .. " ~= " .. tostring( b ) ) end;
local function test( name, fn ) fn(); passed = passed + 1; print( "PASS ECONOMY_REVIEW " .. name ) end;
local function pickup( s )
    s.env.BOT_ACTION_TYPE_PICK_UP_RUNE = 8; s.env.BOT_MODE_EVASIVE_MANEUVERS = 19;
    s.bot.IsRooted = function() return s.rooted or false end;
    s.moves = {};
    -- T028: издалека бот ИДЁТ к точке руны (MoveTo), PickUp только вблизи.
    s.bot.Action_MoveToLocation = function( _, loc ) s.moves[#s.moves + 1] = loc; s.action = 2 end;
    s.bot.Action_PickUpRune = function( _, rune ) s.runes[#s.runes + 1] = rune; s.action = 8 end;
    s.bot.Action_ClearActions = function( _, stop ) eq( stop, true ); s.cancelled = ( s.cancelled or 0 ) + 1; s.action = 0 end;
end;
test( "enemy near one rune redirects the approach to the other", function()
    local s = scenario(); pickup( s ); local enemy = s:unit();
    enemy.GetLocation = function() return { x = 800, y = 0 } end; -- до руны 1 (400,0) = 400 <= rune_enemy_radius 500
    s.bot.GetNearbyHeroes = function( _, radius ) return radius >= 800 and { enemy } or {} end;
    -- T025: rune_distance 2200 — вторая руна (2000,0) досягаема; враг у первой
    -- руны перенаправляет бота ко ВТОРОЙ, а не отменяет поход полностью.
    -- T028: d=2000 > rune_pickup_range 900 — сначала MoveTo к точке второй руны.
    eq( s.rune_policy.GetDesire( s.bot ), .85 ); s.mode = 7; s.rune_policy.Think( s.bot );
    eq( #s.runes, 0 ); eq( #s.moves, 1 ); eq( s.moves[1].x, 2000 ); -- идёт ко ВТОРОЙ, не к первой
    s.bot.GetLocation = function() return { x = 1500, y = 0 } end; -- подошёл: d=500 <= 900
    s.time = 101; s.rune_policy.Think( s.bot ); eq( #s.runes, 1 ); eq( s.runes[1], 1 ); -- теперь PickUp
end );
test( "wave arriving during pickup does not cancel the committed rune order", function()
    local s = scenario(); pickup( s ); s.mode = 7; s.rune_policy.Think( s.bot ); eq( #s.runes, 1 );
    -- T026 (матч 9082418779): транзиентные гейты (крип рядом на 0.2с) роняли
    -- desire и сносили приказ — так умерли все 8 походов за рунами. Пока
    -- попытка наша и не истёк timeout, волна крипов её НЕ отменяет.
    s.creeps = { s:unit() }; s.time = 101; eq( s.rune_policy.GetDesire( s.bot ), .85 );
    s.rune_policy.Think( s.bot ); eq( s.cancelled, nil ); eq( #s.runes, 1 );
end );
test( "completed purchase missed between polls does not block all future supply", function()
    local s = scenario(); s.enemies = { s:unit() }; s.mana_policy.TryPurchase( s.bot );
    -- Engine accepted mango, delivered and consumed it before next observation.
    s.time = 190; eq( s.mana_policy.TryPurchase( s.bot ), true ); eq( #s.calls, 2 );
end );
test( "far stale hero target does not permanently suppress a safe nearby rune", function()
    local s = scenario(); pickup( s ); s.target = s:unit();
    s.target.GetLocation = function() return { x = 3000, y = 0 } end;
    eq( s.rune_policy.GetDesire( s.bot ), .85 );
end );
test( "salve skipping obeys the mana experiment time window", function()
    local s = scenario(); s.time = 601; eq( s.mana_policy.SkipFlask( s.bot ), false );
end );
test( "unknown result followed by delivery still consumes the purchase budget", function()
    local s = scenario(); s.result = nil;
    for i = 0, 3 do
        s.time = 100 + i * 100; s.mana_policy.TryPurchase( s.bot );
        s.items[0] = s:item( "item_clarity", 1 ); s.time = s.time + 5;
        s.mana_policy.TryPurchase( s.bot ); s.items[0] = nil;
    end;
    eq( #s.calls, 3 );
end );
test( "OnEnd cancels only the tracked pickup with no queued action", function()
    local s = scenario(); pickup( s ); s:load( "profiles/lane_economy/mode_rune_nevermore.lua" );
    s.mode = 7; s.env.Think(); eq( #s.runes, 1 ); s.mode = 1; s.env.OnEnd(); eq( s.cancelled, 1 );
end );
test( "new native attack retires ownership and is never cleared", function()
    local s = scenario(); pickup( s ); s.mode = 7; s.rune_policy.Think( s.bot ); s.action = 4;
    s.rune_policy.Leave( s.bot ); eq( s.cancelled, nil ); eq( s.action, 4 );
    s.action = 8; s.rune_policy.Leave( s.bot ); eq( s.cancelled, nil );
end );
test( "cast, channel or queued actions are preserved on exit", function()
    for _, kind in ipairs( { "cast", "channel", "queued", "queue_unknown" } ) do
        local s = scenario(); pickup( s ); s.mode = 7; s.rune_policy.Think( s.bot );
        if kind == "cast" then s.casting = true
        elseif kind == "channel" then s.bot.IsChanneling = function() return true end
        elseif kind == "queued" then s.bot.NumQueuedActions = function() return 1 end
        else s.bot.NumQueuedActions = nil end;
        s.rune_policy.Leave( s.bot ); eq( s.cancelled, nil );
    end;
end );
test( "no owned pickup means no clearing even if current action has rune type", function()
    local s = scenario(); pickup( s ); s.action = 8;
    s.rune_policy.Leave( s.bot ); eq( s.cancelled, nil ); eq( s.rune_policy.GetDesire( s.bot ), 0 );
end );
test( "missing cancellation enum, root and evasion suppress new rune orders", function()
    local s = scenario(); pickup( s ); s.env.BOT_ACTION_TYPE_PICK_UP_RUNE = nil; eq( s.rune_policy.GetDesire( s.bot ), 0 );
    local t = scenario(); pickup( t ); t.rooted = true; eq( t.rune_policy.GetDesire( t.bot ), 0 );
    t.rooted = false; t.mode = 19; eq( t.rune_policy.GetDesire( t.bot ), 0 );
end );
test( "pickup has a distance-aware timeout and reentry cannot bypass retry cooldown", function()
    -- T028: deadline = distance/280+3 (мин 8с) от приказа; после РЕАЛЬНОГО старта
    -- pickup движком продлевается на rune_commit_extend_s (матч 9082444290:
    -- живой pickup убивался ClearActions ровно на 8с у порога руны).
    local s = scenario(); pickup( s ); s.time = 130; s.mode = 7; s.rune_policy.Think( s.bot ); eq( #s.runes, 1 );
    s.time = 137; s.rune_policy.Think( s.bot ); eq( #s.runes, 1 ); -- движок в пути (action 8)
    s.time = 142.9; assert( s.rune_policy.GetDesire( s.bot ) > 0 ); -- продлено до 143
    s.time = 143.1; eq( s.rune_policy.GetDesire( s.bot ), 0 ); s.rune_policy.Leave( s.bot ); eq( s.cancelled, 1 );
    s.time = 144; eq( s.rune_policy.GetDesire( s.bot ), 0 ); s.time = 153.2; assert( s.rune_policy.GetDesire( s.bot ) > 0 );
end );
test( "unseen stale target is not read for hidden location", function()
    local s = scenario(); pickup( s ); s.target = s:unit(); s.target.CanBeSeen = function() return false end;
    s.target.GetLocation = function() error( "hidden location access" ) end;
    eq( s.rune_policy.GetDesire( s.bot ), .85 );
end );
test( "unobserved nonnumeric purchase result remains unknown", function()
    for _, value in ipairs( { false, "unknown", {} } ) do
        local s = scenario(); s.result = value; s.mana_policy.TryPurchase( s.bot ); s.time = 300;
        eq( s.mana_policy.TryPurchase( s.bot ), false ); eq( #s.calls, 1 );
    end;
end );
test( "unknown mango outcomes count toward the gold cap too", function()
    local s = scenario(); s.result = nil; s.enemies = { s:unit() };
    for i = 0, 3 do
        s.time = 100 + i * 100; s.mana_policy.TryPurchase( s.bot );
        s.items[0] = s:item( "item_enchanted_mango", 1 ); s.time = s.time + 5;
        s.mana_policy.TryPurchase( s.bot ); s.items[0] = nil;
    end;
    eq( #s.calls, 2 );
end );
test( "failed attempts release budget reservation rather than exhausting supplies", function()
    local s = scenario(); s.result = 4;
    for i = 0, 4 do s.time = 100 + i * 5; s.mana_policy.TryPurchase( s.bot ) end;
    s.result = 0; s.time = 125; eq( s.mana_policy.TryPurchase( s.bot ), true ); eq( #s.calls, 6 );
end );
test( "engine not starting the pickup re-issues the order instead of cancelling", function()
    local s = scenario(); pickup( s ); s.time = 130; s.mode = 7; s.rune_policy.Think( s.bot );
    -- T026 (матч 9082418779): движок терял приказ при мгновенном схлопывании
    -- режима — бот стоял IDLE до конца grace, затем попытка отменялась. Теперь
    -- desire держится весь timeout, неначавшийся приказ перевыдаётся раз в
    -- секунду, чужое движение не очищается.
    s.action = 2; s.time = 131; eq( s.rune_policy.GetDesire( s.bot ), .85 );
    s.time = 134; eq( s.rune_policy.GetDesire( s.bot ), .85 ); s.rune_policy.Think( s.bot );
    eq( s.cancelled, nil ); eq( #s.runes, 2 ); eq( s.action, 8 );
    s.time = 142; eq( s.rune_policy.GetDesire( s.bot ), 0 ); -- timeout: first_pickup 130 + окно 12с (T031)
end );
test( "finished pickup releases the bot without clearing and blocks instant reorder", function()
    local s = scenario(); pickup( s ); s.mode = 7; s.rune_policy.Think( s.bot ); eq( #s.runes, 1 );
    s.rune_policy.Think( s.bot ); -- action==8: движок в пути на руну
    s.action = 2; s.time = 102; -- pickup завершён: действие сменилось
    eq( s.rune_policy.GetDesire( s.bot ), 0 ); -- rune_attempt_finished
    s.rune_policy.Think( s.bot ); eq( s.cancelled, nil ); eq( #s.runes, 1 ); -- очистка без ClearActions
    s.time = 111; eq( s.rune_policy.GetDesire( s.bot ), 0 ); -- retry 10с с момента завершения
    s.time = 113; assert( s.rune_policy.GetDesire( s.bot ) > 0 );
end );
test( "rune taken in plain sight aborts the committed wait", function()
    -- T028: ждать руну на пустой точке в слепом окне — норма, но если точку
    -- видно и руны там НЕТ (после спавна) — уходим сразу, а не стоим до таймаута.
    local s = scenario(); pickup( s ); s.time = 130; s.mode = 7; -- tmod=10: после спавна
    s.rune_policy.Think( s.bot ); eq( #s.runes, 1 );
    s.action = 2; -- ещё идём, pickup не начался
    s.status = 3; s.time = 131; -- точка видна, руна забрана на глазах
    eq( s.rune_policy.GetDesire( s.bot ), 0 ); -- rune_taken_while_committed
end );
test( "missing rune before spawn does not abort the committed wait", function()
    -- T029 (матч 9082458295): до спавна (tmod >= 100) статус «нет руны» — это
    -- MISSING, а не «забрали»; 4 подхода матча убиты этим ложным срабатыванием.
    local s = scenario(); pickup( s ); s.time = 350; s.visible = false; -- blind, tmod=110
    s.mode = 7; s.rune_policy.Think( s.bot ); eq( #s.moves + #s.runes, 1 );
    s.action = 2; s.status = 3; s.visible = true; s.time = 356; -- точка видна, пусто, ДО спавна
    assert( s.rune_policy.GetDesire( s.bot ) > 0 ); -- держим: это MISSING, не taken
end );
test( "point blank position backoffs instead of a silently rejected pickup", function()
    -- T030 (матч 9082480212): движок молча отклоняет pickup, когда бот стоит
    -- ТОЧНО на споте (5 эпизодов: t=137/236/354/476/596, d=0). Ближе
    -- rune_pickup_min отступаем от точки, pickup — уже с рабочей дистанции;
    -- 4 близких отказа после спавна по-прежнему закрывают попытку (T029).
    local s = scenario(); pickup( s ); s.time = 130; s.mode = 7;
    s.bot.GetLocation = function() return { x = 380, y = 0 } end; -- d=20 до руны 0
    s.rune_policy.Think( s.bot );
    eq( #s.runes, 0 ); eq( #s.moves, 1 ); eq( s.moves[1].x, 200 ); -- отступ к центру реки
    s.bot.GetLocation = function() return { x = 200, y = 0 } end; -- отступил: d=200
    s.bot.Action_PickUpRune = function( _, rune ) s.runes[#s.runes + 1] = rune end; -- движок НЕ начинает
    s.time = 131; s.rune_policy.Think( s.bot ); eq( #s.runes, 1 ); -- pickup с 200
    -- T031: pickup перевыдаётся раз в 2.5с, не чаще — движку нужно время дойти
    s.time = 132; s.rune_policy.Think( s.bot ); eq( #s.runes, 1 ); -- интервал не вышел
    for _, t in ipairs( { 134, 137, 140 } ) do s.time = t; s.rune_policy.Think( s.bot ); end; eq( #s.runes, 4 );
    s.time = 142.6; s.rune_policy.Think( s.bot ); -- 4 близких отказа без старта → Leave (интервал 2.5с вышел)
    eq( s.cancelled, nil ); eq( #s.runes, 4 ); eq( s.rune_policy.GetDesire( s.bot ), 0 ); -- retry
end );
test( "deadline covers the wait for the rune spawn", function()
    -- T030 (матч 9082480212): дедлайн подхода срезал ДОСПАВНОВОЕ ожидание —
    -- t=479.5 за 0.5с до спавна 8:00, t=357.5 за 2.5с, t=600.0 ровно в спавн.
    -- Идём под спавн (tmod >= 100) → ждём спавн + rune_commit_extend_s.
    local s = scenario(); pickup( s ); s.time = 465; s.mode = 7; -- tmod=105: под спавн 480
    s.bot.Action_PickUpRune = function( _, rune ) s.runes[#s.runes + 1] = rune end; -- движок молчит до спавна
    s.rune_policy.Think( s.bot ); eq( #s.runes, 1 ); -- d=400: pickup выдан
    s.time = 480; eq( s.rune_policy.GetDesire( s.bot ), .85 ); -- walk 4.4с вышел, но ждём спавн+grace
    s.time = 487; eq( s.rune_policy.GetDesire( s.bot ), 0 ); -- спавн+grace прошли → timeout
end );
test( "distant rune is approached by move before pickup", function()
    -- T028 (матч 9082444290): движок молча отклоняет PickUp издалека и до
    -- спавна — сначала ИДЁМ к точке, PickUp только ближе rune_pickup_range.
    local s = scenario(); pickup( s );
    s.env.GetRuneSpawnLocation = function( rune ) return { x = rune == 0 and 1600 or 3000, y = 0 } end;
    s.mode = 7; s.rune_policy.Think( s.bot ); eq( #s.runes, 0 ); eq( #s.moves, 1 ); eq( s.moves[1].x, 1600 );
    s.bot.GetLocation = function() return { x = 1400, y = 0 } end; -- подошёл: d=200 в рабочем диапазоне 120..900
    s.time = 101; s.rune_policy.Think( s.bot ); eq( #s.runes, 1 ); eq( s.runes[1], 0 );
end );
test( "resolved rune is not retried until the next spawn cycle", function()
    -- T031 (матч 9082503862): после rune_done 120.7 бот ещё дважды (t=137, 151)
    -- бежал к уже взятой НАМИ руне — «много лишних движений в сторону рун».
    -- Решённая руна блокируется до конца текущего 120-секундного цикла.
    local s = scenario(); pickup( s ); s.time = 130; s.mode = 7;
    s.rune_policy.Think( s.bot ); eq( #s.runes, 1 ); -- pickup, mock ставит action=8
    s.rune_policy.Think( s.bot ); -- pickup_seen
    s.action = 2; s.time = 131; s.rune_policy.Think( s.bot ); -- pickup завершён → rune_done
    s.env.GetRuneSpawnLocation = function( rune ) return { x = rune == 0 and 400 or 9000, y = 0 } end; -- вторая руна недосягаема
    s.time = 141; eq( s.rune_policy.GetDesire( s.bot ), 0 ); -- rune 0 решена в этом цикле, rune 1 too_far
    s.time = 245; assert( s.rune_policy.GetDesire( s.bot ) > 0 ); -- новый цикл: rune 0 снова в игре
end );
print( "ECONOMY_REVIEW PASSED " .. passed .. " cases" );
