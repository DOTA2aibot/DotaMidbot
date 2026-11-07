# T007 runtime: что подключено и как провести первые игровые пробы

Owner: **Artem (GPT)**. Reviewer / игровые пробы и файл способностей: **Олег (Kimi)**.
Base: `65a7a20112b66d6f512c1092e45d39543ff7c5b8`, где PR21 и PR22 уже merged.

## Фактическое состояние

Добавлен настоящий Bot API адаптер `laning/runtime/`: collector → planner → scheduler → Action API → наблюдаемое подтверждение/timeout. Это исполнение на игровых handles, не второй симулятор. Новое поведение подключено из GetDesire/Think/OnEnd в mode_laning_nevermore.lua. GetDesire собирает наблюдения и пишет лог даже при нулевом desire.

**В Dota этот код ещё не запускался.** Default -- operation=observe: он читает данные/планирует/логирует, но не отдаёт приказов. Подключение ability hook в текущую main ещё не выполнено; файл Олега (Kimi) Artem (GPT) не изменяет. Нельзя объявлять интеграцию проверенной по наличию флага в config.

123 offline PASS = прежние 87 + 36 runtime scenarios. В том числе проверены оба пути через entry/bridge/backend: койл по крипу→тычка героя и тычка героя→койл до приземления снаряда. Включены совместимость с pinned PR23, read-only HasActivePlan и безопасная передача непрерывной AA/AttackMove после наблюдаемого release. Использовались mock handles/синтетические числа; эти PASS не подтверждают реальные API/события установленного клиента.

## Файлы и ownership

| Компонент | Что делает | Owner |
|---|---|---|
| runtime/api.lua | Защищённые reads, позиции, время, modifiers; без скрытых enemy cooldown | Artem (GPT) |
| runtime/observe.lua | Читает реальные собственные ресурсы, видимые targets/бounty/защиту, own ability values, tower range/target; handles остаются вне сериализуемых snapshots | Artem (GPT) |
| runtime/guard.lua | Двусторонний heartbeat + отдельный ACK на каждый план; TTL владения приказами | Artem (GPT); вызов hook добавляет Олег (Kimi) |
| runtime/backend.lua | Fresh validation, ограниченный поворот/позиционирование, attack_once/NO_TARGET cast, наблюдение событий, staged action masks и лог | Artem (GPT) |
| runtime/entry.lua | Подключение из lane callbacks; observe/probe/execute; отказ при отсутствующем API/hook | Artem (GPT) |
| runtime/config.lua | Режим теста, ограничения, результаты калибровки конкретного build | Artem (GPT); probe результаты сообщает Олег (Kimi) |
| advanced/bridge.lua, scheduler.lua | Acquire/release, подготовка поворота, сохранение управления во время собственного cast, ожидание настоящего evidence и cleanup | Artem (GPT) |
| ability_item_usage_nevermore.lua | Существующие способности/прокачка, integration hook | Олег (Kimi), отдельная правка |

## Обязательный hook в файле Олега (Kimi)

Проверен новый PR23 head `b0773c2e58d53ff515c4f5a8579d202324f353cb`: он уже добавляет JointExecutorOwnsBot через Bridge.IsReady. Это **ещё не нужный handshake**: IsReady означает регистрацию backend, не ACK и не владение конкретным планом. Оставить только эту проверку -- значит не запустить новый runtime; при насильственной регистрации она может постоянно отключить автономные способности. Artem (GPT) добавил запрошенный HasActivePlan как read-only status, но он тоже не заменяет AbilityGate.

Поэтому Олег (Kimi) заменяет тело существующего JointExecutorOwnsBot на вызов LaneGuard.AbilityGate(npcBot), сохраняя один существующий if в AbilityUsageThink. Если hook ещё не добавлен -- использовать фрагмент ниже. Не ставить две конкурирующие проверки подряд. При необходимости совместимости со старой сборкой import нового guard делается через pcall и без него возвращает false.

Ещё один пункт PR23: GetSoulsCount/GetRazeDebuffStacks/debug вызывают GetModifierCount. В проверенных Bot API declarations указан NumModifiers. На SDK, где есть только NumModifiers, текущие helpers падают; это воспроизведено из pinned PR23 source. Олег (Kimi) проверяет/исправляет перечисление в своём файле. Collector Artem (GPT) использует защищённый NumModifiers и не вызывает глобальные helpers PR23.

Вверху ability_item_usage_nevermore.lua:

```lua
local LaneGuard = require(GetScriptDirectory() .. "/laning/runtime/guard")
```

Внутри AbilityUsageThink сразу после GetBot и проверки nil:

