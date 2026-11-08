-- Read-only observer. Handles хранятся отдельно от JSON; ошибок optional API не боимся.
local A = require( GetScriptDirectory() .. "/laning/runtime/api" );
local Trace = require( GetScriptDirectory() .. "/laning/advanced/trace" );
local C = require( GetScriptDirectory() .. "/laning/observer/config" );
local Profile = require( GetScriptDirectory() .. "/laning/profile" );
local M, states, serial = {}, setmetatable( {}, { __mode = "k" } ), 0;
function M.Global( name, ... )
    local fn = _G[name]; if type( fn ) ~= "function" then return nil end;
    local ok, value = pcall( fn, ... ); if ok then return value end;
end
function M.Height( p )
    if not p then return nil end;
    local ok, v = pcall( A.Vector, p ); if not ok or not v then return nil end;
    local h = M.Global( "GetHeightLevel", v );
    if A.Number( h ) and h >= 1 and h <= 5 then return h end;
end
function M.State( bot )
    local now = A.Time(); if not now then return nil end;
    local s = states[bot];
    if not s or now < s.last_time then
        serial = serial + 1;
        s = { next_sample = -math.huge, next_error = -math.huge, sequence = 0, action_sequence = 0,
            ids = setmetatable( {}, { __mode = "k" } ), id_count = 0, handles = {},
            run_id = C.run_prefix .. ":" .. tostring( A.Call( bot, "GetPlayerID" ) ) .. ":" .. serial .. ":" .. now };
        states[bot] = s;
    end;
    s.last_time = now; return s;
end
function M.ID( s, unit )
    if not s.ids[unit] then s.id_count = s.id_count + 1; s.ids[unit] = "u:" .. s.id_count end;
    return s.ids[unit];
end
function M.Emit( s, kind, data )
    -- Неудачная сериализация/печать не отменяет игровой callback.
    s.sequence = s.sequence + 1;
    local record = { schema = "midbot-observer-1", version = C.version, run_id = s.run_id,
        seq = s.sequence, time = A.Time(), kind = kind, profile = Profile.name,
        controller = Profile.controller, source_revision = Profile.source_revision or "uncommitted",
        observation_id = s.run_id .. ":record:" .. s.sequence, data = data, reward_status = "not_defined" };
    return pcall( function() print( "[MIDBOT observe] " .. Trace.Encode( record ) ) end );
end
function M.Action( bot, kind, ability, location, reason )
    local s = M.State( bot ); if not s then return end;
    local point;
    if location then
        local ok, value = pcall( function() return { x = location.x, y = location.y } end );
        if ok then point = value end;
    end;
    s.action_sequence = s.action_sequence + 1;
    local id = s.run_id .. ":action:" .. s.action_sequence;
    M.Emit( s, "action_submitted", { action_id = id, owner = kind == "ward" and "midbot_ward" or "midbot_ability", action = kind,
        ability = A.Call( ability, "GetName" ), location = point, reason = reason,
        outcome = "unknown", attribution = "submission_only" } );
    if kind == "cast" and s.before_action then
        s.pending_casts = s.pending_casts or {};
        s.pending_casts[id] = s.before_action;
    end;
    s.before_action = nil;
    return id;
end
function M.BeforeAction( bot, ability )
    local s = M.State( bot ); if not s then return end;
    s.before_action = { ability = ability, time = A.Time(), mana = A.Call( bot, "GetMana" ),
        cooldown = A.Call( ability, "GetCooldownTimeRemaining" ), cost = A.Call( ability, "GetManaCost" ) };
end
function M.PollCasts( bot, s )
    for id, p in pairs( s.pending_casts or {} ) do
        local cd, mana = A.Call( p.ability, "GetCooldownTimeRemaining" ), A.Call( bot, "GetMana" );
        local now = A.Time();
        if A.Number( cd ) and A.Number( p.cooldown ) and cd > p.cooldown + 0.001
            and A.Number( mana ) and A.Number( p.mana ) and A.Number( p.cost )
            and mana <= p.mana - p.cost + 1 and A.Call( bot, "IsUsingAbility" ) == false then
            M.Emit( s, "cast_consumption_observed", { action_id = id,
                evidence = "cooldown_and_mana_transition", hit = "unknown", kill = "unknown" } );
            s.pending_casts[id] = nil;
        elseif now and p.time and now - p.time > 3 then
            M.Emit( s, "cast_outcome_unknown", { action_id = id, evidence = "resource_confirmation_unavailable" } );
            s.pending_casts[id] = nil;
        end;
    end;
