# ADR 0004: наблюдаемый runtime handoff для T007/T016

Status: Proposed. Owner: Artem (GPT); reviewer: Олег (Kimi). Связано с T007/T016, продолжает Proposed ADR0003.

Контекст: планировщик merged через PR22, способности через PR21. Независимые callbacks могут перебивать приказы; shared Lua VM/cache и надёжный источник release ещё не проверены в игре.

Предложение: collector/typed executor в laning/runtime, один lane controller и AbilityGate hook в файле Олега (Kimi). Handshake состоит из наблюдённого общего nonce/heartbeat и отдельного ACK на каждый план. До ACK приказов нет; TTL предотвращает бесконечное удержание. При раздельных Lua states handshake не происходит; config-флагом это не обходится.

Режимы: observe по умолчанию, затем однокомандные diagnostic probes attack/raze, затем staged execute на том же каталоге. Диагностика не является reward и не обучает primitive policy. Бounded positioning ID0 обслуживает подход к mid front без реализации полного macro path planner.

Переходы исполнения -- по наблюдаемому evidence: projectile+own attack record либо отдельно откалиброванный own record, CD+mana+ended phase для NO_TARGET cast, текущая позиция для move. Таймеры только отвергают не подтверждённый шаг, не создают успешное событие.

Изменения protocol: optional backend Acquire/Release/Filter/Prepare; Bridge.Cancel/IsActive/Unregister; move_completed; observed_at для ожидания после фактического release. Старые backend fixtures продолжают работать без optional методов. Новые data остаются типизированными/сериализуемыми, handles хранятся отдельно.

Не выбрано: молча считать shared state подтверждённым; одновременно выдавать приказы из двух policies; автоматически объявлять успех по истечению windup; читать скрытые cooldown врага. Fallback для раздельных VM требует отдельного решения после фактического probe.

Принятие обоими владельцами и игровой результат пока отсутствуют. Следующий шаг -- hook Олега (Kimi) и короткие probes по docs/INTEGRATION_TEST.md, затем актуализация ADR по фактическому результату.
