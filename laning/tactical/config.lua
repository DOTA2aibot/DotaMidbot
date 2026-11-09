-- Opt-in only: modules do nothing until BindLegacy(script_environment).
return {
    version = "tactical-1", enabled = true,
    requiem_cancel = true, mana_items = true, bkb = true, treads = true,
    neutral_farm = true, wards = true,
    requiem_start_radius = 700, requiem_enemy_hp = .40, requiem_self_hp = .30,
    requiem_far_margin = 80, requiem_far_hold = .15, requiem_recast_delay = 3,
    requiem_unknown_timeout = .5,
    mana_min_missing = 50, safe_enemy_radius = 1000, safe_damage_gap = 3,
    item_retry_s = 2, item_confirmation_s = 1, bkb_threat_horizon = 1.2,
    bkb_low_hp = .55, bkb_burst_hp_fraction = .20,
    treads_low_hp = .35, treads_recover_hp = .45,
    -- GetPowerTreadsStat raw states differ from hero ATTRIBUTE_* enums (run9083407516).
    treads_raw_states = {STRENGTH=0, INTELLECT=1, AGILITY=2},
    treads_timeout = 1, treads_max_toggles = 2,
    treads_toggle_interval = .10, treads_intent_s = 1.5,
    wand_emergency_hp = .15, finisher_retry_s = 3,
    neutral_reserve_razes = 2, neutral_radius = 950, neutral_face_step = 48, neutral_face_interval = .12,
    ward_min_hp = .70, ward_enemy_radius = 1100, ward_interval_s = 20,
    ward_timeout_s = 3, ward_dedup_radius = 900,
    -- Geometry profile, NOT a promise of actual vision. Readback reports quality.
    observer_vision_radius = 1600, observer_visibility_margin = 150, observer_min_height = 3,
    tree_corridor = 100, river_height_max = 1,
    control_spells = {
        sven_storm_bolt = true, vengefulspirit_magic_missile = true,
        skeleton_king_hellfire_blast = true, chaos_knight_chaos_bolt = true,
        dragon_knight_dragon_tail = true, lion_impale = true,
        lion_voodoo = true, shadow_shaman_voodoo = true,
        shadow_shaman_shackles = true, windrunner_shackleshot = true,
        ogre_magi_fireblast = true, alchemist_unstable_concoction_throw = true,
    },
};