end
function M.PollAttacks( bot, s )
    local now = A.Time(); if not now or now < ( s.next_attack_poll or -math.huge ) then return end;
    s.next_attack_poll = now + C.attack_poll_s;
    local record, target = A.Call( bot, "GetLastAttackTime" ), A.Call( bot, "GetAttackTarget" );
    if not A.Number( record ) then return end;
    local near = 0; local origin = A.Position( bot );
    if A.Visible( target ) and origin then
        local incoming = A.Call( target, "GetIncomingTrackingProjectiles" );
        for _, p in ipairs( type( incoming ) == "table" and incoming or {} ) do
            if p.caster == bot and p.is_attack == true and p.location
                and A.Number( p.location.x ) and A.Number( p.location.y ) and A.Distance( origin, p.location ) <= 180 then near = near + 1 end;
        end;
    end;
    if s.native_record and record > s.native_record then
        local confirmed = target == s.native_target and near > ( s.native_near or 0 );
        M.Emit( s, confirmed and "attack_release_observed" or "attack_record_changed", {
            source = "native_or_unattributed", target_id = A.Visible( target ) and M.ID( s, target ) or nil,
            record_before = s.native_record, record_after = record,
            evidence = confirmed and "new_near_own_projectile_and_attack_record" or "timestamp_only_not_calibrated",
            hit = "unknown", kill = "unknown", count_status = "observed_lower_bound_not_total_attacks" } );
    end;
    s.native_record, s.native_target, s.native_near = record, target, near;
