local A = require( GetScriptDirectory() .. "/laning/runtime/api" );
local Profiles = require( GetScriptDirectory() .. "/laning/advanced/runtime_profile" );
local Creeps = require( GetScriptDirectory() .. "/laning/advanced/creeps" );
local Mechanics = require( GetScriptDirectory() .. "/laning/advanced/mechanics" );
local Knowledge = require( GetScriptDirectory() .. "/laning/advanced/knowledge" );
local M = {};
function M.New( cfg )
    return { cfg = cfg, ids = setmetatable( {}, { __mode = "k" } ), serial = 0,
        handles = {}, abilities = {}, memory = Knowledge.New(), observations = 0 };
end
function M.ID( ctx, unit )
    if not ctx.ids[unit] then ctx.serial = ctx.serial + 1; ctx.ids[unit] = "unit:" .. ctx.serial end;
    return ctx.ids[unit];
end
function M.AttackEstimate( source, target, cfg )
    local raw, variance = A.Call( source, "GetAttackDamage" ), A.Call( source, "GetBaseDamageVariance" );
    if not A.Number( raw ) or not A.Number( variance ) or raw < 0 or variance < 0 then return nil end;
    local factor = cfg.attack_use_proficiency and A.Call( source, "GetAttackCombatProficiency", target ) or 1;
    if not A.Number( factor ) or factor < 0 or DAMAGE_TYPE_PHYSICAL == nil then return nil end;
    local low = A.Call( target, "GetActualIncomingDamage", math.max( 0, raw - variance ) * factor, DAMAGE_TYPE_PHYSICAL );
    local high = A.Call( target, "GetActualIncomingDamage", ( raw + variance ) * factor, DAMAGE_TYPE_PHYSICAL );
    if not A.Number( low ) or not A.Number( high ) or low < 0 or high < low then return nil end;
    return { min = low, max = high, source = "current_engine_query_requires_build_probe" };