```lua
local npcBot = GetBot()
if npcBot == nil or npcBot:IsNull() then return end
local laneOwnsOrders = LaneGuard.AbilityGate(npcBot)

-- Здесь остаются InitAbilities и LevelUpThink Олега (Kimi).
-- Прокачка может выполняться до уступки управления; новое решение о cast -- после неё.

if laneOwnsOrders then return end
-- Далее существующие using/channel/silence guards и выбор способностей.
```

Нужно встроить фрагмент в существующую функцию, **не создавать вторую AbilityUsageThink** и не копировать её целиком из этого документа. Вызов AbilityGate должен происходить каждый callback, включая время собственного каста, до раннего return по IsUsingAbility. В этот же файл не добавлять второй независимый combo selector. Разрешён emergency abort через текущий RETREAT и освобождение lease.

Hook требует наличия нового runtime/guard.lua. Для совместного probe Олег (Kimi) берёт ветку task/T007-runtime целиком и делает свою отдельную ветку поверх неё с изменением ability-файла. Альтернатива -- сначала merge runtime PR в режиме observe, затем отдельный PR с hook от обновлённой main. Добавлять require в старую main без этих файлов нельзя: ability callback не загрузится.

Guard не предполагает общий require-cache: lane создаёт nonce, ability callback должен увидеть его в **том же** состоянии. Затем на каждый конкретный план нужен отдельный ACK, прежде чем появится Action API вызов. При раздельных Lua states связь не подтвердится и действия останутся заблокированы. Это диагностический результат; флагом его не обходить. Тогда требуется согласованный другой способ передачи управления/данных, отдельно от этого patch.

## Последовательность проб

Менять только `laning/runtime/config.lua` и отмеченные probe поля по результатам. Для воспроизводимости после изменения режима -- новый матч/загрузка полного согласованного набора Lua; hot reload не является проверенным маршрутом. Указать run_id и build, сохранить общий commit SHA. Не смешивать файлы двух веток вручную.

### 1. Observe -- сбор данных без приказов

Сохранить operation="observe". Олег (Kimi) запускает Local Host и проверяет лог `[MIDBOT runtime]`:

- collector_unavailable -- недоступны обязательные own resource/position/time API; сначала исправить это;
- observed_no_orders -- snapshot и planning проходят, команды намеренно не отправляются;
- integration.channel_ready=true после установки hook -- callback видит общий nonce; само по себе это не ACK на план;
- hero содержит текущую ману/HP, attack_point_observed, last_attack_record/current_action_type; targets -- subtype/bounty/query estimates и modifier_probe/projectile_probe.

GetAbilityDamage не используется как итоговый урон. Own GetActualIncomingDamage query и attack proficiency -- **оценка до калибровки**, отдельно от verified effective profile. Неизвестные данные не превращаются в удобные нули. Enemy knowledge после потери видимости получает last_seen; enemy ability cooldown getters не вызываются.

### 2. Одна атака -- diagnostic probe

operation="probe_attack", stage="attacks", option_allowlist=nil. В зоне обычной атаки должен быть видимый допустимый вражеский крип; для наблюдения projectile удобнее живучая одиночная цель. Проба не гонится за вышедшей из range целью и не является стратегией фарма.

После общего heartbeat создаётся запрос владения; callback Kimi должен подтвердить **конкретный** план. Только затем `Action_AttackUnit(target,true)`. Лимит -- один атакующий приказ на экземпляр backend, даже при повторном входе в mode. Для нового probe -- новая загрузка; не повышать max_probe_orders для компенсации пропущенного evidence.

Нормальные результаты различаются:

- submit -- API вызван; это ещё не release;
- attack_released / new_own_projectile_and_attack_record -- наблюдён новый собственный projectile плюс изменившаяся own attack record;
- rejected / release_not_confirmed -- время ожидания закончилось без достаточного подтверждения. Таймер замаха не объявляет успех.

Некоторые SDK/builds не предоставляют caster/handle у tracking projectiles. Это видно в projectile_probe. Тогда одна атака может реально произойти, но подтвердить release этим источником нельзя. Олег (Kimi) сопоставляет GetLastAttackTime с реальным моментом release в установленном build. Только после такой проверки допустим `last_attack_time_release_verified=true`; evidence будет build_calibrated_last_attack_record. Если соответствие не подтверждено, поле остаётся false и нужен иной наблюдаемый источник. Само изменение timestamp не считается доказательством без этого probe.

Отдельно сверить длительность GetAttackPoint и effective attack estimate на используемых subtype/защите, включая flag/siege. Только после этого выставлять attack_point_seconds_verified / attack_damage_verified. Исчезновение/смерть цели не превращается в наш подтверждённый kill.

