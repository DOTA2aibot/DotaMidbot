-- Обычный матч: собственный mode_laning отсутствует в корне сборки.
-- tools/package_bot.py генерирует отдельный профиль для диагностической пробы.
return { name = "valve_play", controller = "valve_native", runtime_enabled = false,
    observer_enabled = true, wards_enabled = false, source_revision = "uncommitted" };
