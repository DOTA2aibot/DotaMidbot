-- Параметры baseline для обсуждения. Это не обученные веса и не reward.
return {
    policy_version = "T007-options-draft-2",
    execution_mode = "joint_options", -- прежние примитивные правила больше не выбираются по умолчанию
    lane_end_s = 600,             -- после 10 минут этот lane mode уступает другим режимам
    decision_interval_s = 0.15,
    yield_hp_fraction = 0.35,      -- ниже: отдать управление другим режимам, а не приказать retreat
    harass_hp_fraction = 0.65,
    damage_fraction = 0.95,        -- запас 5% от оценки одного обычного удара
    reserve_damage_multiple = 1.5,-- не отвлекаться на harass, если крип близок к last-hit/deny
    deny_hp_fraction = 0.50,
    tower_margin = 150,           -- запас в world units вокруг радиуса атаки видимой башни
    lane_front_offset = -250,
    reposition_distance = 175,
    enemy_count_radius = 1200,
    creep_scan_radius = 1500,
    tower_scan_radius = 1500,
    trace_interval_s = 1.0,        -- периодическая сводка; каждый отправленный attack логируется
};
