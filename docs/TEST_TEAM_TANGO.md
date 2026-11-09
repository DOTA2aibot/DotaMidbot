# Тестовые союзники без вардов и Tango

T026 / [Issue54](https://github.com/DOTA2aibot/DotaMidbot/issues/54), owner **Artem (GPT)**, reviewer **Олег (Kimi)**. Пользователь выбрал простые собственные сборки союзников, признавая их отличие от Valve. Это тестовый стенд, не новый обычный baseline матча.

## Запрет покупки вардов союзниками

Только профиль `all_test` включает `ally_ward_free_shop=true` и корневой `item_purchase_generic.lua` из `profiles/all_test`. Он заменяет native ItemPurchaseThink для non-SF ботов скриптовой команды. Персональный `item_purchase_nevermore.lua` остаётся отдельным, со стартовым Observer и replenishment.

**В лобби выбрать этот пакет только для команды контролируемого SF. Для противника — Valve/default.** У callback нет подтверждённого способа вызвать обратно нативный C++ закуп. Если пакет ошибочно назначен команде без bot-SF, модуль пишет wrong_scripted_team_no_sf и не покупает; это не native fallback. Нельзя утверждать, что он сохраняет закуп врагов при использовании одного пакета обеими командами.

`laning/testing/ally_shop.lua` содержит отдельные небольшие plans для Juggernaut, Bristleback, Lion, Crystal Maiden и общий fallback для остальных героев, которых движок мог добавить в solo mid. Все targets и рекурсивные recipe leaves запрещают Observer, Sentry и Dispenser. Остальные покупки продолжаются: расходники, ботинки, wand, базовые carry/tank/support предметы. Рецепты берутся из текущего клиента; купленные компоненты не повторяются после принятого SUCCESS. Инвентарь/стэш/свой courier учитываются; courier delivery ограничена собственным ID и idle/base state. Неизвестный purchase outcome не повторяет трату до наблюдения. Временные shop failures откладывают цель, invalid/disallowed пропускают её. Отдельного похода героя/курьера в secret shop или общего inventory cleanup в этом стенде нет.

Логи `[MIDBOT ally_shop]` содержат actor, component и reason. Команда SF не покупает варды этим модулем, но это не запрет на ручную передачу предмета человеком/читом. Другие профили не получают generic purchase entry и продолжают прежний native shopping.

Результаты матчей с этим стендом нельзя напрямую смешивать с обычной командой Valve: изменились сборки союзников. Движение, атаки и обычные способности союзников остаются движку.

## Tango SF

`tactical/tango.lua` вызывается из существующего item owner после emergency wand/BKB/mana/bottle/salve checks. Он использует **Action_UseAbilityOnTree(item, treeID)**, не cast на себя или координату.

Текущий baseline: HP<85% и нехватка≥90HP, активный Tango/Tango single с зарядом, нет tango/flask/bottle regeneration и близкой fountain regen. Выбирается ближайшее дерево в реальном GetCastRange с небольшим запасом. Нет приказа идти к дереву; дальнее/неизвестное дерево отклоняется. Не прерываются атака, каст, канал, очередь и pending ward. Общий broker ограничивает количество своих приказов; наблюдение заряда пишет resource_change_observed, а само order_attempt не считается лечением.

Tango в backpack не применяется оттуда и не перекладывается этим небольшим исправлением. Это отдельное ограничение для будущей inventory задачи.

Механика и API: [Dotabuff Tango](https://www.dotabuff.com/items/tango), [ModDota Bot API](https://docs.moddota.com/lua_bots/). Значения текущего tooltip на2026-11-09: tree range165; для применения код читает live GetCastRange, не использует жёсткое165.

## Актуальность53 и последний лог

Аудит установленной папки: все56 Lua соответствовали manifest `test53-48dafb8-55-1bfa6f1`; PR53 был старым48dafb8. Актуальный на момент аудита PR53 — ac729cb87269a2d55e371b7f4dcb5528075ce5ee. В нём добавлены MoveTo approach перед близким PickUp и deadline/продление; rune policy принадлежит Олегу и в этом PR не переписывается.

Последний доступный лог9082456112 относится ещё к `test53-48dafb8-55-7a976f0`, до возврата стартового Observer. В нём 116rune_order,16rune_cancel,1rune_done; last snapshot609.07с, LH45/deny20/K1/D0, Lua ошибок не найдено. Rune order — отправка приказа, не подтверждение похода/подбора. Ward purchase attempts нет; vision_supply_skip содержит radiant_bank_geometry_unknown. Лог не доказывает, что в этом запуске именно союзники исчерпали stock. Запрет союзникам реализован по прямому поручению, а geometry gate исправлен отдельно по воспроизведённому случаю.

## Проверки и игровой шаг

```powershell
python -X utf8 tests/testing/run_tests.py
python -X utf8 tests/testing/test_package.py
python -X utf8 tests/vision/run_tests.py
python -X utf8 tests/laning/run_tests.py
python -X utf8 tests/tactical/run_tests.py (Resolve-Path ability_item_usage_nevermore.lua).Path
```

API mocks не доказывают фактическую работу client callback, лечение, обзор, отсутствие ward-покупок нативным кодом или FPS. Нужен новый Radiant test с правильными team scripts: увидеть ally_shop events без ward items, стартовый Observer SF, ward_plan/placement/rune_visible и Tango tree charge/regen modifier. Полный лог и manifest нужны для атрибуции новой сборки.