### 3. Один койл -- diagnostic probe

operation="probe_raze", option_allowlist=nil. Нужны изученный доступный рейз, мана и видимая цель в его геометрии. На подготовке выполняется короткое ограниченное перемещение для поворота; затем новый snapshot и IsFacingLocation + AoE revalidation. AttackMove и cast не отправляются подряд в одном callback.

`Action_UseAbility(handle)` используется только для runtime NO_TARGET behavior. Command submission не подтверждает попадание. Cast completion требует наблюдённого роста собственного CD, расхода маны и окончания ability phase/using state; это факт потребления каста, не damage/hit/kill. Высокий regen/reset/необычная cooldown семантика могут привести к консервативному timeout -- это повод сверить evidence, не включать timer-success.

Снять реальные modifier names/stack counts/duration из лога. Значения soul_modifier/raze_modifier в config -- кандидаты для установленного build; до проверки modifier_bindings_verified=false. Сверить собственные range/radius/cast point и реальное попадание, затем raze_geometry_verified=true. Cross-raze timing проверяется отдельно и по умолчанию остаётся false.

### 4. Execute и одна комбинация

После подтверждённых probes: operation="execute". Начать со stage="attacks", затем stage="raze", затем stage="combos". Неподтверждённые profile fields продолжают маскировать соответствующие действия. IDs каталога не меняются.

Для точечной проверки можно задать option_allowlist={ [6]=true } -- койл по крипу→атака героя; или { [7]=true } -- атака героя→койл по крипу. Цели должны находиться в допустимой геометрии/дальности. При такой allowlist позиционирование ID0 также выключено, поэтому перед пробой обеспечить положение героя отдельно. После проверки вернуть nil для обычного выбора.

При execute + lane_positioning=true добавлено ограниченное перемещение ID0 к собственному mid front (до250 units за шаг), чтобы без доступной атаки герой мог занимать линию. Это не rune/ward/kite executor. Проверяются passability, видимая башня и fresh safety; completion -- по фактической позиции, не по таймеру. Маршрут/дальность всё равно требуют игрового run.

Ожидаемая цепочка в логе: выбран option → ACK → submit → cast_completed/attack_released → fresh revalidation → следующий submit. Рейз может начаться, пока ранее выпущенный снаряд ещё летит. Если цель/мана/геометрия/владение изменились, план прерывается. Во время собственного каста lane сохраняет управление; RETREAT/death/опасность его освобождают. Потерявший lease код не очищает чужие команды.

## Что пока не подключено полностью

- Tower range/current target читаются; профиль урона требует отдельного tower_damage_verified. Парсер подтверждённых tower projectile impacts и полный predictor aggro ещё не включены: tower_shots остаётся unknown/пустым, а не выдуманной будущей серией.
- XP radius/recipients/factor, first-wave/rune schedule, aura dependencies и изменение защиты после смерти flag source требуют отдельных runtime bindings. Их сложные варианты остаются masked/unknown. Все эти модели/IDs сохранены для дальнейшей интеграции.
- Мана/HP врага читаются, но автоматическое распознавание его cast events/known spellbook для threat/CD estimates ещё не подключено; неизвестная готовность не трактуется как безопасное окно.
- Full trace и compact runtime log не являются готовым обучающим dataset. Probe действия помечены diagnostic_probe, reward_status=not_defined; LH/deny counters не дают причинного credit автоматически.
- Видимая башня проверяется консервативно; отсутствие наблюдения не доказывает отсутствие угрозы. Полный retreat/path planner не реализован.

## Offline проверка и передача

Из корня checkout:

```powershell
python -m pip install -r tests/laning/requirements.txt
python -X utf8 tests/laning/run_tests.py
```

Олег (Kimi) фиксирует build, общий SHA с hook, run_id/режим, точный сценарий, последовательность runtime statuses и фактический результат. Artem (GPT) разбирает wiring/planner, Олег (Kimi) -- ability API/профили. Только после коротких probes -- общая серия T009.

API-поверхность сверена с [декларациями Bot API](https://docs.moddota.com/lua_bots/); наличие метода не доказывает семантику событий в конкретном клиенте. Проверка данных профиля опирается также на [клиентский конфиг Valve](https://github.com/SteamTracking/GameTracking-Dota2/blob/b671cd08d5da5820ff0ad64fd26fcf32f615d197/game/dota/pak01_dir/scripts/npc/heroes/npc_dota_hero_nevermore.txt). Чужие реализации ботов в patch не переносились.
