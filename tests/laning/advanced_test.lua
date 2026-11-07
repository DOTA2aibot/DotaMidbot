local nativeRequire = require;
local modules = {};
GetScriptDirectory = function() return "bots" end;
require = function( path )
    if not path:match( "^bots/" ) then return nativeRequire( path ) end;
    local localPath = path:gsub( "^bots/", "" );
    if not modules[localPath] then modules[localPath] = assert( loadfile( localPath .. ".lua" ) )() end;
    return modules[localPath];
end;
local K = require( "bots/laning/advanced/knowledge" );
local D = require( "bots/laning/advanced/mechanics" );
local W = require( "bots/laning/advanced/wave" );
local P = require( "bots/laning/advanced/planner" );
local S = require( "bots/laning/advanced/scheduler" );
local C = require( "bots/laning/advanced/config" );
local Runtime = require( "bots/laning/advanced/runtime_profile" );
local Threat = require( "bots/laning/advanced/threat" );
local Bridge = require( "bots/laning/advanced/bridge" );
local FullTrace = require( "bots/laning/advanced/trace" );
local passed = 0;
local function eq( a, b ) assert( a == b, tostring( a ) .. " ~= " .. tostring( b ) ) end;
local function approx( a, b ) assert( math.abs( a - b ) < 0.00001, tostring( a ) .. " != " .. tostring( b ) ) end;
local function test( name, fn ) fn(); passed = passed + 1; print( "PASS OPTIONS " .. name ) end;
local function fixture()
    -- Синтетические damage/mana-values: проверка механики, не патчевые константы.
    local s = { time = 100, enemy_visible = true, schedule_verified = true,
        hero = { x = 0, y = 0, mana = 200, max_mana = 300, hp = 800, max_hp = 1000,
            hp_fraction = 0.8, level = 3, souls = 10, max_souls = 20, souls_per_creep = 1,
            attack_range = 550, attack_point_s = 0.3, attack_cycle_s = 1.4,
            projectile_speed = 1000, spell_amp = 0 },
        run_id = "fixture", build = "mock", observation_id = "obs-1",
        targets = {}, razes = {}, capabilities = { joint_executor = true, cross_raze_timing_verified = true }, wave = {} };
    for i, range in ipairs( { 200, 450, 700 } ) do
        s.razes["r" .. i] = { id = "r" .. i, learned = true, base_damage = 40,
            damage_per_soul = 2, stack_bonus = 10, stack_duration_s = 6,
            range = range, radius = 250, mana_cost = 30, cast_point_s = 0.55,
            ready_in_s = 0, cooldown_s = 9, no_target_verified = true, geometry_verified = true };
    end
    local creep = { id = "c", kind = "enemy_creep", x = 450, y = 0, visible = true, alive = true,
        hp = 100, max_hp = 300, attack_damage_effective = 55, magic_multiplier = 1, creep_type = "ranged",
        raze_stacks = 0, is_ranged = true };
    local hero = { id = "h", kind = "enemy_hero", x = 450, y = 0, visible = true, alive = true,
        hp = 1000, max_hp = 1000, attack_damage_effective = 55, magic_multiplier = 1, raze_stacks = 0 };
    s.targets = { creep, hero }; return s;
end
local function evaluate( s, steps ) return P.Evaluate( s, { option_id = 8, option_key = "fixture", candidate_key = "p", steps = steps }, C ) end;
local function raze( id, target ) return { kind = "raze", ability_id = id, target_id = target or "h" } end;
local function attack( target ) return { kind = "attack", target_id = target or "h" } end;

