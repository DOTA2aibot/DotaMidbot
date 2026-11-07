# T007 draft 3: варианты игровых планов вместо фиксированной очереди правил

**Статус:** планировщик PR22 merged; runtime continuation реализует настоящий collector/executor в laning/runtime. Default observe, приказы -- только после hook Олега (Kimi)/ACK и staged probe. Игрового run пока нет. Порядок: [INTEGRATION_TEST](INTEGRATION_TEST.md). Предыдущий primitive draft superseded, тесты оставлены для регрессии.

## Что теперь выбирает policy

`каталог plan options → параметризация наблюдаемыми целями/рейзами → action masks → признаки прогноза → выбор плана → подтверждённые шаги → перепроверка/replan`.

ML позже может заменить только функцию выбора/ранжирования при том же observation/action schema. Это уменьшает будущую переделку интерфейсов, но не гарантирует отсутствие дообучения, нового action-space version или ошибок переноса. Сейчас обучения нет.

## Каталог с постоянными IDs

| ID | Семейство | Реализовано сейчас |
|---|---|---|
| 0 | Удерживать волну / наблюдать | candidate |
| 1 | Добивание обычной атакой | candidate + forecast |
| 2 | Добивание рейзом | candidate + forecast, runtime mask без T016 backend |
| 3 | Атака → рейз | timeline: сначала release, затем cast; попадания могут идти в другом порядке |
| 4 | Рейз → атака | forecast + scheduler |
| 5 | Один AoE по крипам и герою | считаются все цели в одной окружности |
| 6 | Добить рейзом → ударить героя | разные цели в одном плане |
| 7 | Ударить героя → добить рейзом | полёт снаряда может совмещаться с cast |
| 8 | Два/три рейза по одной цели | стаки, expiry, мана, отдельные cooldown; дополнительный timing probe required |
| 9 | Deny обычной атакой | eligibility и forecast |
| 10 | Пуш обычными атаками | только при контекстном разрешении wave strategy |
| 11 | Пуш рейзом и атакой | context + forecast |
| 12 | Контроль/подбор руны | ID/schema есть, movement/pickup backend pending |
| 13 | Сохранить ресурсы | candidate |
| 14 | Прервать план / отдать управление | emergency path |
| 15–16 | Ward/deward под обзор/руну | только каталог и явные маски pending |
| 17 | Обычный harass | candidate |
| 18 | Удар → kite | каталог; movement backend pending |
| 19 | Перестроить позицию под рейз | каталог; geometry/movement backend pending |
| 20 | Deny → secure | каталог; predictor второго окна pending |
| 21 | Сохранить известное XP-окно | observe + отдельный passive XP forecast |
| 22 | Вернуть позицию для XP | movement backend pending |
| 23 | Дождаться tower projectile → AA | forecast по наблюдаемым снарядам + настоящий scheduler wait |
| 24 | Подготовить крипа → вышка → AA | условный forecast; execution masked до target-lock/second-attack predictor |

ID не уплотняются при недоступности. У каждого candidate есть target/ability параметры и `candidate_key`. Маска объясняет mana/cooldown/visibility/geometry/profile/integration ограничения. Название «secure» обозначает намерение, а не обещание добивания. Горизонт ограничен 4 s и 3 шагами; это полезное подмножество механик, не все возможные Dota-последовательности.

## Почему нет «одновременно двух приказов»

Герой имеет один контур приказов. Атака может выпустить снаряд, затем начинается рейз, пока снаряд летит. Планировщик строит timeline выпуска и попаданий, сортирует damage events по времени. Scheduler не разрешает cast по одному API-submitted: нужен `attack_released`. После рейза для следующего шага нужен `cast_completed`. Любое cancel/reject/потеря цели/мана/CD/геометрия → abort/replan.

Прогноз не подтверждает фактическое исполнение. Одни таймеры не доказывают, что атака выпустила снаряд. Между callbacks T007 и T016 должен быть один owner/lease героя; этот handshake требует игрового probe.

## Пересмотр прежних правил

