-- T020: ограниченный опыт; значения являются гипотезой, а не обученной наградой.
-- T022 (матчи 9081721395/9081927137: 233/233 и 199/199 снапшотов rune desire=0):
-- desire 0.15 никогда не побеждал нативный LANING (~0.27+), а гейты «любой видимый
-- крип в 1200» и «требуется видимость руны» при отсутствии вардов делали режим
-- недостижимым. Поднимаем desire над лайнингом, крипы блокируют только вплотную,
-- добавлено слепое окно силовых рун (см. runes.lua).
-- T023 (матч 9082042282: даже в слепом окне desire=0 — 56× no_nearby_visible):
-- mid-front до руны ~900+ единиц, rune_distance=650 не доставал; бот на unfair
-- часто ниже 50% HP (health_or_unknown ×31) — а руна как раз заряжает ботл.
-- rune_distance 1100 + enemy_radius 500: scan 1600 — предел API GetNearbyHeroes.
return {
    lane_radius = 1200, rune_distance = 1100, rune_desire = 0.85,
    rune_enemy_radius = 500, rune_min_hp = 0.35, rune_window_end = 900,
    rune_creep_block_radius = 250,
    rune_lane_defense_radius = 900, -- T024: враги у нашей вышки → сначала лайн
    -- T024b: grace держит desire, пока движок начинает наш pickup (матч 9082231706:
    -- схлопывание через 0.13с); timeout 8с — пешком до дальней руны ~1100 ед. ≈ 3.5с.
    rune_order_timeout_s = 8, rune_order_grace_s = 3, rune_retry_s = 10,
    mana_fraction = 0.35, mana_missing = 100, mana_window_end = 600,
    mana_purchase_interval = 90, mana_attempt_interval = 5,
    mana_max_purchases = 3, mana_max_gold = 200,
};
