-- T026: one Radiant mid Observer; parameters are explicit baseline rules.
return {
    enabled=true, lane_end_s=900, duration_s=360, refresh_lead_s=30,
    -- Human Observer entity from calibration match9082528045, owner0 (human), SFowner1.
    fixed_location={x=-216.73818969727,y=-990.77404785156,z=128},
    calibration_source={match_id="9082528045",owner_id=0,observed_at=-41.033332824707,
        evidence="live_human_observer_entity",source_line=1214},
    -- Automatic placement is enabled at the human-selected coordinate.
    calibration_only=false,
    windows={{start=0,finish=15},{start=300,finish=315},{start=600,finish=615}},
    prefetch_s=60, diagnostic_interval_s=5,
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