test( "visible observations only and stale mana is not current mana", function()
    local m = K.New(); K.Observe( m, "e", { visible = true, hp = 300, max_hp = 600, mana = 20 }, 1 );
    eq( K.Observe( m, "e", { visible = false, hp = 1, mana = 900 }, 2 ), false );
    local e = K.Read( m, "e", 2, false ); eq( e.mana, 20 ); eq( e.resource_status, "last_seen" );
    eq( K.ThreatFeatures( e, 50 ).observed_mana, nil );
end );
test( "enemy cooldown is estimate, reset remains possible", function()
    local m = K.New();
    eq( K.ObserveCast( m, "e", "nuke", { source = "hidden_handle", confirmed_release = true, at = 0 } ), false );
    assert( K.ObserveCast( m, "e", "nuke", { source = "visible_cast", confirmed_release = true, at = 1, cooldown_low = 8, cooldown_high = 10 } ) );
    local cd = K.Read( m, "e", 4, false ).spells.nuke;
    eq( cd.nominal_remaining_low, 5 ); eq( cd.nominal_remaining_high, 7 ); eq( cd.ready_possible, true );
end );
test( "observed lack of mana is distinct from unknown", function()
    local e = { resource_status = "observed", mana = 20, spells = {} };
    local f = K.ThreatFeatures( e, 50 ); eq( f.mana_sufficient, false ); eq( f.insufficient_mana_observed, true );
end );
test( "raze uses target stacks and souls, attack total is not doubled", function()
    local s = fixture(); approx( D.RazeRaw( s.razes.r1, 10, 2, 0 ), 80 );
    approx( D.AttackDamage( s.hero, s.targets[2] ), 55 );
end );
test( "stack expiry and unknown stacks", function()
    eq( D.StacksAt( { raze_stacks = 2, stack_expires_at = 101 }, 102 ), 0 );
    eq( D.StacksAt( { raze_stacks = 2 }, 100 ), nil );
end );
test( "no phantom armor reduction or unknown magic damage", function()
    eq( D.MagicDamage( 100, { magic_multiplier = 0.75 } ), 75 );
    eq( D.MagicDamage( 100, { magic_multiplier = 0.75, nonlinear_damage_unknown = true } ), nil );
end );
test( "two razes ramp on same target only", function()
    local s = fixture(); s.targets = { s.targets[2] };
    local p = evaluate( s, { raze( "r1" ), raze( "r2" ) } ); assert( p.available ); approx( p.features.hero_damage, 130 );
    s.targets[1].stack_expires_at, s.targets[1].raze_stacks = 101, 2;
    s.razes.r2.ready_in_s = 2;
    p = evaluate( s, { raze( "r1" ), raze( "r2" ) } ); assert( p.available ); approx( p.features.hero_damage, 170 );
end );
test( "triple raze candidate exists with stable option ID", function()
    local s = fixture(); local out = P.Build( s, C ); local found = false;
    for _, p in ipairs( out.candidates ) do if p.option_id == 8 and #p.steps == 3 and p.available then found = true end end;
    assert( found ); eq( out.option_catalog[9].id, 8 );
end );
test( "one AoE can secure a creep and damage hero", function()
    local s = fixture(); s.targets[1].hp = 50;
    local p = evaluate( s, { raze( "r2", "c" ) } ); assert( p.available );
    eq( p.features.secured_creeps, 1 ); approx( p.features.hero_damage, 60 );
end );
test( "attack projectile can land AFTER following raze", function()
    local s = fixture(); s.hero.projectile_speed = 300;
    local p = evaluate( s, { attack(), raze( "r2" ) } ); assert( p.available );
    eq( p.events[1].kind, "raze" ); eq( p.events[2].kind, "attack" );
    assert( p.events[2].release_at < p.events[1].at );
end );
test( "separate targets can be assigned to cast and attack", function()
    local s = fixture(); s.targets[1].hp = 50;
    local p = evaluate( s, { raze( "r2", "c" ), attack( "h" ) } );
    assert( p.available ); eq( p.features.secured_creeps, 1 ); approx( p.features.hero_damage, 115 );
end );
test( "insufficient mana masks whole chain", function()
    local s = fixture(); s.hero.mana = 50;
    local p = evaluate( s, { raze( "r1" ), raze( "r2" ) } ); eq( p.available, false ); eq( p.mask_reason, "insufficient_mana" );
end );
test( "cooldown and geometry are checked independently", function()
    local s = fixture(); s.razes.r1.ready_in_s = 10;
    eq( evaluate( s, { raze( "r1" ) } ).available, false );
    s.razes.r1.ready_in_s = 0; s.targets[2].y = 900;
    eq( evaluate( s, { raze( "r1" ) } ).mask_reason, "raze_geometry_miss" );
end );
test( "runtime integration masks combos but keeps catalog IDs", function()
    local s = fixture(); s.capabilities.joint_executor = false;
    local out = P.Build( s, C ); eq( out.option_masks[8].available, false );
    eq( out.option_masks[17].available, true ); eq( #out.option_catalog, 25 );
    assert( out.option_masks[8].reasons.joint_executor_not_integrated );
end );
test( "invisible targets never become damage candidates", function()
    local s = fixture(); s.targets[2].visible = false;
    eq( evaluate( s, { attack( "h" ) } ).mask_reason, "target_not_observed" );
end );
test( "first wave may be deliberately shoved for level two", function()
    local s = fixture(); s.hero.level = 1; s.wave = { is_first_wave = true, level_two_race = true };
    eq( W.Context( s, C ).push_allowed, true ); eq( W.Context( s, C ).goal, "level_two_race" );
end );
test( "rune push conditional on clear and travel feasibility", function()
    local s = fixture(); s.time = 100; s.rune = { next_spawn_at = 120, spawn_type_known = true };
    s.wave.can_clear_and_reach_rune = true; eq( W.Context( s, C ).goal, "prepare_rune" );
    s.wave.can_clear_and_reach_rune = false; eq( W.Context( s, C ).push_allowed, false );
    s.wave.can_clear_and_reach_rune = true; s.schedule_verified = false; eq( W.Context( s, C ).push_allowed, false );
end );
test( "minute five does not invent a visible siege creep", function()
    local s = fixture(); s.time = 300; eq( W.Context( s, C ).push_allowed, false );
    s.wave = { allied_siege_visible = true, allied_siege_alive = true, siege_pressure_viable = true };
    eq( W.Context( s, C ).goal, "siege_pressure" );
end );
test( "missing enemy and low HP suppress push without hidden resource reads", function()
    local s = fixture(); s.enemy_visible = false; s.hero.hp_fraction = 0.4;
    s.wave = { is_first_wave = true, level_two_race = true }; s.hero.level = 1;
    eq( W.Context( s, C ).reason, "unsafe_push" );
end );
test( "emergency masks plans and selects abort", function()
    local s = fixture(); s.danger = true; local out = P.Build( s, C ); eq( out.selected.option_id, 14 );
end );
test( "scheduler cannot cancel attack windup by casting early", function()
    local s = fixture(); local p = evaluate( s, { attack(), raze( "r2" ) } );
    local scheduler = S.New(); assert( S.Begin( scheduler, 7, "joint", p, 100, C, s.capabilities ) );
    local o = { time = 100, snapshot_time = 100, valid_targets = { h = true }, ability_ready = { r2 = true }, facing_ready = true, geometry_valid = true };
    local submitted = S.Next( scheduler, o, C ); eq( submitted.status, "submit" );
    eq( S.Next( scheduler, o, C ).status, "waiting_event" );
    local ok = S.Event( scheduler, { actor = 7, step_id = 1, plan_id = submitted.plan_id, status = "api_submitted" } ); eq( ok, false );
    assert( S.Event( scheduler, { actor = 7, step_id = 1, plan_id = submitted.plan_id, status = "attack_released" } ) );
    eq( S.Next( scheduler, o, C ).step.kind, "raze" );
end );
test( "scheduler rechecks mana/cd, facing and stale snapshots", function()
    local s = fixture(); local p = evaluate( s, { raze( "r2" ) } ); local scheduler = S.New();
    S.Begin( scheduler, 7, "joint", p, 100, C, s.capabilities );
    local o = { time = 100, snapshot_time = 100, valid_targets = { h = true }, ability_ready = { r2 = true }, facing_ready = false, geometry_valid = true };
    eq( S.Next( scheduler, o, C ).status, "need_face_then_reobserve" );
    o.facing_ready = true; o.ability_ready.r2 = false; eq( S.Next( scheduler, o, C ).reason, "cooldown_or_mana_changed" );
    S.Begin( scheduler, 7, "joint", p, 100, C, s.capabilities ); o.time = 101;
    eq( S.Next( scheduler, o, C ).reason, "stale_snapshot" );
end );
test( "two callbacks cannot claim same actor concurrently", function()
    local scheduler = S.New(); assert( S.Claim( scheduler, 7, "lane", "p", 100, 3 ) );
    local ok, reason = S.Claim( scheduler, 7, "abilities", "q", 101, 3 ); eq( ok, false ); eq( reason, "actor_already_owned" );
    assert( S.Claim( scheduler, 7, "abilities", "q", 104, 3 ) );
end );
test( "own runtime profile reads AbilityValues not GetAbilityDamage zero", function()
    local values = { shadowraze_damage = 40, damage_per_soul = 2, stack_bonus_damage = 10,
        duration = 6, shadowraze_range = 450, shadowraze_radius = 250 };
    local ability = { GetName = function() return "r2" end, GetLevel = function() return 1 end,
        GetSpecialValueFloat = function( _, name ) return values[name] or 0 end,
        GetManaCost = function() return 30 end, GetCastPoint = function() return 0.55 end,
        GetCooldownTimeRemaining = function() return 0 end, GetCooldown = function() return 9 end };
    local p = Runtime.ReadRaze( ability, { no_target_verified = true, geometry_verified = true, build = "fixture" } );
    eq( p.base_damage, 40 ); eq( p.mana_cost, 30 );
    values.shadowraze_damage = 0; local bad = Runtime.ReadRaze( ability ); eq( bad, nil );
end );
test( "enemy observed mana and cooldown change risk features", function()
    local s = fixture(); s.enemy_knowledge = { { id = "h", visible = true, resource_status = "observed",
        mana = 20, spellbook_complete = true, known_threats = { nuke = { mana_cost = 50, damage_estimate = 200 } }, spells = {} } };
    eq( Threat.Estimate( s, 1, C ).damage_budget, 0 );
    s.enemy_knowledge[1].mana = 100; eq( Threat.Estimate( s, 1, C ).damage_budget, 200 );
    s.enemy_knowledge[1].spells.nuke = { status = "estimated", nominal_remaining_low = 5 };
    eq( Threat.Estimate( s, 1, C ).damage_budget, 100 );
    s.enemy_knowledge[1].visible = false; eq( Threat.Estimate( s, 1, C ).unknown, true );
end );
test( "stack damage does not transfer to a different target", function()
    local s = fixture(); s.targets[1].hp = 1000; s.targets[1].kind = "enemy_hero";
    s.targets[1].x, s.targets[1].y = 0, 450;
    local p = evaluate( s, { raze( "r2", "h" ), raze( "r2", "c" ) } );
    eq( p.available, false ); -- тот же рейз на CD, нельзя изобрести второй каст
    p = evaluate( s, { raze( "r2", "h" ), raze( "r1", "c" ) } );
    assert( p.available ); approx( p.features.hero_damage, 120 );
end );
test( "stable mask IDs and candidate order after input target permutation", function()
    local s = fixture(); local a = P.Build( s, C ); s.targets = { s.targets[2], s.targets[1] };
    local b = P.Build( s, C ); eq( #a.candidates, #b.candidates );
    for i, p in ipairs( a.candidates ) do eq( p.candidate_key, b.candidates[i].candidate_key ) end;
    eq( a.option_masks[19].available, false ); assert( a.option_masks[19].reasons.movement_and_geometry_probe_pending );
end );
test( "predicted kills are not emitted as confirmed reward", function()
    local s = fixture(); s.targets[1].hp = 30; local p = evaluate( s, { attack( "c" ) } );
    eq( p.features.secured_creeps, 1 ); eq( p.predictions_are_outcomes, false );
    local out = P.Build( s, C ); eq( out.learning_reward, nil );
    local encoded = FullTrace.Encode( FullTrace.Record( s, out, { status = "submitted" } ) );
    ADVANCED_RECORD_SAMPLE = encoded;
    assert( encoded:find( '"reward_status":"not_defined"', 1, true ) );
end );
test( "scheduler rejects wrong event and active-plan overwrite", function()
    local s = fixture(); local p = evaluate( s, { attack() } ); local scheduler = S.New();
    S.Begin( scheduler, 7, "joint", p, 100, C, s.capabilities );
    local ok, reason = S.Begin( scheduler, 7, "joint", p, 100, C, s.capabilities );
    eq( ok, false ); eq( reason, "plan_already_active" );
    eq( S.Event( scheduler, { actor = 8, step_id = 1, plan_id = "p", status = "attack_released" } ), false );
end );
test( "late release from previous execution cannot advance repeated candidate", function()
    local s = fixture(); local p = evaluate( s, { attack() } ); local scheduler = S.New();
    local o = { time = 100, snapshot_time = 100, valid_targets = { h = true } };
    assert( S.Begin( scheduler, 7, "joint", p, 100, C, s.capabilities ) );
    local old = S.Next( scheduler, o, C ); eq( old.status, "submit" );
    S.Abort( scheduler, "cancelled" );
    assert( S.Begin( scheduler, 7, "joint", p, 100, C, s.capabilities ) );
    local current = S.Next( scheduler, o, C ); assert( current.plan_id ~= old.plan_id );
    eq( S.Event( scheduler, { actor = 7, step_id = 1, plan_id = old.plan_id, status = "attack_released" } ), false );
    eq( S.Next( scheduler, o, C ).status, "waiting_event" );
    assert( S.Event( scheduler, { actor = 7, step_id = 1, plan_id = current.plan_id, status = "attack_released" } ) );
    eq( S.Next( scheduler, o, C ).status, "plan_finished" );
end );
test( "bridge handshake is required and rejected submission remains aborted", function()
    local s = fixture(); local bot = { GetPlayerID = function() return 77 end };
    eq( Bridge.IsReady( 77 ), false ); eq( Bridge.Desire( bot ), 0 );
    eq( Bridge.Register( 77, { schema = C.schema, joint_executor_verified = false } ), false );
    local records = {};
    local backend = { schema = C.schema, joint_executor_verified = true,
        Snapshot = function() return s end,
        Events = function() return {} end,
        Validate = function() return { time = s.time, snapshot_time = s.time, valid_targets = { h = true, c = true },
            ability_ready = { r1 = true, r2 = true, r3 = true }, facing_ready = true, geometry_valid = true } end,
        Submit = function() return false, "fixture_api_reject" end,
        Record = function( _, _, event ) records[#records + 1] = event end,
    };
    assert( Bridge.Register( 77, backend ) );
    eq( Bridge.Register( 77, backend ), false );
    local result = Bridge.Think( bot ); eq( result.status, "aborted" ); eq( result.reason, "fixture_api_reject" );
    eq( records[#records].status, "aborted" );
end );
test( "trace refuses nonserializable handles/functions", function()
    local ok = pcall( FullTrace.Encode, { handle = function() end } ); eq( ok, false );
    local cycle = {}; cycle.self = cycle; eq( pcall( FullTrace.Encode, cycle ), false );
end );
test( "projected soul gain is capped and temporary expiry affects spell damage", function()
    local s = fixture(); s.hero.souls = 20; s.targets[1].hp = 30;
    local p = evaluate( s, { raze( "r1" ), raze( "r2" ) } );
    assert( p.available ); approx( p.features.hero_damage, 170 ); -- 80+90, не 80+92
    s = fixture(); s.targets = { s.targets[2] }; s.hero.soul_expiry_events = { { at_s = 1, remove_at_most = 5 } };
    p = evaluate( s, { raze( "r1" ), raze( "r2" ) } ); assert( p.available ); approx( p.features.hero_damage, 120 );
end );
test( "expired item/buff damage window masks unsupported projection", function()
    local s = fixture(); s.hero.damage_projection_valid_until_s = 0.5;
    eq( evaluate( s, { raze( "r2" ) } ).mask_reason, "damage_effect_window_expired" );
end );
print( "ADVANCED PASSED " .. passed );
require = nativeRequire;
