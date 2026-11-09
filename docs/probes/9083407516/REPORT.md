# Что показал тест v0.3.13

Owner **Artem (GPT)**, reviewer **Олег (Kimi)**. T036/Issue58 и T037/Issue59.

## Пользовательское наблюдение

До Stick/PT появились дёрганые шаги/развороты, мешающие farm/койлам. Встречаcourier
местами уменьшилась, но не исчезла; пользователь предпочитает убрать новое
вмешательство при таком регрессе. Стики/активное использование предметов выглядят
хорошо. PT часто наINT и не хватает нескольких единиц damage наlast-hit; проверить
реальныеattribute mechanics иAGI приAA. На6мин после первойруны проверяется другая.
Пользователь закрылDota/Steam и разрешил анализ/исправление/установку.

## Курьерный ROAM experiment отозван

Лог10guard_start/10end. Первые231.500,232.833,233.967с — частые вход/выход и
своиattack/return приказы рядом сnative управлением; rawlines4330–4357. Всего
22delivery_lane_attack и12delivery_lane_return. ПервыйStick появляется452.000с,
Wand495.000с,PT692.033с: дёрганье раннегоguard не объясняется этими предметами.
Связь достаточна для безопасного rollback по просьбе пользователя, но лог не
позволяет приписать каждый missed LH/raze именноguard или вычислитьhit-rate.

v0.3.14 **не включает mode_roam_nevermore.lua** вall_test и задаёт
delivery_lane_guard=false; root samplinghook удалён. Source experiment остаётся
для истории/tests, а installed root entry должен отсутствовать. Чистая замена
bots, не overlay, возвращает native personal ROAM. Полный запрет courierdetours
не заявлен: прежнее поведение возвращено, другой fix требует нового отдельного
подхода, без ещё одной movement/AA политики поверхValve. Courierdelivery не отключена.

## Корень ошибки PT — неправильная интерпретация raw state

В v0313 GetPowerTreadsStat сравнивался с ATTRIBUTE_AGILITY1/ATTRIBUTE_INTELLECT2.
В текущем клиенте rawPTstate имеет другую карту: STR0 / INT1 / AGI2.
Геройские enums по-прежнему STR0/AGI1/INT2; их нельзя использовать вместоPTstate.

Наблюдения при неизменныхlevel8/souls20:

| Snapshot | Attack damage | Max mana | Действие рядом |
|---|---:|---:|---|
| 692.033/700.033/705.033 |113|627| после farm_agility, фактическиINT |
|706.033|123|507| после before_spell_stat, фактическиAGI |
|709.033/710.033|113|627| после очередного farm_agility, фактическиINT |

Raw treads_state_observed возле706.233 и переключения0/1/2 сохранены вcontrol-events.
Параметры выросли на10damage либо120maxmana, что согласуется с выбранным10attribute.
[Dotabuff Power Treads](https://www.dotabuff.com/items/power-treads) подтверждает
переключаемый бонус10атрибута. Raw code mapping установлен по этому live run,
а не по догадке из hero enums или неточной сторонней документации.

Отдельный Lua51 replay на правильной raw fixture: old0313 остаётся raw1/INT,
attack_damage100,0orders; fixed0314 переключает вraw2/AGI,damage110,1order.
Это synthetic regression, не новый матч. Старая fixture возвращала hero enum
вместо настоящего rawPTstate и потому скрывала баг; теперь разделены оба пространства.

v0314: config.treads_raw_states отдельно, AGIraw2 дляобычнойатаки/фарма/Bottle/fountain,
INTraw1 только дляspellintent, STRraw0 какoptional survival. Нет постоянного INT
просто из-за малого mana: без выбранного spell SF должен быть готов бить с полным
уроном. Переключение само по себе не создаёт бесплатнойманы; послеINT проверяется
реальнаяGetMana. Предварительный castintent/readback/timeout и правильныйWand сохранены.

GetAttackDamage уже возвращает текущий урон с учётомPT/душ/предметов. Ни в модель,
ни в engine query не добавляется ещё+10 вручную. Правильный AGI дообычногоfarm
устраняет эту потерюdamage; точный момент чужого C++AA выбора полностьюLua не
контролирует. Собственная атака/новыйcreepcontroller здесь не вводится.
Observer теперь пишет item.treads_raw_state вместе с fresh hero.attack_damage,
maxmana иатакой. Самиengine damage queries сохранены; точностьlast-hit ещё требуетrun.

## Вторая руна6мин — отдельный существующий Rune selector

Rune1 attempt363.100→369.067с; bottle0 в369.000 и3 в370.000, то есть подбор
подтверждён ресурсом. В379.467с начинается поход наRune0 соstatus2(UNKNOWN),
в384.700с отменаrune_taken_while_committed. Первыйguardэтогорайона лишь400.267с;
прямыеguardприказы не объясняют этот второйtrip по времени. Rune source unchanged:
PR53 0dc2e60. Отличие от прежнихматчей может зависеть от visibility/resources/условий.

Олегу (Kimi): рассмотреть запрет слепой проверки второйpowerточки после подтверждённого
собственногоpowerpickup втомжеspawncycle (6мин+), с фактическимtype/status/readback;
не переносить это слепо на2/4watercycles сдвумярунами. Нужнырегрессии наknownfirst
pickup/UNKNOWNopposite инеподтверждённыйfirstattempt, не новый глобальныйtimeout.
Реализацию Rune в этой сессии Artem (GPT) не меняет и не присваивает.

## Прочее и границы

Ward подтвердился4.500/301.233/613.667с, собственныеentity. Wardsource не меняется.
Стики по отзыву пользователя работают; ихбоевыеправила сохранились.
Новыйclientrun необходим: отсутствиеROAMguard, реальныеAGI/INTrawstate иdamage,
сохранённыеWand/ward/распорядок. Играv0314 не выдаётся за проверенную до такогоrun.
