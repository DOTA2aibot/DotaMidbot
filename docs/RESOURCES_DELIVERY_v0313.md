# v0.3.13 — PT, Stick/Wand и курьер

Owner **Artem (GPT)**, reviewer **Олег (Kimi)**. T036/Issue58 + T037/Issue59,
PR55 поверх a36aeb5. Прямое поручение пользователя разрешает общий патч. Кандидат,
не merge и не подтверждённая новая игра. Руны PR53 остаются за Олегом (Kimi).

## Что изменено и зачем

| Путь | Поведение |
|---|---|
| laning/tactical/treads.lua | PT intent создаётся ДО первого переключения; Tick не разворачивает незавершённую подготовку обратно на AGI/STR. Ожидание реального GetPowerTreadsStat; между нажатиями>=.10с, максимум2переключения, при отсутствии readback1с timeout+pause. Один intent до1.5с, без бесконечного обновления selected_at. |
| tactical/resources.lua | Только собственный активный Stick/Wand с известными целымиcharges>0, castable/cooldown/retry. Nominal restore=live restore_per_charge×charges, отдельно capped missing HP/mana; unknown не подставляется как гарантированная мана. |
| tactical/finisher.lua | Локальная подготовка ресурсов только для видимого настоящего врага в геометрии потенциально смертельного Raze, с выученным готовым незасайленсенным spell. Сначала бесплатный переход INT, затем реальные mana readback и при необходимости заряды. Нет снятия маны с нуля «из воздуха». |
| tactical/items.lua / entry.lua | Emergency Stick приHP<=15% в бою раньше необязательного PT; прежний расход при25–40%HP вне боя убран. Перед Bottle AGI; во время подготовки spell обычный regen не перебивает intent. |
| items/delivery_guard.lua + config.lua | Отдельная детекция движения от lane anchor навстречу own delivery; краткая безопасная lane-hold lease, ближний creep AA или возврат на anchor. Не выбирает courier целью. |
| profiles/all_test/mode_roam_nevermore.lua + packager | Новый личный ROAM entry/flag только all_test. Это полная замена этого native mode, с описанным в ADR0011 ограничением, а не фильтр одной C++ команды. |

GetBotNames, bundle metadata и observer version/run prefix обновлены доv0.3.13;
старый0311observer label из run9082994995 больше не должен путать диагностику.
Root ability/purchase, wards и laning/economy/** не редактируются.

## Правила ПТ

Для добивания/обычной атаки/простоя — AGI. Перед выбранным spell — INT, удерживать
на протяжении подготовки/каста; при наблюдённом release/cooldown вернутьAGI.
AGI при Bottle regen и fountain aura. STR приHP<=35% и recenthero damage —
низкоприоритетная защита, не отбирает незавершённый spell intent; восстановление
порога45%/отсутствие недавнего урона снимает STR. Никаких toggles в cast/channel,
с непустой очередью или без фактической готовности предмета.

Переключение INT сохраняет относительные ресурсы по правилам движка; оно не
гарантирует, что недостаток маны будет покрыт. В production не зафиксирована
выдуманная формула бонуса: после переключения читается реальная GetMana. Если
этого недостаточно, есть bounded retry, а не AGI↔INT каждый кадр.

## Стики/ванд и потенциальные ресурсы

HP<=15% в настоящем бою/при recenthero damage: применить даже1заряд. Empty,
unknown, backpack/stash/cooldown не вызывают Action_UseAbility. Вне боя заряды
сохраняются. Дополнительный повод — маны не хватает на конкретный потенциально
смертельный Raze, а реальная мана после INT/известные заряды покрывают цену.
Видимость/реальныйгерой/иммунитет/CD/геометрия перепроверяются, не преследуем врага
ради подготовки. Текущий урон — консервативная base estimate с engine resistance,
без претензии на точный учёт всех barrier/heal/spell amplification эффектов.
Восстановление — nominal, не обещание фактического heal под всеми debuff.

Число зарядов и potential_hp/potential_mana пишутся в combat_resource_decision.
int_readback_still_insufficient — отказ/пауза, не успешный каст. Сам cast выполняет
прежний spell controller по фактической доступности и своей геометрии/повороту.

## Курьер и границы

См.[ADR0011](adr/0011-delivery-lane-guard.md). Guard не трогает rune policy и не
запрещает survival-retreat глобально. Он действует возле мида, только при наблюдённом
отходе к own delivery от lane anchor и knownsafe. Native map-roaming личного ROAM
этим all_test пакетом заменяется; для возврата нужен чистый пакет без этого entry.
При опасности guard отпускает управление, а при отсутствии отклонения не выбирается.
Он не является новой полной lane policy и не обещает исправить все маршруты карты.
Cooldown/lease/readback и guard decisions логируются. Курьер продолжает старый
TAKE_AND_TRANSFER; никакого отключения доставки нет.

## Проверка в клиенте

Нужен новый Radiantmid матч>=12мин. Проверить доставку bottle/boots/компонентов
во время фарма: delivery_lane_deviation → guard_start → близкая атака/короткий
возврат на lane anchor; герой не проходит половину пути до courier. При новом
враге/реальной угрозе/выходе за midcontext guard должен исчезнуть. Rune и Ward0/5/10
сохраняются. Измерить LH и простои: один успешный путь не является benchmark.

После сборкиPT: несколько последовательныхRaze/обычныхAA, Bottle/fountain,
прерванныйcast, отсутствие нужнойманы. Не должно быть per-frame toggles; смотреть
order_attempt/treads_state_observed/treads_plan_unknown. В бою15%HP проверить
Stick1/много/0charges; отдельно видимый lowHP enemy+mana deficit и неизвестные
special values. Повторное неизвестное применение не считать heal/kill успехом.

Offline suites: resources22, items12+guard10, tactical82, vision86, integration15,
полный baseline runner и package contracts. Их результаты записываются в PR;
synthetic API не подтверждает native arbitration и эффект этого нового клиента.
Никаких новых ML reward labels/обучения/реального gameAC в этом патче нет.

API surface: [ModDota Bot API](https://docs.moddota.com/lua_bots/) —
GetPowerTreadsStat/GetCurrentCharges/GetSpecialValueFloat и GetLaneFrontLocation.
Balance numbers восстановления читаются из live special values, не из старого гайда.
