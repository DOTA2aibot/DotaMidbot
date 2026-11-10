-- T026: one Radiant mid Observer; parameters are explicit baseline rules.
return {
    enabled=true, lane_end_s=900, duration_s=360, refresh_lead_s=30,
    -- Human Observer entity from calibration match9082528045, owner0 (human), SFowner1.
    fixed_location={x=-216.73818969727,y=-990.77404785156,z=128},
    calibration_source={match_id="9082528045",owner_id=0,observed_at=-41.033332824707,
        evidence="live_human_observer_entity",source_line=1214},
    -- Automatic placement is enabled at the human-selected coordinate.
    calibration_only=false,
    -- Filled only from the next human calibration; never infer either point from SF position.
    dire_fixed_location={x=-549.09741210938,y=425.63497924805,z=128},
    dire_calibration_source={match_id="9083785339",owner_id=0,observed_at=-55.966667175293,
        evidence="live_human_observer_entity",source_line=855},
    sentry_fixed_location={x=-556.30944824219,y=-290.81549072266,z=0},
    sentry_calibration_source={match_id="9083785339",owner_id=0,observed_at=-55.966667175293,
        evidence="live_human_sentry_entity",source_line=856,height_level_raw=4,passable=true},
    sentry_use_rune_midpoint=false, -- human-selected shared point; midpoint was rejected in317
    sentry_windows={{start=0,finish=30},{start=360,finish=390}}, sentry_duration_s=420,
    support_enabled=true, deward_enabled=true, support_desire=.80,
    support_max_s=8, support_max_approach=1000, support_mid_radius=2200,
    sentry_retry_s=3, sentry_attempts_per_window=3, sentry_farm_radius=950,
    sentry_first=true, sentry_followup_s=5, sentry_reveal_grace_s=.35, sentry_enemy_site_radius=350,
    support_enemy_radius=1100, support_creep_radius=1500, support_move_interval_s=.6,
    deward_expected_hits=2, deward_attack_timeout_s=2.5, deward_max_attempts=4,
    windows={{start=0,finish=30},{start=300,finish=330},{start=600,finish=630}},
    prefetch_s=90, diagnostic_interval_s=5,
    recovery_end_s=720, final_window_start_s=600,
    courier_retry_s=10, courier_near_base=1200, courier_min_hp=.8,
    phase_max_s=8, phase_max_approach=1400, phase_retry_s=3,
    phase_move_interval_s=.6, phase_stall_s=2, phase_min_progress=24,
    phase_enemy_radius=1100, phase_creep_radius=1100,
    phase_desire=.80, phase_direct_enemy_radius=450,
    mid_radius=2200, near_site_radius=1800, dedup_radius=180,
    vision_radius=1600, vision_margin=120, tree_corridor=80,
    bank_fraction=.45, mid_fraction=.48, search_radius=640, search_step=160,
    geometry_retry_s=5, max_tree_ids=20000,
    purchase_retry_s=30, pending_timeout_s=90,
    swap_interval_s=8, recent_damage_s=3,
};
