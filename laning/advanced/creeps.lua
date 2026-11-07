-- Тип -- признак, а не таблица навсегда фиксированных HP/защиты/награды.
local D = require( GetScriptDirectory() .. "/laning/advanced/mechanics" );
local M = {};
function M.Classify( name )
    if type( name ) ~= "string" then return "unknown", "unknown" end;
    local subtype, suffix = name:match( "^npc_dota_creep_goodguys_(%a+)(.*)$" );
    if not subtype then subtype, suffix = name:match( "^npc_dota_creep_badguys_(%a+)(.*)$" ) end;
    if not subtype then
        suffix = name:match( "^npc_dota_goodguys_siege(.*)$" ) or name:match( "^npc_dota_badguys_siege(.*)$" );
        if suffix then subtype = "siege" end;
    end
    local variants = { [""] = "normal", _upgraded = "super", _upgraded_mega = "mega" };
    if not variants[suffix] or ( subtype ~= "melee" and subtype ~= "ranged" and subtype ~= "flagbearer" and subtype ~= "siege" ) then
        return "unknown", "unknown";
    end
    return subtype, variants[suffix];
end
local function read( unit, method )
    local ok, value = pcall( function() return unit[method]( unit ) end );
    if ok then return value end;
end
function M.Observe( unit )
    if not unit or read( unit, "CanBeSeen" ) ~= true then return nil, "creep_not_visible" end;
    local name = read( unit, "GetUnitName" );
    local subtype, variant = M.Classify( name );
    return { unit_name = name, creep_type = subtype, creep_variant = variant,
        hp = read( unit, "GetHealth" ), max_hp = read( unit, "GetMaxHealth" ),
        regen = read( unit, "GetHealthRegen" ), armor = read( unit, "GetArmor" ),
        bounty_gold_min = read( unit, "GetBountyGoldMin" ), bounty_gold_max = read( unit, "GetBountyGoldMax" ),
        bounty_xp = read( unit, "GetBountyXP" ), bounty_source = "visible_engine_getters",
        -- Не смешивать ranged attack capability катапульты с типом ranged-крипа.
        is_ranged = subtype == "ranged", profile_status = subtype == "unknown" and "unknown_unit" or "observed" };
end
function M.Type( target )
    if target.creep_type then return target.creep_type end;
    if target.unit_name then return M.Classify( target.unit_name ) end;
    return "unknown"; -- legacy is_ranged не доказывает subtype.
end
function M.Bounty( t )
    local low, high = t.bounty_gold_min, t.bounty_gold_max;
    if D.Number( low ) and D.Number( high ) and low >= 0 and high >= low then return low, high end;
    return nil, nil;
end
local function copy( t ) local o = {}; for k, v in pairs( t ) do o[k] = v end; return o end;
-- Для смерти источника ауры нужны подтверждённые зависимости и переходы защиты.
-- Не вычитаем условные «40%» из всех соседей и не переносим броню одного типа другому.
function M.DefenseView( target, dt, deadFlags )
    local relevant = false;
    for id, death in pairs( deadFlags ) do
        if target.id ~= id and target.kind == death.kind then relevant = true end;
    end
    if not relevant then return target end;
    if not target.defense_dependencies_verified then return nil, "flag_aura_dependencies_unknown" end;
    local changed = {};
    for _, dep in ipairs( target.defense_dependencies or {} ) do
        local death = deadFlags[dep.source_id];
        if death then
            if not D.Number( dep.linger_s ) or dep.linger_s < 0 then return nil, "flag_aura_linger_unknown" end;
            if dt >= death.at + dep.linger_s then changed[#changed + 1] = tostring( dep.source_id ) end;
        end
    end
    if #changed == 0 then return target end;
    table.sort( changed );
    local nextState = ( target.defense_after_deaths or {} )[table.concat( changed, "|" )];
    if not nextState then return nil, "flag_aura_transition_unknown" end;
    local out = copy( target );
    -- Отсутствующий новый query не может унаследовать прежнюю защиту молча.
    out.magic_multiplier, out.magic_damage_by_raw = nextState.magic_multiplier, nextState.magic_damage_by_raw;
    out.attack_damage_effective, out.attack_damage_by_souls = nextState.attack_damage_effective, nextState.attack_damage_by_souls;
    out.nonlinear_damage_unknown, out.regen = nextState.nonlinear_damage_unknown, nextState.regen;
    if not D.Number( out.regen ) then return nil, "flag_aura_regen_transition_unknown" end;
    return out;
end
function M.HPUpperAt( target, dt, deadFlags )
    local cuts = { 0, dt };
    for _, dep in ipairs( target.defense_dependencies or {} ) do
        local death = deadFlags[dep.source_id];
        if death and D.Number( dep.linger_s ) then
            local at = death.at + dep.linger_s;
            if at > 0 and at < dt then cuts[#cuts + 1] = at end;
        end
    end
    table.sort( cuts );
    local regeneration = 0;
    for i = 1, #cuts - 1 do
        local view, err = M.DefenseView( target, cuts[i], deadFlags );
        if not view then return nil, err end;
        regeneration = regeneration + ( view.regen or 0 ) * ( cuts[i + 1] - cuts[i] );
    end
    local view, err = M.DefenseView( target, dt, deadFlags );
    if not view then return nil, err end;
    return math.max( 0, target.hp + regeneration - ( target.hp_loss_per_s or 0 ) * dt
        + ( target.hp_prediction_error_per_s or 0 ) * dt ), nil, view;
end
return M;
