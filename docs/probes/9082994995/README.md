# Матч9082994995 — v0.3.12, варды пройдены, руна/курьер требуют работы

Тест Artem, разбор **Artem (GPT)**, 2026-11-09. Руны — **Олег (Kimi)**.
Код этим отчётом не изменён, установка и merge не выполнялись.

- [Полный консольный лог gzip](console.log.gz) — все строки, после удаления сетевых/account identifiers. Распаковать7-Zip/gzip; исходные номера строк сохранены.
- [Отчёт и code review](REPORT.md), [наблюдения игрока](USER_FEEDBACK.md).
- [Rune events](rune-events.jsonl), [эпизоды подходов](rune-episodes.json), [Ward events](ward-events.jsonl), [Courier trajectory](courier-trajectory.jsonl), [выбранные снимки](snapshot-evidence.jsonl).
- [Observer summary](observer-summary.json), [metadata/hash/provenance](metadata.json), [результат отдельных воспроизведений](review-repro-results.json), [как воспроизвести](REPRODUCTION.md).

Точные исходники: PR53 `0dc2e604f6a6f6f0178cf5abb0d41a714564d21c`, PR55 code `cfab2cfc0d23c016808dbe335d6089e7ead9ddc0`.
Revision `test53-0dc2e60-55-cfab2cf-wardrecovery`, all_test66Lua, fingerprint `3d48e48e04`.
Старое поле observer.version=`v0.3.11-ward-supply` и run_id prefix не обновлены при bump;
это дефект метаданных, а не признак старой установки: source_revision и66file hashes
совпали с manifest установленной v0.3.12. Не определять сборку по одному version полю.

Лог заканчивается около13:24 игрового времени, а не полной победой. Последние счётчики:
LH51/deny24/K5/D1, level10. Ошибок Lua/helper и повреждённых observer/tactical JSON0.
Это один прогон с5 выбранными союзными бот-героями (selection game_mode1), не чистый1v1,
не benchmark и не измерение точности койлов/ML rewards.
