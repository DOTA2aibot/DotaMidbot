# T016 × T007: интерфейс передачи управления способностями

Статус: **предложение kimi, ждёт подтверждения GPT**. По плану следующего этапа (п.4):
в каждый момент приказы атак/способностей выдаёт один исполнитель.

## Принцип

- Единственный владелец приказов — scheduler T007 (`laning/advanced/bridge.lua`).
- `ability_item_usage_nevermore.lua` (этот модуль) становится **библиотекой способностей**:
  backend вызывает Consider-функции и кастует через них, сам модуль приказов не выдаёт.
- Прокачка (`LevelUpThink`) НЕ передаётся: `ActionImmediate_LevelAbility` не боевой приказ,
  конфликтов с scheduler нет. Остаётся в этом модуле и работает всегда.

## Механика уступки (реализовано по ревью GPT к PR #23)

В начале `AbilityUsageThink` (после `LevelUpThink`, ДО раннего return по `IsUsingAbility`):

```lua
if ( JointExecutorOwnsBot( npcBot ) ) then return end;
```

`JointExecutorOwnsBot` делает lazy `pcall(require, ".../laning/runtime/guard")` и вызывает
`LaneGuard.AbilityGate( npcBot )` каждый callback — этот вызов одновременно является
heartbeat ability-стороны (nonce-канал lane↔ability). Gate возвращает true только пока
lease конкретного плана жив (TTL) и подтверждён ACK; между планами автономная логика
способностей работает как раньше. Emergency: при RETREAT/смерти guard сам освобождает lease.

**Обратная совместимость**: без `laning/runtime/guard.lua` (старая сборка) require
падает в pcall → модуль полностью автономен.

## Что модуль способностей экспортирует backend'у (все функции глобальные)

| Функция | Назначение |
|---|---|
| `ConsiderRazeOnHero( bot )` → desire, loc, ability | скоринг каста по герою (+крипы в зоне) |
| `ConsiderRazeOnCreeps( bot )` → desire, loc, ability | дальний крип / вышка / добивание / пачка |
| `ConsiderRequiem( bot )` → desire, target | добивание / отпорка ультой |
| `CastRaze( bot, ability, loc )` | no-target каст с проверкой ФАКТИЧЕСКОГО центра удара: каст только если `Dist2D(loc, центр по текущему GetFacing()) <= 250-40`; иначе доворот коротким шагом 48 ед. через `Action_MoveDirectly` (throttle 0.15с, guards: RETREAT / вышка 750 / IsLocationPassable). Допуск 20° и движение до цели УБРАНЫ по ревью GPT |
| `GetRazeIndexOf( ability )` → 1..3\|nil | индекс рейза по хендлу способности (для геометрии) |
| `GetCurrentRazeImpact( bot, i )` → vector | фактический центр удара i-го рейза при текущем направлении взгляда |
| `GetRazeImpactPoint( bot, target, i )` → vector | геометрия: центр удара i-го рейза (200/450/700, радиус 250) при взгляде на target |
| `EffectiveRazeDamage( rawDamage, unit )` → number | урон с магрезистами (герои ×0.75, siege ×0.20) |
| `GetSoulsCount( bot )` → number\|nil | души Necromastery (стаки модификатора) |
| `GetRazeDebuffStacks( enemy )` → stacks\|nil, name | стаки дебаффа рейзов на враге (амплифай) |
| `LevelUpThink( bot )` | прокачка (вызывать не нужно — модуль делает сам) |

Backend НЕ должен вызывать `Action_UseAbilityOnLocation` для рейзов напрямую — только
через `CastRaze` (рейзы no-target, кастуются по направлению взгляда).

Диагностика ошибок: `AbilityUsageThink` обёрнут в `xpcall`; traceback получается через
защищённый вызов (`pcall` + проверка `debug.traceback`), поэтому исходный текст ошибки
сохраняется всегда — падение самого обработчика («error in error handling») исключено.
Ошибки печатаются как `[MIDBOT ability ERROR] <текст> | <traceback>`.

## Открытые вопросы к игровой проверке (п.3 плана)

1. Имена модификаторов в текущем патче: `modifier_nevermore_necromastery`,
   `modifier_nevermore_shadowraze_debuff` — предположения. Включить
   `MIDBOT_DEBUG_MODIFIERS = true` (в конце ability_item_usage_nevermore.lua),
   короткий запуск, консоль покажет реальные имена → поправим константы.
2. Поворот перед кастом: `AttackMove` + `UseAbility` в одном тике — подтверждено паттерном
   эталонного `bot_nevermore` Valve (workshop 838589409), в игре Олегом подтверждено
   08.11 (рейзы работают). Точное время разворота — отдельный probe при необходимости.
3. `GetAbilityDamage` рейза уже включает бонус от стаков дебаффа или нет — проверить
   в игре: урон по тому же крипу вторым подряд рейзом.

## Граница файлов (по плану)

- kimi: `ability_item_usage_nevermore.lua`, `tests/abilities/`, этот документ.
- GPT: `laning/`, `mode_laning_nevermore.lua`, `tests/laning/`.
- `item_purchase_nevermore.lua` — отдельная правка только после согласования.
