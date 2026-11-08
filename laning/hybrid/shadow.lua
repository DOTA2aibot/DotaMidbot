-- Каталог T007 сохранён. Этот selector только предлагает: Action API здесь нет.
local A = require( GetScriptDirectory() .. "/laning/runtime/api" );
local Catalog = require( GetScriptDirectory() .. "/laning/advanced/catalog" );
local M = {};
function M.Decide( bot, snapshot, handles )
    local candidates, masks = {}, {};
    for _, option in ipairs( Catalog ) do masks[tostring( option.id )] = { available = false, reason = "not_implemented_in_shadow_slice" } end;
    local h = snapshot.hero;
    local free = h.alive == true and h.casting == false and h.channeling == false
        and h.stunned == false and h.hexed == false and BOT_MODE_RETREAT ~= nil and h.active_mode ~= BOT_MODE_RETREAT;
    for _, t in ipairs( snapshot.targets ) do
        local d = h.position and t.position and A.Distance( h.position, t.position );
        local valid = A.Number( d ) and A.Number( h.attack_range ) and d <= h.attack_range
            and t.invulnerable == false and t.attack_immune == false;
        local can_secure = A.Number( t.hp ) and A.Number( t.attack_damage_estimate ) and t.hp <= t.attack_damage_estimate * 0.95;
        local option = t.kind == "allied_creep" and 9 or ( t.kind == "enemy_hero" and 17 or 1 );
        local available = free and h.disarmed == false and valid and ( can_secure or t.kind == "enemy_hero" )
            and ( t.kind ~= "allied_creep" or ( A.Number( t.max_hp ) and t.hp <= t.max_hp * 0.5 ) );
        local score = can_secure and ( option == 9 and 80 or 100 ) or 10;
        if t.uphill == true then score = score - 30 end;
        candidates[#candidates + 1] = { option_id = option, target_id = t.id, available = available == true,
            score = score, reason = t.uphill == true and "uphill_attack_risk" or "attack_estimate",
            uphill = t.uphill, estimated_damage = t.attack_damage_estimate,
            accuracy_status = t.uphill == nil and "terrain_unknown" or "not_a_measured_hit_probability" };
        if available then masks[tostring( option )] = { available = true, reason = "shadow_candidate_only" } end;
        if t.kind ~= "allied_creep" and t.uphill == true and handles[t.id] then
            for _, ability in ipairs( h.abilities ) do
                if ability.name:find( "nevermore_shadowraze", 1, true ) == 1 then
                    local a = A.Call( bot, "GetAbilityByName", ability.name );
                    local range = A.Call( a, "GetSpecialValueFloat", "shadowraze_range" );
                    local radius = A.Call( a, "GetSpecialValueFloat", "shadowraze_radius" );
                    local damage = A.Call( a, "GetAbilityDamage" );
                    local estimate = A.Number( damage ) and DAMAGE_TYPE_MAGICAL ~= nil
                        and A.Call( handles[t.id], "GetActualIncomingDamage", damage, DAMAGE_TYPE_MAGICAL ) or nil;
                    local geometry;
                    if A.Number( range ) and range > 0 and A.Number( radius ) and radius > 0
                        and A.Number( h.facing ) and h.position and t.position then
                        local rad = h.facing * math.pi / 180;
                        geometry = A.Distance( { x = h.position.x + math.cos( rad ) * range,
                            y = h.position.y + math.sin( rad ) * range }, t.position ) <= radius - 40;
                    end;
                    local ready = free and h.silenced == false and ability.castable == true and ability.level and ability.level > 0
                        and t.magic_immune == false and t.invulnerable == false and geometry == true
                        and A.Number( ability.mana_cost ) and A.Number( h.mana ) and h.mana >= ability.mana_cost;
                    local secure = A.Number( estimate ) and A.Number( t.hp ) and t.hp <= estimate * 0.9;
                    candidates[#candidates + 1] = { option_id = 2, target_id = t.id, ability = ability.name,
                        available = ready == true, score = secure and 140 or 5,
                        reason = "uphill_raze_candidate", estimated_damage = estimate,
                        damage_status = "base_query_only_stacks_souls_and_shields_unverified", guaranteed_kill = false };
                    if ready then masks['2'] = { available = true, reason = "shadow_candidate_only" } end;
                end;
            end;
        end;
    end;
    table.sort( candidates, function( a, b )
        if a.available ~= b.available then return a.available end;
        if a.score ~= b.score then return a.score > b.score end;
        return ( a.target_id .. tostring( a.ability or a.option_id ) ) < ( b.target_id .. tostring( b.ability or b.option_id ) );
    end );
    return { policy = "T007-shadow-v1", executed = false, action_masks = masks, candidates = candidates,
        selected = candidates[1] and candidates[1].available and candidates[1] or { option_id = 0, reason = "no_candidate" },
        attribution = "suggestion_not_native_decision", reward_status = "not_defined" };
end
return M;