- Убрано глобальное «нельзя пушить»: wave.lua различает equilibrium, гонку за 2 lvl, pre-rune clear и видимую siege-pressure.
- Нет жёсткого «сначала любой last-hit, потом любой harass»: единый plan может решать оба. Baseline оценивает вектор предполагаемых целей/урона/маны/риска/времени, позднее ML выбирает среди тех же вариантов.
- HP/мана/CD противника влияют на оценку угрозы с явным unknown. Недоступность одного spell не означает безопасный размен.
- Отправка attack/cast не считается добиванием. Прогнозируемые damage/kills не являются reward.

## Модули

| Модуль в laning/advanced | Ответственность |
|---|---|
| knowledge.lua | видимые сведения/last_seen и оценка CD по увиденному cast |
| runtime_profile.lua | чтение собственных AbilityValues, без старых зашитых damage/манакостов |
| mechanics.lua | геометрия, target-specific stacks/expiry, soul-aware raw damage, HP bounds |
| threat.lua | признаки угрозы от видимой маны, наблюдавшихся кастов и явно заданных priors |
| wave.lua | причины удержать/пропушить, привязка к наблюдаемой волне и цели |
| catalog.lua | 25 постоянных IDs с параметрами, старые 0–20 сохранены |
| creeps.lua | subtype/variant, реальные bounty/HP, переходы защиты и regen при смерти flag source |
| experience.lua | XP range/получатели/factor, passive forecast отдельно от last hits |
| tower.lua | диапазоны урона по конкретной цели, projectiles, условные tower hit counts, pressure risk |
| planner.lua | генерация/маски/короткий event timeline и прогнозы, baseline utility |
| scheduler.lua | ожидание подтверждений, валидация, actor lease, abort/replan |
| bridge.lua | handshake с T016 backend; без регистрации не отдаёт приказы |
| trace.lua | сериализуемый snapshot + все candidates/masks/выбор/engine events |
| config.lua | явно вынесенные baseline coefficients; не learned reward |

## Будущая оценка/обучение

Нужны отдельные записи: observation с источниками/uncertainty; доступные options/причины масок; chosen plan и его предсказания; submitted/released/completed/cancelled; подтверждённые combat/last-hit/deny/resource события; смена волны/доступ к руне; actual return/reward, определённый отдельно.

У `trace.Record` reward_status=not_defined. В predicted features лежат предполагаемые secured_creeps/denies/hero damage/kills, затраты маны, риск, длительность и wave context. Они не подмешиваются в labels как реальные исходы. Damage attribution между автоатакой, рейзом и крипами требует combat-event collector T006. Счётчика LH между кадрами недостаточно для причинного attribution.

Baseline utility из config — заменяемое ранжирование, не reward function. Числа там вынесены для ревью. Модель не должна получать награду за нажатие cast, ожидание не штрафуется покадрово, каждое лишнее применение маны не объявляется полезным. Цели включают LH/deny/XP timing, выгодные размены, rune access, wave position и выживание; веса и delayed credit согласуются отдельно.

Schema расширена до `sf-lane-options-0.2-draft3`, это локальный draft-интерфейс до согласования T016. В trace.context отдельно сохраняются XP и условные tower forecasts. Подробнее: [типы крипов/мана/XP/вышки](CREEPS_XP.md); [аудит нового PR #21](RELEASE_AUDIT.md).

## Что ещё не сделано

Backend Snapshot/Validate/Submit/Events/Record уже реализован в runtime/backend.lua; collector -- runtime/observe.lua. Ещё требуются hook Олега (Kimi), фактическое подтверждение shared Lua-state и семантики event/profile API, точные modifier bindings/профиль build/режима. Полный predictor входящего урона/путей и rune/ward/kite execution остаются pending. Enemy HP/mana читаются, автоматические enemy cast/threat bindings ещё не подключены.

**Не устанавливать текущую папку как готовый игровой релиз.** Default режима переключён на joint_options, поэтому без зарегистрированного backend он уступает управление; старый primitive-adapter не запускается незаметно. Совместная интеграция и игровой тест v0.2 остаются обязательными.