end
function M.Capture( bot, s )
    s = s or M.State( bot ); if not s then return nil end;
    s.handles = {};
    local p = A.Position( bot ); local own_height = M.Height( p );
    local id = A.Call( bot, "GetPlayerID" );
    local hero = { position = p, height_level = own_height, hp = A.Call( bot, "GetHealth" ),
        max_hp = A.Call( bot, "GetMaxHealth" ), mana = A.Call( bot, "GetMana" ), max_mana = A.Call( bot, "GetMaxMana" ),
        level = A.Call( bot, "GetLevel" ), gold = A.Call( bot, "GetGold" ), alive = A.Call( bot, "IsAlive" ),
        last_hits = A.Call( bot, "GetLastHits" ), denies = A.Call( bot, "GetDenies" ),
        kills = M.Global( "GetHeroKills", id ), deaths = M.Global( "GetHeroDeaths", id ),
        active_mode = A.Call( bot, "GetActiveMode" ), mode_desire = A.Call( bot, "GetActiveModeDesire" ),
        current_action = A.Call( bot, "GetCurrentActionType" ), last_attack_record = A.Call( bot, "GetLastAttackTime" ),
        attack_range = A.Call( bot, "GetAttackRange" ), attack_damage = A.Call( bot, "GetAttackDamage" ),
        attack_point = A.Call( bot, "GetAttackPoint" ), attack_cycle = A.Call( bot, "GetSecondsPerAttack" ),
        facing = A.Call( bot, "GetFacing" ), casting = A.Call( bot, "IsUsingAbility" ),
        channeling = A.Call( bot, "IsChanneling" ), silenced = A.Call( bot, "IsSilenced" ),
        stunned = A.Call( bot, "IsStunned" ), hexed = A.Call( bot, "IsHexed" ), disarmed = A.Call( bot, "IsDisarmed" ),
        modifiers = A.Modifiers( bot ), items = {}, abilities = {} };
    for _, modifier in ipairs( hero.modifiers ) do
        if modifier.name == "modifier_nevermore_necromastery" and A.Number( modifier.stacks ) then
            hero.souls = modifier.stacks;
        end;
    end; -- Нет наблюдаемого modifier binding — souls unknown, не ноль и не вывод о LH.
    for slot = 0, 14 do
        local item = A.Call( bot, "GetItemInSlot", slot );
        if item then hero.items[#hero.items + 1] = { slot = slot, name = A.Call( item, "GetName" ),
            charges = A.Call( item, "GetCurrentCharges" ), secondary_charges = A.Call( item, "GetSecondaryCharges" ),
            toggle = A.Call( item, "GetToggleState" ), castable = A.Call( item, "IsFullyCastable" ) } end;
    end;
    for _, name in ipairs( { "nevermore_shadowraze1", "nevermore_shadowraze2", "nevermore_shadowraze3", "nevermore_frenzy", "nevermore_requiem" } ) do
        local a = A.Call( bot, "GetAbilityByName", name );
        if a then hero.abilities[#hero.abilities + 1] = { name = name, level = A.Call( a, "GetLevel" ),
            cooldown = A.Call( a, "GetCooldownTimeRemaining" ), mana_cost = A.Call( a, "GetManaCost" ),
            castable = A.Call( a, "IsFullyCastable" ), phase = A.Call( a, "IsInAbilityPhase" ) } end;
    end;
    local targets, seen = {}, {};
    local function collect( list, kind )
        for _, unit in ipairs( type( list ) == "table" and list or {} ) do
            if #targets < C.max_targets and not seen[unit] and A.Visible( unit ) then
                seen[unit] = true;
                local pos = A.Position( unit ); local height = M.Height( pos ); local uid = M.ID( s, unit );
                local uphill; if height and own_height then uphill = height > own_height end;
                local raw, variance = hero.attack_damage, A.Call( bot, "GetBaseDamageVariance" );
                local prof = A.Call( bot, "GetAttackCombatProficiency", unit ); local damage;
                if A.Number( raw ) and A.Number( variance ) and A.Number( prof ) and DAMAGE_TYPE_PHYSICAL ~= nil then
                    damage = A.Call( unit, "GetActualIncomingDamage", math.max( 0, raw - variance ) * prof, DAMAGE_TYPE_PHYSICAL );
                end;
                targets[#targets + 1] = { id = uid, kind = kind, name = A.Call( unit, "GetUnitName" ),
                    position = pos, height_level = height, uphill = uphill, visible = true,
                    hp = A.Call( unit, "GetHealth" ), max_hp = A.Call( unit, "GetMaxHealth" ),
                    mana = A.Call( unit, "GetMana" ), regen = A.Call( unit, "GetHealthRegen" ),
                    armor = A.Call( unit, "GetArmor" ), evasion = A.Call( unit, "GetEvasion" ),
                    attack_immune = A.Call( unit, "IsAttackImmune" ), invulnerable = A.Call( unit, "IsInvulnerable" ),
                    magic_immune = A.Call( unit, "IsMagicImmune" ), modifiers = A.Modifiers( unit ),
                    attack_damage_estimate = damage, damage_status = "engine_query_uncalibrated",
                    bounty_min = A.Call( unit, "GetBountyGoldMin" ), bounty_max = A.Call( unit, "GetBountyGoldMax" ) };
                s.handles[uid] = unit;
            end;
        end;
    end;
    collect( A.Call( bot, "GetNearbyHeroes", C.radius, true, BOT_MODE_NONE ), "enemy_hero" );
    collect( A.Call( bot, "GetNearbyLaneCreeps", C.radius, true ), "enemy_creep" );
    collect( A.Call( bot, "GetNearbyLaneCreeps", C.radius, false ), "allied_creep" );
    local attack_target = A.Call( bot, "GetAttackTarget" );
    if attack_target and A.Visible( attack_target ) then hero.attack_target_id = M.ID( s, attack_target ) end;
    return { hero = hero, targets = targets, height_status = own_height and "observed" or "unavailable",
        targets_truncated = #targets >= C.max_targets, field_absence = "unknown_not_zero",
        attack_owner = "native_or_unattributed", ability_owner = "midbot_rules" };
end
return M;