end
local function bool( bot, name, missing )
    local value = A.Call( bot, name ); if type( value ) ~= "boolean" then missing[#missing + 1] = name end;
    return value == true;
end
local function target( ctx, bot, unit, kind, s )
    if not A.Visible( unit ) then return nil end;
    local p = A.Position( unit ); if not p then return nil end;
    local t = { id = M.ID( ctx, unit ), kind = kind, x = p.x, y = p.y, visible = true, alive = true,
        hp = A.Call( unit, "GetHealth" ), max_hp = A.Call( unit, "GetMaxHealth" ),
        regen = A.Call( unit, "GetHealthRegen" ), armor = A.Call( unit, "GetArmor" ),
        invulnerable = A.Call( unit, "IsInvulnerable" ) ~= false,
        attack_immune = A.Call( unit, "IsAttackImmune" ) ~= false,
        magic_immune = A.Call( unit, "IsMagicImmune" ) ~= false,
        position_error_per_s = 25, prediction_source = "observed_velocity_with_explicit_error_prior" };
    if not A.Number( t.hp ) or not A.Number( t.max_hp ) then return nil end;
    if kind ~= "enemy_hero" then
        local profile = Creeps.Observe( unit ); if profile then for k, v in pairs( profile ) do t[k] = v end end;
    else
        t.mana, t.max_mana = A.Call( unit, "GetMana" ), A.Call( unit, "GetMaxMana" );
        t.level = A.Call( unit, "GetLevel" );
        Knowledge.Observe( ctx.memory, t.id, t, s.time );
    end
    local velocity = A.Call( unit, "GetVelocity" );
    if velocity and A.Number( velocity.x ) and A.Number( velocity.y ) then t.vx, t.vy = velocity.x, velocity.y end;
    local estimate = M.AttackEstimate( bot, unit, ctx.cfg );
    t.attack_query_probe = estimate;
    if estimate and ctx.cfg.probes.attack_damage_verified then t.attack_damage_effective = estimate.min end;
    local stacks, duration = A.Stacks( unit, ctx.cfg.raze_modifier, ctx.cfg.probes.modifier_bindings_verified );
    t.raze_stacks = stacks;
    if stacks and stacks > 0 and duration then t.stack_expires_at = s.time + duration end;
    t.modifier_probe = A.Modifiers( unit );
    t.projectile_probe = {};
    local incoming = A.Call( unit, "GetIncomingTrackingProjectiles" );
    for _, projectile in ipairs( type( incoming ) == "table" and incoming or {} ) do
        if #t.projectile_probe < 24 then
            local row = { is_attack = projectile.is_attack == true, has_caster = projectile.caster ~= nil,
                own_caster = projectile.caster == bot, has_handle = projectile.handle ~= nil };
            if projectile.location and A.Number( projectile.location.x ) and A.Number( projectile.location.y ) then
                row.x, row.y = projectile.location.x, projectile.location.y;
            end
            t.projectile_probe[#t.projectile_probe + 1] = row;
        end
    end
    t.magic_damage_by_raw, t.nonlinear_damage_unknown = {}, true;
    local queries = 0;
    -- Exact raw queries для коротких планов. Не применять factor от одного raw к другому.
    if s.hero.souls ~= nil and stacks ~= nil and DAMAGE_TYPE_MAGICAL ~= nil then
        for _, spell in pairs( s.razes ) do
            for gain = 0, 8 do
                for extraStacks = 0, 2 do
                    local raw = Mechanics.RazeRaw( spell, s.hero.souls + gain, stacks + extraStacks, s.hero.spell_amp );
                    if raw and queries < ctx.cfg.max_damage_queries and t.magic_damage_by_raw[tostring( raw )] == nil then
                        local damage = A.Call( unit, "GetActualIncomingDamage", raw, DAMAGE_TYPE_MAGICAL );
                        if A.Number( damage ) and damage >= 0 then t.magic_damage_by_raw[tostring( raw )] = damage end;
                        queries = queries + 1;
                    end
                end
            end
        end
    end
    ctx.handles[t.id] = unit;
    return t;
end
function M.Collect( ctx, bot )
    local now, p = A.Time(), A.Position( bot );
    if not now or not p then return nil, "clock_or_position_missing" end;
    local mana, maxMana, hp, maxHP = A.Call( bot, "GetMana" ), A.Call( bot, "GetMaxMana" ),
        A.Call( bot, "GetHealth" ), A.Call( bot, "GetMaxHealth" );
    if not A.Number( mana ) or not A.Number( maxMana ) or maxMana <= 0 or not A.Number( hp ) or not A.Number( maxHP ) or maxHP <= 0 then
        return nil, "own_resources_missing";
    end
    ctx.observations = ctx.observations + 1; ctx.handles, ctx.abilities = {}, {};
    local h = { id = "hero:" .. tostring( A.Call( bot, "GetPlayerID" ) ), x = p.x, y = p.y,
        mana = mana, max_mana = maxMana, mana_regen = A.Call( bot, "GetManaRegen" ), hp = hp, max_hp = maxHP,
        hp_fraction = hp / maxHP, level = A.Call( bot, "GetLevel" ), xp_needed_to_level = A.Call( bot, "GetXPNeededToLevel" ),
        attack_range = A.Call( bot, "GetAttackRange" ), attack_cycle_s = A.Call( bot, "GetSecondsPerAttack" ),
        projectile_speed = A.Call( bot, "GetAttackProjectileSpeed" ), spell_amp = A.Call( bot, "GetSpellAmp" ),
        attack_point_observed = A.Call( bot, "GetAttackPoint" ), last_attack_record = A.Call( bot, "GetLastAttackTime" ),
        current_action_type = A.Call( bot, "GetCurrentActionType" ) };
    if not A.Number( h.level ) then return nil, "own_level_missing" end;
    if ctx.cfg.probes.attack_point_seconds_verified and A.Number( h.attack_point_observed ) and h.attack_point_observed >= 0
        and A.Number( h.attack_cycle_s ) and h.attack_cycle_s > 0 and h.attack_point_observed <= h.attack_cycle_s
        and A.Number( h.projectile_speed ) and h.projectile_speed > 0 then h.attack_point_s = h.attack_point_observed end;
    h.souls = A.Stacks( bot, ctx.cfg.soul_modifier, ctx.cfg.probes.modifier_bindings_verified );
    local missing = {};
    h.alive = bool( bot, "IsAlive", missing );
    h.disabled = bool( bot, "IsStunned", missing ) or bool( bot, "IsHexed", missing );
    h.disarmed, h.silenced = bool( bot, "IsDisarmed", missing ), bool( bot, "IsSilenced", missing );
    local using, phase, channel = bool( bot, "IsUsingAbility", missing ), bool( bot, "IsCastingAbility", missing ), bool( bot, "IsChanneling", missing );
    h.casting = using or phase or channel;
    local s = { time = now, snapshot_time = now, run_id = ctx.cfg.run_id, build = ctx.cfg.build,
        observation_id = "obs:" .. ctx.observations, hero = h, targets = {}, razes = {}, towers = {}, tower_shots = {},
        enemy_knowledge = {}, capabilities = { cross_raze_timing_verified = ctx.cfg.probes.cross_raze_timing_verified },
        schedule_verified = false, wave = {}, xp_rules = { verified = ctx.cfg.probes.xp_rules_verified, radius = ctx.cfg.probes.xp_radius },
        probe = { own_modifiers = A.Modifiers( bot ), missing_methods = missing },
        last_hits = A.Call( bot, "GetLastHits" ), denies = A.Call( bot, "GetDenies" ),
        outcome_attribution = "not_attributed" };
    local mode = A.Call( bot, "GetActiveMode" );
    h.active_mode = mode;
    s.danger = not h.alive or h.disabled or hp / maxHP < ctx.cfg.yield_hp_fraction or #missing > 0
        or ( BOT_MODE_RETREAT ~= nil and mode == BOT_MODE_RETREAT );
    for i = 1, 3 do
        local name = "nevermore_shadowraze" .. i;
        local ability = A.Call( bot, "GetAbilityByName", name );
        if ability then
            local noTarget = A.HasBit( A.Call( ability, "GetBehavior" ), DOTA_ABILITY_BEHAVIOR_NO_TARGET );
            local ok, profile = pcall( Profiles.ReadRaze, ability, { no_target_verified = noTarget,
                geometry_verified = ctx.cfg.probes.raze_geometry_verified, build = ctx.cfg.build } );
            if ok and profile then
                profile.silenced = h.silenced; s.razes[name], ctx.abilities[name] = profile, ability;
            end
        end
    end
    local scanOK = true;
    for _, group in ipairs( { { "GetNearbyLaneCreeps", true, "enemy_creep" }, { "GetNearbyLaneCreeps", false, "allied_creep" },
        { "GetNearbyHeroes", true, "enemy_hero" } } ) do
        local units;
        if group[1] == "GetNearbyHeroes" then units = A.Call( bot, group[1], ctx.cfg.scan_radius, group[2], BOT_MODE_NONE );
        else units = A.Call( bot, group[1], ctx.cfg.scan_radius, group[2] ) end;
        if type( units ) ~= "table" then scanOK = false; units = {} end;
        for _, unit in ipairs( units ) do
            if #s.targets < 48 then local t = target( ctx, bot, unit, group[3], s ); if t then s.targets[#s.targets + 1] = t end end;
        end
    end
    s.enemy_visible = false;
    for _, t in ipairs( s.targets ) do
        if t.kind == "enemy_hero" then s.enemy_visible = true end;
        if t.kind == "allied_creep" and t.creep_type == "siege" then s.wave.allied_siege_visible, s.wave.allied_siege_alive = true, true end;
    end
    for id in pairs( ctx.memory.enemies ) do
        local visible = ctx.handles[id] ~= nil;
        s.enemy_knowledge[#s.enemy_knowledge + 1] = Knowledge.Read( ctx.memory, id, now, visible );
    end
    table.sort( s.enemy_knowledge, function( a, b ) return a.id < b.id end );
    for _, enemy in ipairs( { false, true } ) do
        local towers = A.Call( bot, "GetNearbyTowers", ctx.cfg.scan_radius, enemy );
        if type( towers ) ~= "table" then scanOK = false; towers = {} end;
        for _, tower in ipairs( towers ) do
            if A.Visible( tower ) then
                local pos = A.Position( tower );
                if pos then
                    local id = M.ID( ctx, tower ); local range = A.Call( tower, "GetAttackRange" );
                    local victim = A.Call( tower, "GetAttackTarget" );
                    local t = { id = id, x = pos.x, y = pos.y, enemy = enemy, alive = true, visible = true,
                        attack_range = range, range_verified = A.Number( range ) and range > 0,
                        range_margin = 150, target_id = victim == bot and h.id or ( A.Visible( victim ) and M.ID( ctx, victim ) or nil ),
                        seconds_per_attack = A.Call( tower, "GetSecondsPerAttack" ), damage_by_target = {} };
                    if ctx.cfg.probes.tower_damage_verified then
                        local q = M.AttackEstimate( tower, bot, ctx.cfg ); if q then t.damage_by_target[h.id] = q end;
                        for _, unit in ipairs( s.targets ) do
                            local q2 = M.AttackEstimate( tower, ctx.handles[unit.id], ctx.cfg ); if q2 then t.damage_by_target[unit.id] = q2 end;
                        end
                    end
                    s.towers[#s.towers + 1] = t;
                end
            end
        end
    end
    s.tower_context_verified = scanOK;
    s.probe.scan_complete = scanOK;
    if not scanOK then s.danger = true end;
    if type( GetLaneFrontLocation ) == "function" and LANE_MID ~= nil then
        local ok, v = pcall( GetLaneFrontLocation, A.Call( bot, "GetTeam" ), LANE_MID, ctx.cfg.anchor_offset );
        if ok and v and A.Number( v.x ) and A.Number( v.y ) then s.lane_anchor = { x = v.x, y = v.y } end;
    end
    return s;
end
return M;
