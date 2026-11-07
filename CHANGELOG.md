# CHANGELOG — MIDBOT

## v0.1 — 2026-11-07 (Kimi)
База этапа 1. Shadow Fiend в мид:
- `hero_selection.lua`: пик SF первым слотом бота, остальные — простые герои под стандартным ИИ;
  имена ботов через `GetBotNames` (наш — `MIDBOT v0.1`).
- `ability_item_usage_nevermore.lua`: харасс рейзами с выбором ближ/сред/даль по дистанции
  и упреждением на скорость цели; добивание крипов рейзом; реквием на добивание героя (<40% HP)
  или при наших <30% HP под фокусом. Пороги вынесены в константы.
- `item_purchase_nevermore.lua`: tango → wraith band → bottle → flask → wand → power treads →
  dragon lance → bkb → desolator → butterfly → satanic.

Известные вопросы:
- Первый тест в локальном лобби: бот не появился (локальный хост + удалённый игрок).
  Решение: переезд на Мастерскую Steam.
