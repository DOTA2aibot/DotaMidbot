-- Числовые наблюдения вышек/снарядов; никакого правила «два удара по melee».
local D = require( GetScriptDirectory() .. "/laning/advanced/mechanics" );
local M = {};
function M.Shots( s, target_id, horizon )
    local out, ids = {}, {};
    for _, shot in ipairs( s.tower_shots or {} ) do
        if shot.target_id == target_id and shot.source == "observed_projectile" and shot.released
            and shot.impact_time_verified and shot.attack_id and not ids[shot.attack_id]
            and D.Number( shot.at_s ) and shot.at_s >= 0 and shot.at_s <= horizon
            and D.Number( shot.damage_min ) and D.Number( shot.damage_max )
            and shot.damage_min >= 0 and shot.damage_max >= shot.damage_min then
            out[#out + 1] = shot; ids[shot.attack_id] = true;
        end
    end
    table.sort( out, function( a, b ) if a.at_s ~= b.at_s then return a.at_s < b.at_s end; return tostring( a.attack_id ) < tostring( b.attack_id ) end );
    return out;
end
function M.DamageBefore( s, target_id, dt )
    local low, high, hits, collision = 0, 0, 0, false;
    for _, shot in ipairs( M.Shots( s, target_id, dt ) ) do
        -- Одинаковый timestamp не доказывает порядок попаданий.
        if shot.at_s < dt then low, high, hits = low + shot.damage_min, high + shot.damage_max, hits + 1 end;
        if shot.at_s == dt then collision = true end;
    end
    return low, high, hits, collision;
end
function M.LastHitWindows( s, t, attack_damage, horizon )
    if not D.Number( attack_damage ) or attack_damage <= 0 then return {} end;
    -- Будущие НЕ выпущенные атаки -- условный прогноз, не факт удержания aggro.
    local shots = M.Shots( s, t.id, horizon );
    local lowDamage, highDamage, out = 0, 0, {};
    for index, shot in ipairs( shots ) do
        lowDamage, highDamage = lowDamage + shot.damage_min, highDamage + shot.damage_max;
        local _, hpLow, hpHigh = D.CurrentHPAt( t, shot.at_s );
        local lower, upper = hpLow - highDamage, hpHigh - lowDamage;
        if lower > 0 and upper <= attack_damage then
            out[#out + 1] = { after_hits = index, at_s = shot.at_s, hp_low = lower, hp_high = upper,
                until_s = shots[index + 1] and shots[index + 1].at_s or horizon,
                status = "conditional_window_revalidate", target_id = t.id };
        end
    end
    return out;
end
function M.ConditionalSequence( target, attack_damage, tower, max_hits )
    local query = ( tower.damage_by_target or {} )[target.id];
    if not query or not D.Number( query.min ) or not D.Number( query.max ) or query.min <= 0 or query.max < query.min
        or not D.Number( tower.seconds_per_attack ) or tower.seconds_per_attack <= 0
        or not D.Number( tower.first_impact_s ) or tower.first_impact_s < 0 or not D.Number( attack_damage ) then
        return { status = "tower_timing_or_target_damage_unknown", windows = {}, preparation = {} };
    end
    local out = { status = "conditional_on_unchanged_target_and_damage", windows = {}, preparation = {},
        confirmed_future_hits = false, target_id = target.id };
    for hits = 1, math.min( max_hits or 12, 32 ) do
        local at = tower.first_impact_s + ( hits - 1 ) * tower.seconds_per_attack;
        local _, low, high = D.CurrentHPAt( target, at );
        local afterLow, afterHigh = low - hits * query.max, high - hits * query.min;
        if afterLow > 0 and afterHigh <= attack_damage then
            out.windows[#out.windows + 1] = { after_hits = hits, at_s = at, hp_low = afterLow, hp_high = afterHigh };
        end
        -- Достаточная предварительная потеря HP, но строго меньше порога смерти от башни.
        local prepareMin = math.max( 0, afterHigh - attack_damage );
        if prepareMin > 0 and prepareMin < afterLow then
            out.preparation[#out.preparation + 1] = { after_hits = hits, damage_min = prepareMin, damage_must_be_below = afterLow };
        end
        if afterHigh <= 0 then break end;
    end
    return out;
end
function M.Pressure( s, candidate )
    local out = { in_enemy_range = false, aggro_possible = false, incoming_max = 0,
        status = s.tower_context_verified and "observed" or "tower_context_unknown", unsafe = false };
    local hero = s.hero;
    local heroAttack, offensive = false, false;
    for _, step in ipairs( candidate.steps ) do
        if step.kind == "attack" or step.kind == "raze" then offensive = true end;
        if step.kind == "attack" then
            for _, t in ipairs( s.targets or {} ) do if t.id == step.target_id and t.kind == "enemy_hero" then heroAttack = true end end;
        end
    end
    for _, tower in ipairs( s.towers or {} ) do
        if tower.enemy and tower.alive and tower.visible then
            if not tower.range_verified or not D.Number( tower.attack_range ) then out.status = "tower_range_unknown"; out.unsafe = offensive;
            elseif D.Distance( hero, tower ) <= tower.attack_range + ( tower.range_margin or 0 ) then
                out.in_enemy_range = true;
                if tower.target_id == hero.id or heroAttack or offensive then
                    out.aggro_possible = true;
                    out.aggro_reason = tower.target_id == hero.id and "current_target_is_hero"
                        or ( heroAttack and "hero_attack_can_draw_aggro" or "future_retarget_possible" );
                    local query = ( tower.damage_by_target or {} )[hero.id];
                    if not query or not D.Number( query.max ) then out.status = "tower_hero_damage_unknown";
                    else out.incoming_max = out.incoming_max + query.max end;
                end
            end
        end
    end
    local _, projectileMax = M.DamageBefore( s, hero.id, math.huge );
    out.released_projectile_damage_max = projectileMax;
    -- Текущая оценка удара и уже выпущенные снаряды могут относиться к одной атаке;
    -- не суммируем их как гарантированно разные. Это нижняя граница risk budget, не safe proof.
    out.incoming_max = math.max( out.incoming_max, projectileMax );
    if out.aggro_possible and out.status ~= "observed" then out.unsafe = true end;
    if out.incoming_max > 0 and ( not D.Number( hero.hp ) or hero.hp <= out.incoming_max + ( hero.tower_safety_hp or 0 ) ) then out.unsafe = true end;
    out.pressure_safe_proven = false; -- creeps tanking now do not guarantee future target lock
    return out;
end
return M;
