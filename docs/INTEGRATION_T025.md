# T025 — воспроизводимая интеграция v0.3.6-github

Owner: **Artem (GPT)**. Reviewer: **Олег (Kimi)**. [Каноническая задача №50](https://github.com/DOTA2aibot/DotaMidbot/issues/50).
База: `0c3bf83eff62228a991e5ef4af5ded686ae96824`, после merge №51.
Статус: кандидат для независимого review и игрового теста. В этой задаче нет merge, установки и запуска матча.

## Изменения относительно main

PR №46 уже вошёл в main через №51. Его пороги, окна рун, skill build, закупочная очередь и геройские способности сохраняются. Модули №49 уже находятся в main; теперь корневой ability-файл явно подключает их через `BindLegacy(getfenv(1))`.

| Путь | Изменение |
|---|---|
| `ability_item_usage_nevermore.lua` | Только защищённый footer подключения tactical и диагностика |
| `laning/integration/actor.lua` | Проверка настоящего SF и вспомогательный учёт собственных приказов |
| `item_purchase_nevermore.lua` | Actor guard; защищённый глобальный courier-state API, method fallback при отсутствии глобального; неизвестные state/enums запрещают отправку; false не считается успехом |
| `laning/economy/mana.lua`, `runes.lua` | Actor guard; Think сохраняет тот же startup grace похода к руне, что уже используется Decide |
| `laning/observer/entry.lua`, `laning/hybrid/wards.lua` | Actor/занятость и согласование предметных/ward callbacks |
| `laning/tactical/entry.lua` | Не подключаться в диагностическом runtime или при неизвестном профиле |
| `laning/tactical/wards.lua` | Разрешить безопасный MOVE_TO, сохранив high-cliff/coverage; не перебивать rune/combat/retreat/evasion, атаки и неизвестные действия |
| `hero_selection.lua`, observer/runtime config | Идентификаторы установленной v0.3.6-github |
| `tools/package_bot.py` | Профиль `all_test`, версия пакета и инструкция |
| `tests/integration/` и существующие fixtures | Совместные callbacks, courier/identity regressions, соответствие установленным файлам |

Обычные атаки и движение на линии остаются Valve. Лесной модуль сохраняет предусмотренный короткий доворот у уже достигнутого лагеря.

Активный tactical владеет `ItemUsageThink` и ward hook: BKB/PT/clarity/mango, базовые bottle/wand/stick/flask и Requiem используют один tactical broker. Прежний item callback сохранён для отключённого tactical и предусмотренного аварийного fallback. Покупки/курьер остаются purchase callback. [ADR0008](adr/0008-tactical-hooks.md) остаётся Proposed до согласования людьми; подготовка PR не является его принятием.

## Как получить одинаковую сборку

Оба участника выбирают **один commit SHA**, профиль `all_test` и одну сборку ZIP. После merge использовать SHA merge-коммита main; до merge — SHA головы этого PR. Из чистого checkout выбранного SHA, PowerShell:

```powershell
$revision = git rev-parse HEAD
python -X utf8 tools/package_bot.py --profile all_test --revision $revision --output MIDBOT-v036-all-test.zip
```

В `MANIFEST.json` должны совпадать `source_revision`, `profile` и вся таблица `files_sha256`. ZIP-контейнеры могут отличаться временем упаковки; сравнивать игровые файлы. Патчи из установленной Dota вручную накладывать больше не нужно.

Исходный `laning/profile.lua` сохраняет default `valve_play`. Паковщик заменяет его в ZIP на выбранный `all_test`: observer/economy/wards включены, rune mode включён, lane_probe/runtime выключен. Поэтому копирование всего репозитория напрямую в игру не эквивалентно сборке по инструкции. Tactical подключается и в остальных не-диагностических профилях, но постановка вардов требует разрешения wards в профиле. `config.enabled=false` делегирует прежним callbacks.

Установку выполнять после закрытия Dota с резервной копией полной папки `bots`; не накладывать новую сборку поверх старого диагностического mode_laning. Установленная папка игры этим PR не меняется.

### Соответствие установленному варианту

На машине Artem до PR установлены 51 Lua-файл, версия `v0.3.6-github`, fingerprint `4850e41a29`, исторический revision `main-ab5a2aa-r46-556717f-i2`. Тест `test_package_parity.py` подтверждает байтовое совпадение всех 51 файлов при использовании этого исторического revision. SHA256 сохранены в `tests/integration/installed_v036.json`.

Новая обычная сборка должна использовать **свой настоящий SHA**, а не старый revision: изменится provenance в генерируемом `laning/profile.lua`; остальные 50 игровых файлов совпадут с установленными. Старый source-текст bootstrap-сообщения сохранён для точного соответствия тестируемому коду; это историческая метка интеграции, не текущая Git HEAD. Актуальный источник проверять по manifest/profile.

## Проверки

Нужен Python development environment с `lupa.lua51`; в игре Python/Lupa не нужны. Из корня checkout:

```powershell
python -X utf8 tests/laning/run_tests.py
python -X utf8 tests/tactical/run_tests.py (Resolve-Path ability_item_usage_nevermore.lua).Path
python -X utf8 tests/integration/run_v036.py
python -X utf8 tests/integration/test_package_parity.py
python -X utf8 tests/social/run_tests.py
python -X utf8 tests/tactical/test_attachment.py
python -X utf8 tests/tactical/check_checkouts.py
```

В среде Artem `.task-tools` задаётся через PYTHONPATH из родительской рабочей папки. Это локальная development-зависимость, не часть бота.

Кандидат: baseline307 (включая packages16, observer/report, economy32+review17, purchase19); tactical82 на реальном root; combined15; social23; attachment4; package parity3; Lua5.1 compile всех Lua. LF/CRLF проверяются отдельным checkout runner. API mocks не подтверждают силу бота или механику живого клиента.

## Следующий игровой тест

Новый локальный матч 15–20 минут на выбранном SHA с полным console log. Записать version/profile/source_revision; проверить `[MIDBOT tactical] attached` и отсутствие повторяющихся Lua/helper ошибок. Проверить добивания/farm, руны 2/4/6/8 минут, high-ground observer, BKB/PT/ману, отмену собственного Requiem и отказ от старта по иллюзии. Смотреть реальные cooldown/modifier/заряды/entities, а не только `submitted`.

Не заявлены исправленными: незавершённые сборки предметов/очистка backpack, все активные предметы, фактический LOS варда текущей карты, дополнительный bot-slot fill, руны после существующей границы15:00. Длинные старые observer JSON могут фрагментироваться: сохранять полный log вместе с bounded tactical events. Новый матч здесь не запускался; задача остаётся Review до независимой проверки и игровых AC.
