# Разбор9083503375 и откат к выбранному baseline

Artem (GPT), T036/T037; owner рун Олег (Kimi). Tested0314: PR53 точный0dc2e60, PR55 точный3c7c1e0 (см.metadata).

## Отзыв пользователя
Stick/Wand обычно работают; около16мин, возможно, не использовал заряды для добивания Viper через Raze+AA. PT в целом хорошие. Дёрганья остались, courier изменение отвергается. Вернуть movement/courier именно к0312ward-recovery, сохранить vision/PT/Wand. Позднее уточнение: xx:45проверка варда должна быть доступна удалённо без поворота; обычныйRaze важнее PT, STRцель выключить, не задерживать каст радиоптимизации.

## Что подтверждено
Лог22,359строк,16,589,538bytes, Lua/helper errors0, malformedJSON0. Snapshot до18:54.567: LH77/deny16/K1/D1; interval counters не дают per-action credit.
Guard starts/orders0: активныйROAMэксперимент в0314уже отсутствовал. Файлыrootabilities/vision/delivery_mode/nativeentrylayout соответствовали312. 100 existing_face_move — старый Razeдоворот, его реализация byte-identical312; в предыдущем312логе такихприказов49 за13:24. Нельзя из этих разноматчевых счётчиков делать вывод о причине каждого промаха.
Воспроизведён отдельный дефект: безPT обычный Before создавал spellticket, выборRaze2 через33мс послеRaze1 отклонялся. Это могло задерживать пересчёт выбора, но полная причинность пользовательского дёрганья ещё не доказана.
Ward readback:4.100/420.667/622.600. Второйprimarywindow пропущен, восстановление около7мин; работа всей recoveryсистемы не объявляется безошибочной по одному run.
Около16:02–16:06 есть5зарядов Wand и65→74маны; Raze2/3 наCD, Raze1 readyCD0, но castablefalse приcost75. Сам факт зарядов не доказывает доступный lethalRaze: нужны конкретнаягеометрия/HP/сопротивления/видимость и CD. Текущийфинisher требует потенциально смертельный ОДИНRaze, комбинациюRaze+AA здесь не добавляем по scope. Успешное нажатие Wand черезlethal_raze_mana_deficit вматче тоже есть.

## Изменение0315
Полностью удалены source/config/profile/test/flag courierROAM, выбранные movement/vision файлы закреплены исходными312хешами. Старые312ITEMmode/доставка/read-onlycourierobserver сохранены, новогоcourierконтроллера нет. Обычный PT.Before теперь безitemorder/ожидания/lock; maintenance послеabilitycallback. NoPTfastpath и отдельныйresource-only INTprep, AGIdefault, безцелевогоSTR. INTоптимизация пропускается при конфликте скастом, не обещается перед каждымcast/BKB.
xx:45 использует GetUnitList(UNIT_LIST_ALLIED_WARDS), безlocalvision/facing/move; remote regression подтверждён, самvisionкод не менялся.
Новый0315матч/исчезновение дёрганий/устранениеcourierdetours не заявлены. Тест:>=12мин безпингов, доPT сменаRaze/LH, послеPT немедленныйcast+AGIrestore, Wand, ward идоставка. Для оставшихсядёрганий нужен точныйtime/video. Runeветка Олега не изменена.
