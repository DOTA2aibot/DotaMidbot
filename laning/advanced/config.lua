-- Эти коэффициенты ранжируют baseline-планы. Это НЕ reward для обучения.
return {
    schema = "sf-lane-options-0.2-draft3", policy_version = "T007-options-draft-3",
    rune_push_lead_s = 25, missing_enemy_caution_hp = 0.50,
    max_plan_horizon_s = 4, max_target_candidates = 8, max_steps = 3,
    reserve_mana_fraction = 0.15, max_snapshot_age_s = 0.30,
    unknown_enemy_risk = 60, observed_cd_risk_factor = 0.5,
    weights = { creep = 10, ranged_creep_bonus = 6, deny = 5, hero_kill = 40,
        hero_damage = 0.025, mana = -0.025, risk = -0.04,
        wave_damage_push = 0.02, wave_damage_hold = -0.012, duration = -0.3, gold_min = 0.10 },
};
