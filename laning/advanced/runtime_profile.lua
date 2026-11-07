-- Только собственные abilities. Враг: знания из knowledge.lua, не enemy:GetCooldownTimeRemaining().
local M = {};
function M.ReadOwnResources( bot )
    return { mana = bot:GetMana(), max_mana = bot:GetMaxMana(), mana_regen = bot:GetManaRegen(),
        hp = bot:GetHealth(), max_hp = bot:GetMaxHealth(), alive = bot:IsAlive(),
        level = bot:GetLevel(), xp_needed_to_level = bot:GetXPNeededToLevel() };
end
function M.ReadRaze( ability, probe )
    if ability == nil then return nil, "ability_handle_missing" end;
    local profile = {
        id = ability:GetName(), learned = ability:GetLevel() > 0,
        base_damage = ability:GetSpecialValueFloat( "shadowraze_damage" ),
        damage_per_soul = ability:GetSpecialValueFloat( "damage_per_soul" ),
        stack_bonus = ability:GetSpecialValueFloat( "stack_bonus_damage" ),
        stack_duration_s = ability:GetSpecialValueFloat( "duration" ),
        range = ability:GetSpecialValueFloat( "shadowraze_range" ),
        radius = ability:GetSpecialValueFloat( "shadowraze_radius" ),
        linked_raze_cooldown_value = ability:GetSpecialValueFloat( "shadowraze_cooldown" ), -- семантику проверить, не считать автоматически global CD
        mana_cost = ability:GetManaCost(), cast_point_s = ability:GetCastPoint(),
        ready_in_s = ability:GetCooldownTimeRemaining(), cooldown_s = ability:GetCooldown(),
        no_target_verified = probe and probe.no_target_verified == true or false,
        geometry_verified = probe and probe.geometry_verified == true or false,
        source = "own_runtime_ability_values", probe_build = probe and probe.build or nil,
    };
    if profile.learned and ( profile.base_damage <= 0 or profile.range <= 0 or profile.radius <= 0
        or profile.stack_duration_s <= 0 ) then return nil, "ability_values_missing_or_changed" end;
    return profile;
end
return M;
