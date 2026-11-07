# Предлагаемый контракт T007 ↔ T016 — для совместного ревью перед интеграцией

Основание: Артём расширил T007 до комбинированных планов, не независимых ordinary attacks. Способности/прокачка остаются у стороны Олега; его файл в ветке T016 **не изменён**. Это предложение интерфейса, не выданное за принятое обоими решение.

## Обнаруженные места для сверки в T016

Обновлённая проверка PR #21, commit `5456b9e8959fadc87d94762e524a7dcefcb3534d`; подробности и воспроизведения -- [RELEASE_AUDIT](RELEASE_AUDIT.md):

- Гайд найден в docs/MID_GUIDE.md, не main.
- Вызовы рейза всё ещё `Action_UseAbilityOnLocation`, хотя конфиг Valve говорит NO_TARGET. Требуется корректный поворот и no-target cast, а не предположение, что передача точки поворачивает героя.
- Прежнее сомнение про GetVelocity снято: метод найден в Bot API; точность линейного упреждения всё равно требует проверки.
- Damage берётся через GetAbilityDamage без явных soul/target-stack/защиты. Для текущих AbilityValues нельзя предполагать, что этот getter возвращает весь итоговый урон.
- Счётчик group-hit в creep-пути увеличивается при разных направлениях потенциального каста; надо проверять все цели относительно **одного** выбранного impact point.
- Комментарий skill order «рейзы максимум на 1–4 уровнях» не следует автоматически из CanAbilityBeUpgraded. Цикл проверяет upgrade, но альтернативное распределение очков при недоступном следующем уровне рейза не определено явно. Проверить допустимые уровни/очки и фактический callback, не считать комментарий работающим build.

Это пункты ревью, не разрешение GPT переписать файл Олега.

## Backend, который требуется подключить

```lua
local Bridge = require(GetScriptDirectory() .. "/laning/advanced/bridge")
Bridge.Register(bot:GetPlayerID(), {
    schema = "sf-lane-options-0.2-draft3",
    joint_executor_verified = true, -- только ПОСЛЕ проверки shared state и владельца приказов
    Snapshot = function(bot) ... end,
    Validate = function(bot, step, snapshot) ... end,
    Submit = function(bot, order) ... end,
    Events = function(bot) ... end,
    Record = function(snapshot, planning, event) ... end,
})
```

Snippet — спецификация с пропусками, не runnable-код. Пока backend нет, Bridge возвращает awaiting_T016_backend/нулевой desire. Нельзя просто выставить true без реализации и проверки.

### Snapshot

Только JSON-совместимые данные: run/build/observation IDs/time; свои HP/мана/уровень/души/max/статы/тайминги/предметы и валидность buffs; видимые targets с ID, координатами, наблюдённой скоростью/HP bounds/текущим effective attack damage/защитой; точные собственные ability cooldown/mana/profile; known target stacks/expiry; enemy_knowledge с provenance/unknown; wave/rune observation; scenario schedule_verified.

Не включать enemy ability handle или получить «точный» скрытый cooldown, даже если какой-то engine API технически его возвращает. Targets под fog получают last_seen в knowledge, а не сохраняются как текущие доступные цели.

Draft 3: отдельные creep_type/variant/unit_name, текущие bounty_gold_min/max и bounty_xp; эффективные damage queries, зависимости от flag sources/linger/new defense states. Собственные mana_regen/alive/xp_needed_to_level; xp_rules и verified recipients/factor; visible_forecast ожидаемых смертей. Towers с range/current target/эффективным damage по каждой цели, выпущенные projectiles с attack IDs и проверенными impact times. Условные future hit counts не смешивать с реальными incoming shots. Детали полей/ограничений: [CREEPS_XP](CREEPS_XP.md).

### Validate

Возвращает свежие time/snapshot_time, emergency/casting/attack_windup, valid_targets, ability_ready, facing_ready и geometry_valid **для текущего шага**. Учитывает реальную ману, range/AoE, disabled/silenced, target death/visibility. No target callback не освобождает от проверки направления. Для шагов observe/завершения plan step может быть nil.

### Submit

Сопоставляет фиксированный enum разрешённому API: attack_once → Action_AttackUnit(...,true), raze → проверенный Action_UseAbility(handle). Никакого исполняемого текста из модели. Возвращает только факт подачи/отказа, не «попал».

Один actor — один backend/lease. Во время joint plan независимая AbilityUsageThink не должна сама выбирать новый каст. При аварии разрешён явный abort с причиной; emergency retreat не ждёт завершения атакующей комбинации. Регистрация backend/memory между двумя скриптами должна быть проверена в игре; require-cache между разными Lua-state не предполагается автоматически.

### Events

Список новых событий с actor/plan_id/step_id и status: attack_released, cast_completed, cancelled, rejected. API-submitted не подтверждает release. Нужно проверить доступный источник release/complete; один таймер/истечение windup — только оценка, не достаточное доказательство. Combat damage/kill подтверждается отдельным событием и не следует из release.

`plan_id` надо возвращать из конкретного Submit: это уникальный ID исполнения, не стабильный `candidate_key`. Повторная попытка той же комбинации получает новый ID, иначе запоздалое событие старого исполнения могло бы продвинуть новое. После перезапуска backend очищает очередь старых событий; ID локален сессии scheduler.

### Record

Вызывает advanced trace.Record/Encode и подтверждённый sink. Ошибка записи не должна менять action-state; Bridge защищает вызов pcall, но полноту/потери лога должен учесть collector. Снимки не должны содержать userdata/functions. Выполненный plan имеет outcome=not_attributed до combat collector.

## Порядок интеграции

1. Согласовать контракт и точные files, сохранить раздельные ownership T007/T016.
2. Сверить данные и callback в установленном build; отдельно проверить cross-raze cooldown (есть неоднозначное поле shadowraze_cooldown) и времена поворота/release.
3. Подключить backend в отдельной ветке/PR; не переносить чужие незавершённые правки молча.
4. Короткие тесты одного attack, одного raze, атака→рейз по разным целям, два рейза/expiry/cancel, общий runtime/replay log.
5. После этого — общая серия v0.2. Нынешние offline-тесты подтверждают протокол/математику fixtures, не весь игровой контур.
