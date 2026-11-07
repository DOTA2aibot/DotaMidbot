-- Тайминги -- проверяемые cues, не приказ пушить по часам и не знание о spawn под fog.
local M = {};
function M.Context( s, config )
    local w = s.wave or {};
    local out = { goal = "equilibrium", push_allowed = false, reason = "hold_wave",
        schedule_verified = s.schedule_verified == true };
    if s.danger or ( not s.enemy_visible and s.hero.hp_fraction < config.missing_enemy_caution_hp ) then
        out.reason = "unsafe_push"; return out;
    end
    if w.is_first_wave and s.hero.level < 2 and w.level_two_race then
        out.goal, out.push_allowed, out.reason = "level_two_race", true, "first_wave_xp_timing";
    end
    local rune = s.rune or {};
    if s.schedule_verified and rune.next_spawn_at and rune.spawn_type_known then
        local remaining = rune.next_spawn_at - s.time;
        if remaining >= 0 and remaining <= config.rune_push_lead_s and w.can_clear_and_reach_rune then
            out.goal, out.push_allowed, out.reason = "prepare_rune", true, "clear_before_rune";
            out.objective_at = rune.next_spawn_at;
        end
    end
    if w.allied_siege_visible and w.allied_siege_alive and w.siege_pressure_viable then
        out.goal, out.push_allowed, out.reason = "siege_pressure", true, "observed_siege_wave";
    end
    if rune.visible_available and rune.path_safe and w.lane_can_be_left then
        out.rune_move_allowed = true;
    end
    return out;
end
return M;
