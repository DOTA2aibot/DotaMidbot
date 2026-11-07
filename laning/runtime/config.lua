-- Один файл настройки игрового probe. Не включать execute до проверки hook Kimi.
return {
    operation = "observe", -- observe | probe_attack | probe_raze | execute; все приказы требуют двусторонний ACK
    stage = "attacks", -- attacks -> raze -> combos; каталог options при этом не перенумеровывается
    option_allowlist = nil, -- для отдельного combo probe можно ограничить, например { [6] = true }
    build = "unrecorded", run_id = "local-probe",
    scan_radius = 1500, collect_interval_s = 0.05, log_interval_s = 1,
    full_records = false, max_damage_queries = 96,
    max_probe_orders = 1, attack_use_proficiency = true,
    lane_positioning = true, move_step = 250, anchor_offset = -250, anchor_tolerance = 200,
    owner_ttl_s = 0.35, command_timeout_s = 2, decision_interval_s = 0.15,
    facing_tolerance_deg = 5, face_distance = 48, yield_hp_fraction = 0.35,
    -- Здесь фиксируются результаты конкретного установленного build, не предположения.
    probes = {
        attack_damage_verified = false, -- проверить raw/proficiency/reduction query на каждом используемом subtype
        attack_point_seconds_verified = false,
        last_attack_time_release_verified = false, -- только после сопоставления GetLastAttackTime с реальным release в этом build
        raze_geometry_verified = false, modifier_bindings_verified = false,
        cross_raze_timing_verified = false,
        xp_rules_verified = false, xp_radius = nil,
        tower_damage_verified = false,
    },
    soul_modifier = "modifier_nevermore_necromastery",
    raze_modifier = "modifier_nevermore_shadowraze_debuff",
};
