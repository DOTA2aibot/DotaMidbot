# MIDBOT — самообучающийся бот для Dota 2 (мид)

Наш бот-скрипт для Dota 2 (Lua Bot API). Этап 1: один герой — **Shadow Fiend**, играет мид,
дуэли 1v1 против людей и стандартных ботов. Дальше — самообучение на локальном железе
(7800X3D, 32 GB DDR5, RTX 5070 12 GB).

## Структура

| Файл | Что делает |
|---|---|
| `hero_selection.lua` | Пик SF для нашего бота + имена ботов (`GetBotNames`), версия в нике |
| `ability_item_usage_nevermore.lua` | Мозг SF: рейзы по дистанции с упреждением, фарм, реквием |
| `item_purchase_nevermore.lua` | Закупка: tango → wraith band → bottle → wand → PT → dragon lance → bkb → ... |

Всё, для чего нет lua-файла, делает стандартный ИИ Valve (лайнинг, отступления, перемещения).

## Установка / запуск

**Локально:** содержимое репозитория → `Steam\steamapps\common\dota 2 beta\game\dota\scripts\vscripts\bots\`
→ в лобби выбрать «Локальный скрипт» (только Local Host сервер).

**Через Мастерскую:** элемент «MIDBOT» (Steam Workshop) → лобби на любом официальном сервере →
выбрать скрипт MIDBOT. Наш бот заходит под ником `MIDBOT vX.Y` — так видно, что скрипт подхватился.

## Правки и версионирование

- Каждая итерация = коммит + поднять версию в нике бота в `hero_selection.lua` (`MIDBOT v0.2`, ...)
- После правок: обновить элемент Мастерской (Dota 2 Workshop Tools → Update Bot Script)
- Протокол итераций в `CHANGELOG.md`

## Источники / референсы

- [Valve: Dota Bot Scripting](https://developer.valvesoftware.com/wiki/Dota_Bot_Scripting)
- [ModDota: Lua Bots](http://docs.moddota.com/lua_bots/)
- [RMMAI (Ranked Matchmaking AI)](https://github.com/adam3q/dota2ai) — эталонный большой скрипт
