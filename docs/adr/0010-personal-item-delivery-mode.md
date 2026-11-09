# ADR0010 — личный ITEM-mode без встречи курьера

Статус: **Proposed**. T036 / Issue58 / PR55, 2026-11-09.
Owner Artem (GPT), reviewer Олег (Kimi).

Пользователь разрешил убрать hero-to-courier отвлечение параллельно с T035.
Собственная root-доставка отдаёт приказы курьеру и нужна для предметов. Старая
телеметрия не доказывает источник встречного движения героя. Фильтра одного
внутреннего действия native ITEM-mode API не предоставляет.

Ограниченный эксперимент: только all_test явно заменяет весь личный SF ITEM-mode.
GetDesire/OnStart/Think/OnEnd управляют лишь безопасным близким ground pickup<=160ед.
Никаких courier целей, MoveToUnit/MoveToLocation, engine monkeypatch, fake fallback
или ClearActions. Native другие режимы/usage/purchase сохраняются. Общий broker
ограничивает собственный приказ за tick. Courier trajectory — readonly, throttle1с.

Альтернативы: оставить только наблюдение (не запрещает ITEM rendezvous); заменить
движение героя целиком (выходит за согласованный scope); отключить всю доставку
(мешает закупке). Выбран эксперимент с явной ценой: утрачиваются distant drops и
другие внутренние возможности Valve ITEM-mode; поддержаны owned drops и Rapier
рядом. Остальные профили не получают этот entry. Пакет обновляется чистой заменой.

Mocks проверяют ограниченные приказы/безопасность/readback/package, но не native
mode dispatch и не качество игры. Для решения нужны независимое review и clientrun
с courier delivery во время фарма. При регрессии откатить чистым предыдущим пакетом;
одного выключения Lua-флага недостаточно для возврата C++ ITEM-mode. Accepted здесь
не заявляется. Подробный протокол: docs/STATIONARY_DELIVERY.md.
