# Проверка перед интеграцией: PR #21 + локальный T007

Проверено 2026-11-07. **Рекомендация относится к проверенному head PR #21 ниже; T007 подготовлен к публикации для code review, игровой релиз не подготовлен.** Это code/offline review конкретных SHA, не результат игрового прогона. После обновления PR нужно повторно проверить новый head, не переносить эту рекомендацию автоматически.

## Зафиксированные версии

- main: `ae1166da294e3854a41ecface1d9936ca5030b2c` (покупки T017 merged).
- Новый [PR #21](https://github.com/DOTA2aibot/DotaMidbot/pull/21): head `5456b9e8959fadc87d94762e524a7dcefcb3534d`, branch task/T016-abilities; base та же main.
- От прошлого проверенного `d0d0c3e...` добавлен один commit: mode gate для фарма и изменения закупки. Предыдущие спорные cast/damage/pack места всё ещё присутствуют.
- В PR изменены только ability_item_usage_nevermore.lua, item_purchase_nevermore.lua, docs/MID_GUIDE.md. Локальные T007 mode/helper/hero_selection не заменялись этой веткой.
- В PR написано, что Олег проверял прокачку и покупки в игре; последний fix mode gate/ступора ожидает перетеста. Это сообщение автора, не наши независимо подтверждённые результаты нового head.

## Findings

### P1 — очередь останавливается на бесплатном observer ward

[item_purchase_nevermore.lua:112](https://github.com/DOTA2aibot/DotaMidbot/blob/5456b9e8959fadc87d94762e524a7dcefcb3534d/item_purchase_nevermore.lua#L112) считает cost<=0 ошибкой. Новый build ставит observer вторым. В [items.txt Valve](https://github.com/SteamTracking/GameTracking-Dota2/blob/b671cd08d5da5820ff0ad64fd26fcf32f615d197/game/dota/pak01_dir/scripts/npc/items.txt) observer ItemCost=0. На 50 ticks после успешного tango ни observer, ни следующий предмет не вызываются; лог blocked: invalid cost. Счётчик 20 отказов находится после purchase API и не помогает.

Требуется различить допустимую нулевую цену и невалидный item/query; добавить реальные сценарии free observer + stock state. Просто скипнуть всё с cost=0 -- потерять вард, не исправить покупку.

### P1 — рейзы подаются как location-targeted spell

[ability_item_usage_nevermore.lua:117](https://github.com/DOTA2aibot/DotaMidbot/blob/5456b9e8959fadc87d94762e524a7dcefcb3534d/ability_item_usage_nevermore.lua#L117) и строка 125 по-прежнему используют Action_UseAbilityOnLocation. Профиль Valve указывает NO_TARGET; Bot API различает Action_UseAbility и location-targeted вызов. Reproduction подтверждает выбор location API, а не фактическое поведение клиента. Нужны корректная ориентация героя, no-target cast и короткий probe; не считать target point автоматическим поворотом.

### P1 — сырое GetAbilityDamage принимается за итоговый урон по любому крипу

[ability_item_usage_nevermore.lua:305](https://github.com/DOTA2aibot/DotaMidbot/blob/5456b9e8959fadc87d94762e524a7dcefcb3534d/ability_item_usage_nevermore.lua#L305), аналогично hero-путь строка 223. Нет явного target-stack/souls/effective protection расчёта. При synthetic raw=60, actual=12, HP=50 код выбирает secure. Это не подтвердит убийство защищённого flag/siege. Getter текущего raw может также не содержать всех AbilityValues.

В [строке 324](https://github.com/DOTA2aibot/DotaMidbot/blob/5456b9e8959fadc87d94762e524a7dcefcb3534d/ability_item_usage_nevermore.lua#L324) attack range>200 одновременно помечает ranged creep и siege как одну приоритетную группу. Нужны отдельный subtype и индивидуальный damage query; HP/bounty тоже читать отдельно.

### P2 — pack count суммирует цели из разных направлений

[ability_item_usage_nevermore.lua:318](https://github.com/DOTA2aibot/DotaMidbot/blob/5456b9e8959fadc87d94762e524a7dcefcb3534d/ability_item_usage_nevermore.lua#L318): для каждого крипа считается свой vImpact, счётчик общий, выбран последний packCenter. Три крипа на окружности в направлениях 0/120/240° дают pack=3, но одна выбранная область содержит только одного. В hero-пути используется общий impact; исправление туда не означает исправленного creep-пути.

Нужно выбирать один центр и считать все цели относительно него. Эта логика уже есть в локальном T007 planner; не держать две расходящиеся копии расчёта.

### P2 — 20 временных отказов удаляют весь целевой предмет

[item_purchase_nevermore.lua:141](https://github.com/DOTA2aibot/DotaMidbot/blob/5456b9e8959fadc87d94762e524a7dcefcb3534d/item_purchase_nevermore.lua#L141): после 20 ответов с временной причиной очередь необратимо теряет target. Проба подтверждает переход tango→observer без успешной покупки. Для большого предмета можно потерять оставшиеся компоненты, уже оплатив часть сборки. Нехватка золота до API отдельно ожидается без счётчика; проблема относится к повторным отказам самого API (например, временно неподходящие условия).

Нужны отложенный retry/backoff, различие постоянных/временных причин, политика restock и явный статус skipped, а не универсальное удаление target. Это изменение семантики принятой T017; безопасно согласовать отдельно и расширить purchase tests. Строка заголовка «только после подтверждённой покупки» уже не описывает код.

### P2 — build прокачки неполный, комментарии обещают больше кода

[ability_item_usage_nevermore.lua:36](https://github.com/DOTA2aibot/DotaMidbot/blob/5456b9e8959fadc87d94762e524a7dcefcb3534d/ability_item_usage_nevermore.lua#L36): указаны четыре upgrades рейза и один Requiem. CanAbilityBeUpgraded защищает от запрещённого upgrade, но не выбирает альтернативную способность. Если перечисленное недоступно, функция ничего не тратит. После достижения перечисленных рангов нет aura/Feast/talents/следующих рангов ultimate. Комментарии «рейзы максимум на 1–4» и «потратит default AI» не доказывают такое исполнение. Нужно сверить допустимые уровни в установленном build и явный fallback/callback.

## Что исправлено / какие замечания сняты

- Новый mode blacklist действительно разрешает creep-ветку под DEFEND_TOWER_MID; это устраняет старый whitelist gate. Само попадание/урон этим не подтверждены.
- Hero+creep scoring уже проверяет одну общую область для данного hero aim; creep pack-путь всё ещё отдельный и ошибочный.
- **Прежнее сомнение про GetVelocity снято:** метод задокументирован в [Bot API](https://docs.moddota.com/lua_bots/), возвращает скорость за прошлые две секунды. Линейное упреждение всё равно не гарантирует попадание.

## Пересечения T007/T016

Прямого файлового конфликта с новым lane/helper draft сейчас нет, но смысловое дублирование есть: оба слоя выбирают creep/hero cast и оценивают AoE/урон. Независимая AbilityUsageThink PR #21 не проверяет joint lease и может перебить план T007. Единый arbiter/backend отсутствует; складывание папок не является интеграцией. Расчёт combo/защиты следует переиспользовать из согласованного helper, а не копировать в оба места.

Purchase-правка PR относится к уже принятой T017. В этом аудите исходники Олега сохранены только в tests/laning/audit_sources; main и его branch не редактировались. PR также предлагает будущий bump v0.3, тогда как текущая общая договорённость -- серия v0.2; номер надо согласовать при T009, не менять параллельно.

## Воспроизводимость и границы

```powershell
python -m pip install -r tests/laning/requirements.txt
python -X utf8 tests/laning/run_release_audit.py
```

Шесть REPRO_CONFIRMED -- подтверждения воспроизведения описанного поведения, **не шесть успешных acceptance tests PR**. Файлы проверяются по Git blob SHA: ability b984c38cf1fb901399209f49ccab7899fe843aea, purchase 21012c5531fe1748c93294c131defcc05c721c69. Harness запускает реальные функции snapshot в изолированном Lua 5.1 окружении. Числа HP/damage -- synthetic fixtures; API submission probe не доказывает, что клиент отклонит вызов.

Отдельно: исходные 17 purchase regressions T017 проходят на принятом исходнике T017. Это не blanket pass новой изменённой очереди PR #21; старые проверки привязаны и к прежнему порядку item build. Игровые проверки PR/T007 в этой сессии не выполнялись. Перед merge нужен исправленный head и повторная проверка именно его SHA, затем совместная интеграция и общий игровой прогон.
