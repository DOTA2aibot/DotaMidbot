# ADR0009 — короткий режим постановки Observer

Статус: **Proposed**, T026 / Issue54 / PR55. Owner Artem (GPT), reviewer Олег (Kimi).
Основание: прямое поручение Artem 2026-11-09 завершать ward action в свободное окно,
не отдавая движение собственным face/cast веткам; Rune policy остаётся Олегу (Kimi).

Broker гарантирует один собственный приказ в кадр, но не владение нативными приказами
между кадрами. Поэтому ward-phase profiles явно добавляют личный
`mode_ward_nevermore.lua` с GetDesire/OnStart/Think/OnEnd. Он заменяет SF ward-mode,
не полную политику игры. При выходе engine заново выбирает штатный lane/combat mode.
Никакие методы handle/engine не подменяются, lane-mode не добавляется.

Lua phase хранится в общем per-bot broker state. Пока выбран ward-mode, безопасность
проверяется каждый tick; обычные тактические PT/items/spells уступают, observer пишет
данные, emergency BKB выше и освобождает фазу. Один прежний ward executor подтверждает
заряд и новую entity; API return/таймаут не являются постановкой.

Ограничения:8с на фазу,1000ед подхода сверх cast range,2с без прогресса,15с повтор;
farm/deny/enemy/rune/retreat/disabled/lowHP/tower/unknown safety прекращают владение.
Никакого ClearActions при выходе: нельзя стереть новый приказ другого режима.
Реальная диспетчеризация mode/item/ability callbacks, native arbitration, pathing,
LOS и FPS требуют отдельного client run. Mocks не подтверждают их.

Профили valve_play/lane_probe не получают ward entry/flag. Ward-профили получают
его явно; у Dire фаза Radiant не включается, прежняя безопасная in-range ветка
тактических вардов сохраняется. Это не обещание nil→C++ fallback.
