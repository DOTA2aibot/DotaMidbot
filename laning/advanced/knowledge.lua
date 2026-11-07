-- Знание о враге: видимые показания и оценка CD по наблюдавшемуся касту.
-- Никогда не читает enemy ability handles/cooldown API под fog.
local M = {};
function M.New() return { enemies = {} } end;
function M.Observe( memory, id, observation, now )
    if not observation.visible then return false end;
    local e = memory.enemies[id] or { casts = {} };
    e.last_seen = now;
    for _, key in ipairs( { "hp", "max_hp", "mana", "max_mana", "level", "armor", "x", "y" } ) do
        e[key] = observation[key]; -- отсутствующее поле остаётся неизвестным, не нулём
    end
    memory.enemies[id] = e;
    return true;
end
function M.ObserveCast( memory, id, ability, event )
    if event.source ~= "visible_cast" or not event.confirmed_release then return false end;
    local e = memory.enemies[id] or { casts = {} };
    e.casts[ability] = { at = event.at, cooldown_low = event.cooldown_low,
        cooldown_high = event.cooldown_high, assumptions = event.assumptions or "reset/CDR may be unknown" };
    memory.enemies[id] = e;
    return true;
end
function M.Read( memory, id, now, currently_visible )
    local e = memory.enemies[id];
    if not e then return { id = id, visible = false, resource_status = "unknown", spells = {} } end;
    local out = { id = id, visible = currently_visible, last_seen = e.last_seen,
        resource_status = currently_visible and e.last_seen == now and "observed" or "last_seen", spells = {} };
    for _, key in ipairs( { "hp", "max_hp", "mana", "max_mana", "level", "armor", "x", "y" } ) do out[key] = e[key] end;
    for name, cast in pairs( e.casts ) do
        local elapsed = math.max( 0, now - cast.at );
        out.spells[name] = { status = "estimated", observed_cast_at = cast.at,
            nominal_remaining_low = cast.cooldown_low and math.max( 0, cast.cooldown_low - elapsed ) or nil,
            nominal_remaining_high = cast.cooldown_high and math.max( 0, cast.cooldown_high - elapsed ) or nil,
            -- Нельзя гарантировать отсутствие reset/CDR только по одному увиденному касту.
            ready_possible = true, assumptions = cast.assumptions };
    end
    return out;
end
function M.ThreatFeatures( enemy, required_mana )
    local mana = enemy.resource_status == "observed" and enemy.mana or nil;
    local sufficient = nil;
    if mana ~= nil and required_mana ~= nil then sufficient = mana >= required_mana end;
    return { hp_fraction = enemy.hp and enemy.max_hp and enemy.max_hp > 0 and enemy.hp / enemy.max_hp or nil,
        observed_mana = mana, mana_sufficient = sufficient,
        insufficient_mana_observed = mana ~= nil and required_mana ~= nil and mana < required_mana,
        resource_uncertain = enemy.resource_status ~= "observed", cooldowns = enemy.spells };
end
return M;
