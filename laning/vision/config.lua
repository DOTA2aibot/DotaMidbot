-- T026: one Radiant mid Observer; parameters are explicit baseline rules.
return {
    enabled=true, lane_end_s=900, duration_s=360, refresh_lead_s=30,
    mid_radius=2200, near_site_radius=1800, dedup_radius=180,
    vision_radius=1600, vision_margin=120, tree_corridor=80,
    bank_fraction=.45, mid_fraction=.48, search_radius=640, search_step=160,
    geometry_retry_s=5, max_tree_ids=20000,
    purchase_retry_s=30, pending_timeout_s=90,
    swap_interval_s=8, recent_damage_s=3,
};
