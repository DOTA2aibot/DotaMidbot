# T036 — SF не выбирает курьера целью движения

Issue58 / PR55. Owner Artem (GPT), reviewer Олег (Kimi). v0.3.12, кандидат.

Пользователь наблюдал отход SF от пачки к доставляющему курьеру. Старый лог не
содержал courier positions; причина не доказана. Проверка исходников не нашла
собственного приказа герою двигаться к курьеру. Root purchase callback отдаёт
TAKE_AND_TRANSFER **курьеру**. Это нужная доставка, её не удаляем.

Для all_test вводится явная замена **всего личного SF ITEM-mode**. Новый
profiles/all_test/mode_item_nevermore.lua вызывает laning/items/delivery_mode.lua.
Он никогда не выбирает курьера целью героя и не выдаёт MoveToLocation/MoveToUnit.
Нативные lane/attack/retreat и отдельные rune/ward режимы сохраняются; item usage,
закупка, BKB/PT/Tango не переносятся в новый режим. Методы engine/handle не меняются.

Цена этой границы: native ITEM-mode больше не ищет далёкие предметы на земле.
Взамен оставлен ограниченный Action_PickUpItem для видимого предмета<=160ед:
собственный drop или публичная Rapier, известное свободное место, отсутствие
крипов/врагов/башен/retreat/rune/cast/ward lease и повреждения. Меньший desire0.25,
до3с и2попыток, readback реального inventory; исчезновение drop не является успехом.
Даже pickup API может немного подвести героя к близкому предмету, но не к курьеру.
Остальные типы чужих drops автоматически не подбираются.

Флаг stationary_delivery_enabled генерируется только для all_test, и только в нём
устанавливается личный ITEM entry. Простое отключение флага не возвращает native
ITEM-mode: для rollback нужен чистый пакет без этого entry (например
valve_lane_economy) или предыдущее сохранённое all_test. Не накладывать архив сверху.

courier_trajectory пишет примерно раз/сек при cargo/delivery: own hero/courier XYZ,
расстояние, courier state, cargo slots, hero mode/action. Это наблюдение, не причина
движения: уменьшение дистанции само по себе не доказывает rendezvous. Если SF всё
равно отходит, новый лог позволит проверить другой native mode; полной гарантии
от любых перемещений engine этот патч не даёт.

Проверки: tests/items/run_tests.py —12 сценариев; tests/testing/test_package.py
проверяет entry+flag только в all_test. Новая диспетчеризация ITEM-mode и эффект
на фарм в реальном клиенте **не проверены**. ADR0010 остаётся Proposed.

Новый матч Radiant SF: обычная доставка предмета при живой пачке на миду, без
пингов игрока. Наблюдать продолжает ли SF фармить, дошёл ли courier, появились ли
предметы в inventory. Параллельно пройти окна Observer0/5/10 и не менее12мин.
Успех: нет Lua/helper errors и движения SF к courier как ITEM цели; есть реальные
delivery/ward readback. Безопасная отмена при смерти/опасности не является багом.
