-- Чистая логика: snapshot -> намерение. Здесь нет GetBot/Action_* и reward.
local M = {};
local function finite( n ) return type( n ) == "number" and n == n and math.abs( n ) < math.huge end;

function M.YieldReason( s, c )
    if not s.alive then return "dead" end;
    if s.disabled then return "disabled" end;
    if s.casting then return "ability_in_progress" end;
    if s.retreating then return "retreat_mode" end;
    if not finite( s.time ) or s.time < 0 or s.time > c.lane_end_s then return "outside_lane_window" end;
    if not finite( s.hp_fraction ) or s.hp_fraction < c.yield_hp_fraction then return "low_hp" end;
    if s.tower_danger then return "tower_danger" end;
    if s.enemy_count > s.ally_count then return "outnumbered_visible" end;
    return nil;
end

local function available( t )
    return t.visible and t.alive and not t.invulnerable and not t.attack_immune
        and t.in_range and not t.tower_danger and finite( t.hp ) and t.hp > 0
        and finite( t.damage ) and t.damage > 0 and finite( t.eta_s ) and t.eta_s >= 0;
end
local function futureHP( t )
    -- Только текущий HP и доступный regen. Урон других крипов/героев НЕ предсказываем.
    return t.hp + math.max( 0, t.regen or 0 ) * t.eta_s;
end
local function bestKill( list, deny, c )
    local best = nil;
    for _, t in ipairs( list or {} ) do
        local denyAllowed = not deny or ( finite( t.max_hp ) and t.max_hp > 0
            and t.hp / t.max_hp <= c.deny_hp_fraction );
        if available( t ) and denyAllowed and futureHP( t ) <= t.damage * c.damage_fraction then
            -- При двух доступных добиваниях: меньший ETA, затем меньший HP.
            if not best or t.eta_s < best.eta_s or ( t.eta_s == best.eta_s and t.hp < best.hp ) then best = t end;
        end
    end
    return best;
end
local function reserve( list, c )
    for _, t in ipairs( list or {} ) do
        if available( t ) and futureHP( t ) <= t.damage * c.reserve_damage_multiple then return true end;
    end
    return false;
end

function M.Decide( s, c )
    local reason = M.YieldReason( s, c );
    if reason then return { kind = "yield", reason = reason } end;
    if s.attack_busy then return { kind = "wait", reason = "attack_cycle" } end;
    local t = bestKill( s.enemy_creeps, false, c );
    if t then return { kind = "attack", reason = "last_hit", target = t } end;
    t = bestKill( s.allied_creeps, true, c );
    if t then return { kind = "attack", reason = "deny", target = t } end;
    local reserved = reserve( s.enemy_creeps, c ) or reserve( s.allied_creeps, c );
    if not reserved and s.hp_fraction >= c.harass_hp_fraction then
        local target = nil;
        for _, enemy in ipairs( s.enemy_heroes or {} ) do
            if available( enemy ) and ( not target or enemy.distance < target.distance ) then target = enemy end;
        end
        if target then return { kind = "attack", reason = "harass", target = target } end;
    end
    if s.anchor_safe and s.anchor_distance > c.reposition_distance then
        return { kind = "move", reason = reserved and "position_for_creep" or "lane_position" };
    end
    return { kind = "wait", reason = reserved and "reserve_for_creep" or "hold_lane" };
end
return M;
