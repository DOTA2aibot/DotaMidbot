-- T020: ограниченный опыт; значения являются гипотезой, а не обученной наградой.
-- T022 (матчи 9081721395/9081927137: 233/233 и 199/199 снапшотов rune desire=0):
-- desire 0.15 никогда не побеждал нативный LANING (~0.27+), а гейты «любой видимый
-- крип в 1200» и «требуется видимость руны» при отсутствии вардов делали режим
-- недостижимым. Поднимаем desire над лайнингом, крипы блокируют только вплотную,
-- добавлено слепое окно силовых рун (см. runes.lua).
return {
    lane_radius = 1200, rune_distance = 650, rune_desire = 0.85,
    rune_enemy_radius = 900, rune_min_hp = 0.5, rune_window_end = 900,
    rune_creep_block_radius = 450,
    rune_order_timeout_s = 4, rune_retry_s = 10,
    mana_fraction = 0.35, mana_missing = 100, mana_window_end = 600,
    mana_purchase_interval = 90, mana_attempt_interval = 5,
    mana_max_purchases = 3, mana_max_gold = 200,
};
