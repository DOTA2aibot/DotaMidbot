return {
    version = "v0.3.6-github", run_prefix = "observer-v036", interval_s = 1,
    radius = 1400, max_targets = 16, failure_interval_s = 10,
    attack_poll_s = 0.1, -- bounded read-only evidence polling; не считает все попадания
    -- Ни одного AA/move приказа: рекомендации отделены от реальных действий.
    shadow_enabled = true,
    ward_interval_s = 20, ward_timeout_s = 3, -- включение только через profile.wards_enabled
    ward_min_hp_fraction = 0.7, ward_enemy_radius = 900, ward_dedup_radius = 900,
};
