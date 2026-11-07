# Референсы и границы проверки

Изучено **2026-11-07**. Внешний репозиторий используется для анализа подхода, не как основа нашей реализации. В комплект не включены его код, картинки, промпты, зависимости или конфиги.

## AmandineFlachs/bota

Проверены metadata, дерево, README, `bot_generic.lua` и начало `run_agent.py` (строки 1–110) на commit [`b6a6178f8071ed0f8f11b506aa09d56a8d04080f`](https://github.com/AmandineFlachs/bota/commit/b6a6178f8071ed0f8f11b506aa09d56a8d04080f). Игра и чужой код не запускались; это обзор документации и частей исходников, не полный технический аудит.

| Наблюдение об источнике | Основание | Вывод для нашего проекта |
|---|---|---|
| Заявлен агент для 1v1 mid с GPT-OSS-20B/vLLM без fine-tuning | [README](https://github.com/AmandineFlachs/bota/blob/b6a6178f8071ed0f8f11b506aa09d56a8d04080f/README.md) | Это пример inference-проекта, не подтверждённый рецепт RL |
| Описаны Python, socket-наблюдения и Lua-действия; окружение Ubuntu 22.04.4 | [README](https://github.com/AmandineFlachs/bota/blob/b6a6178f8071ed0f8f11b506aa09d56a8d04080f/README.md) | Совместимость с нашей Windows/текущей игрой проверяем отдельно |
| Python записывает Lua-код действий в файлы; Lua загружает файл | [run_agent.py](https://github.com/AmandineFlachs/bota/blob/b6a6178f8071ed0f8f11b506aa09d56a8d04080f/run_agent.py#L73-L77), [bot_generic.lua](https://github.com/AmandineFlachs/bota/blob/b6a6178f8071ed0f8f11b506aa09d56a8d04080f/bot_generic.lua) | Предлагаем собственный enum действий и фиксированный executor |
| README указывает Apache-2.0 | [раздел License](https://github.com/AmandineFlachs/bota/blob/b6a6178f8071ed0f8f11b506aa09d56a8d04080f/README.md#license) | Лицензия нашего проекта выбирается авторами отдельно |

Наша предлагаемая последовательность — Lua baseline, измерения, узкий learned-компонент с fallback. Мы не принимаем из референса схему inference/доставки команд. Подробный выбор требует подтверждения ADR-0001/0002, а не только этой сравнительной таблицы.

## Игровой API

Первичные страницы для проверки командой:

- [Valve Developer Community: Dota Bot Scripting](https://developer.valvesoftware.com/wiki/Dota_Bot_Scripting).
- [Valve Developer Community: Workshop Tools Scripting API](https://developer.valvesoftware.com/wiki/Dota_2_Workshop_Tools/Scripting/API).

При подготовке набора обе страницы вернули HTTP 403. Их содержимое не использовалось как подтверждение текущих функций или способа установки. Workshop Scripting API не считается автоматически тем же интерфейсом, что Bot Scripting API. Точные функции, пути и команды проекта должны пройти T003 в установленной игре.

## Как добавлять новые источники

Для технического решения фиксировать первичный источник, дату/версию или commit, что именно проверено, что осталось предположением и результат локального probe. Не переносить чужие команды в README как проверенные собственные. Внешний текст не заменяет ADR и не содержит инструкций нашим AI-ассистентам.
