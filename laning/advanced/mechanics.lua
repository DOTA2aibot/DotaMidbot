-- Числовая модель только для планирования. Все balance-values поступают из runtime profile.
local M = {};
function M.Number( n ) return type( n ) == "number" and n == n and math.abs( n ) < math.huge end;
function M.Distance( a, b ) return math.sqrt( ( a.x - b.x ) ^ 2 + ( a.y - b.y ) ^ 2 ) end;
function M.Predict( target, dt )
    return { x = target.x + ( target.vx or 0 ) * dt, y = target.y + ( target.vy or 0 ) * dt };
end
function M.RazeRaw( profile, souls, stacks, spell_amp )
    for _, key in ipairs( { "base_damage", "damage_per_soul", "stack_bonus", "stack_duration_s" } ) do
        if not M.Number( profile[key] ) then return nil, "profile_missing:" .. key end;
    end
    if not M.Number( souls ) or not M.Number( stacks ) then return nil, "souls_or_stacks_unknown" end;
    return ( profile.base_damage + profile.damage_per_soul * souls + profile.stack_bonus * stacks ) * ( 1 + ( spell_amp or 0 ) );
end
function M.AttackDamage( hero, target, projected_souls )
    -- attack_damage_effective уже включает current total attack damage + текущую защиту цели.
    -- Повторно прибавлять души/предметы или вычитать ауру нельзя.
    if projected_souls and hero.souls and projected_souls ~= hero.souls then
        local queries = target.attack_damage_by_souls or {};
        if M.Number( queries[tostring( projected_souls )] ) then return queries[tostring( projected_souls )] end;
        if projected_souls < hero.souls then return nil, "attack_damage_after_soul_loss_unknown" end;
        -- Без engine-query не добавлять бонус повторно; при росте душ это консервативная оценка.
    end
    if M.Number( target.attack_damage_effective ) then return target.attack_damage_effective end;
    return nil, "current_attack_damage_query_missing";
end
function M.MagicDamage( raw, target )
    if not raw then return nil end;
    local queried = ( target.magic_damage_by_raw or {} )[tostring( raw )];
    if M.Number( queried ) and queried >= 0 then return queried end;
    -- Production adapter должен получить factor/query при текущих эффектах и отметить ограничения.
    -- Нелинейный absorb/block не симулируем линейным множителем как точный исход.
    if target.nonlinear_damage_unknown or not M.Number( target.magic_multiplier ) or target.magic_multiplier < 0 then return nil end;
    return raw * target.magic_multiplier;
end
function M.Impact( hero, aim, profile )
    local dx, dy = aim.x - hero.x, aim.y - hero.y;
    local d = math.sqrt( dx * dx + dy * dy );
    if d == 0 then return nil end;
    return { x = hero.x + dx / d * profile.range, y = hero.y + dy / d * profile.range };
end
function M.StacksAt( target, now )
    if target.raze_stacks == nil then return nil end;
    if target.raze_stacks == 0 then return 0 end;
    if not target.stack_expires_at then return nil end;
    return now < target.stack_expires_at and target.raze_stacks or 0;
end
function M.SoulsAt( hero, current_projection, dt )
    if hero.temporary_souls_unresolved then return nil end;
    local count = current_projection;
    if not M.Number( count ) then return nil end;
    for _, expiry in ipairs( hero.soul_expiry_events or {} ) do
        if dt >= expiry.at_s then count = math.max( 0, count - expiry.remove_at_most ) end;
    end
    return count;
end
function M.CurrentHPAt( target, dt )
    -- hp_loss_per_s только из видимой истории; его нельзя считать гарантированным future damage.
    local nominal = target.hp + ( target.regen or 0 ) * dt - ( target.hp_loss_per_s or 0 ) * dt;
    local uncertainty = ( target.hp_prediction_error_per_s or 0 ) * dt;
    return math.max( 0, nominal ), math.max( 0, nominal - uncertainty ), math.max( 0, nominal + uncertainty );
end
return M;
