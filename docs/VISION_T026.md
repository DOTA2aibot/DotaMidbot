# T026 — Observer Radiant mid / v0.3.8-ward-phase

Owner Artem (GPT), reviewer Олег (Kimi). Issue54 / PR55, кандидат без merge.
Инструкции текущей версии заменяют прежний grid-поиск v0.3.7.

## Что показал последний тест

Локальный log9082482731 действительно на test53-f4b3f3a-55-f2b51d0-testteam.
446 snapshots до6:13, LH7/deny5/K0/D1, без Lua/helper errors и malformed observer JSON.
Стартовый Observer куплен, но ward_plan/order/placement отсутствуют.9 отказов поиска
no_radiant_bank_rune_view_candidate; другие причины — enemy18, native-action12,
priority-mode6 и прочие. Отдельного доказательства native interruption нет.
Руны:46order/7cancel/1done, причём done не доказывает pickup. Ветки рун не меняются.

## Новое поведение

Artem передал тестовую точку **X=-197,Y=-1003**. Site использует только эти XY;
при наличии GetGroundHeight берёт Z от клиента, требует известный GetHeightLevel.
Не ищет другую точку, не требует совпадения с прежним grid/tree-model и не выдаёт
координату за гарантированный rune LOS. В плане сохраняется ближайшая power-rune,
номинальная дальность и явное coverage=user_coordinate_visibility_unverified.
После постановки лог показывает реальную высоту, team rune_visible/mid_visible и
vision_radius. Team visibility может быть обеспечена союзниками, это не exclusive
credit нового варда. Если точка не даёт нужного обзора, Artem передаёт другую XY.

Один Observer после Tango в стартовом закупе, sentry отсутствует. Courier прежний.
Supply считает inventory/backpack/stash/own courier, не дублирует pending unknown
и готовит максимум один запас за30с до известного360с истечения. Когда вард уничтожен,
можно купить запас заранее, но постановка всё равно ждёт открытого окна.
После15:00, вне Radiant mid или у иллюзии пополнения/новой фазы нет.

Окна: сначала с-90с (до первой пачки), затем с330с/690с — **5:30/11:30**.
Это due-time, не приказ бросить фарм. Если первая возможность пропущена, попытка
ждёт свободной линии; недоступный ранний слот не накапливает несколько вардов.
Одно подтверждение закрывает текущий слот. Живой Observer в точке всегда блокирует
новый. Если старый ещё жив в5:30, бот дождётся исчезновения; раньше не заменяет.

## Приоритет и владение

Только ward-профили получают личный mode_ward_nevermore.lua и ward_phase_enabled.
GetDesire ничего не приказывает. Перед входом: realSF/Radiant/alive/on-mid,
HP>=70%,3с без урона героя, active Observer ready; idle/none/move, без очереди/cast;
нет видимого enemy рядом с SF или целью, вражеских lane creeps в1100,
доступного deny в800, опасной башни, attack/retreat/evasion/rune режима.
Новая фаза не начинается также за20с до и20с после двухминутного rune spawn.
Это ограничение только вардинга, policy рун Олега не редактируется.

Короткий режим держит владение, пока безопасно: максимум8с и1000ед подхода сверх
cast range. Путь использует Action_MoveToLocation в проходимую точку внутри range;
не пытается идти на непроходимый cliff. Нет прогресса2с → exit. Приказы движения
не чаще0.6с; отмена даёт15с cooldown. Появление farm/enemy/retreat/rune/низкихHP/unknown
сразу освобождает фазу. Нет ClearActions на выходе, чужой новый приказ не стирается.

Обычные own PT/regen/spells временно уступают уже выбранному ward-mode; emergency
BKB приоритетнее и отменяет lease. Observer продолжает запись. Прежний executor
единственный вызывает itemcast и Poll подтверждает новую entity+потраченный заряд
(или consumed owned single-use item). Нет readback за3с → unknown и release,
а не успех/бесконечный повтор. После exit обычные режимы снова выбирает Valve.
Backpack swap ограничен Observer и прежним whitelist, ждёт реального cooldown
до старта фазы, BKB/PT не вытесняются. Общая inventory cleanup не добавляется.

all_test также содержит согласованные простые союзные закупы без вардов и Tango.
Пакет назначать ТОЛЬКО команде SF, противнику Valve/default. Это собственные союзные
сборки, не selective native filter и не обещание C++ shopping fallback.

## Проверки и следующий игровой run

Разработческая среда Python/Lupa Lua5.1; в игре эти зависимости не нужны.
Команды из корня исходников:

```powershell
python -X utf8 tests/vision/run_tests.py
python -X utf8 tests/laning/run_tests.py
python -X utf8 tests/tactical/run_tests.py (Resolve-Path ability_item_usage_nevermore.lua).Path
python -X utf8 tests/integration/run_v036.py
python -X utf8 tests/integration/test_package_parity.py
python -X utf8 tests/testing/run_tests.py
python -X utf8 tests/testing/test_package.py
python -X utf8 tests/social/run_tests.py
```

Live AC: новый матч Radiant mid с новым source_revision. Увидеть первый Observer
в указанной точке; нет микрошагов/остановки фарма; ward_phase_start → bounded
approach/order → ward_placement_observed → ward_phase_end placement_confirmed.
Проверить view руны и мида, повторные окна5:30/11:30, задержку при крипах/бое/руне,
немедленный abort при угрозе, возврат к обычной игре и отсутствие Lua/helper errors.
Если source_revision старый, этот патч в матче не проверялся. Если outcome_unknown,
это не успешная постановка. Mode dispatch/pathing/LOS/FPS требуют live run;
мок-тесты их не подтверждают. Независимое review и game AC до Done остаются.
См. Proposed ADR0009; архив старого51Lua reference сохраняется без изменений.
