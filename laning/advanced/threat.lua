-- Оценка риска по наблюдаемым ресурсам и наблюдавшимся кастам. Не доступ к скрытым CD.
local M = {};
function M.Estimate( s, duration, cfg )
    local result = { damage_budget = ( s.threat_damage_per_s or 0 ) * duration,
        unknown = false, threats = {}, source = "observations_and_explicit_priors" };
    if not s.enemy_knowledge or #s.enemy_knowledge == 0 then
        result.unknown = true; result.damage_budget = result.damage_budget + cfg.unknown_enemy_risk;
        return result;
    end
    for _, enemy in ipairs( s.enemy_knowledge ) do
        local observed = enemy.visible and enemy.resource_status == "observed";
        if not observed then
            result.unknown = true; result.damage_budget = result.damage_budget + cfg.unknown_enemy_risk;
        else
            for name, threat in pairs( enemy.known_threats or {} ) do
                local cd = ( enemy.spells or {} )[name];
                local estimate = { enemy_id = enemy.id, ability_id = name, ready_possible = true };
                if enemy.mana ~= nil and threat.mana_cost ~= nil and enemy.mana < threat.mana_cost then
                    estimate.reason, estimate.damage_budget = "observed_mana_insufficient_for_this_spell", 0;
                else
                    local factor = 1;
                    if cd and cd.status == "estimated" and cd.nominal_remaining_low and cd.nominal_remaining_low > duration then
                        factor = cfg.observed_cd_risk_factor;
                        estimate.reason = "observed_cast_cd_estimate_reset_still_possible";
                    else estimate.reason = "cast_possible_or_unknown" end;
                    estimate.damage_budget = ( threat.damage_estimate or cfg.unknown_enemy_risk ) * factor;
                end
                result.damage_budget = result.damage_budget + estimate.damage_budget;
                result.threats[#result.threats + 1] = estimate;
            end
            if not enemy.spellbook_complete then
                result.unknown = true; result.damage_budget = result.damage_budget + cfg.unknown_enemy_risk;
            end
        end
    end
    return result;
end
return M;
