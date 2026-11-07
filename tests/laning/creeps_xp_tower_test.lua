local nativeRequire, modules = require, {};
GetScriptDirectory = function() return "bots" end;
require = function( path )
    if not path:match( "^bots/" ) then return nativeRequire( path ) end;
    local p = path:gsub( "^bots/", "" );
    if not modules[p] then modules[p] = assert( loadfile( p .. ".lua" ) )() end;
    return modules[p];
end;
local Cr = require( "bots/laning/advanced/creeps" );
local X = require( "bots/laning/advanced/experience" );
local T = require( "bots/laning/advanced/tower" );
local D = require( "bots/laning/advanced/mechanics" );
local P = require( "bots/laning/advanced/planner" );
local R = require( "bots/laning/advanced/runtime_profile" );
local S = require( "bots/laning/advanced/scheduler" );
local C = require( "bots/laning/advanced/config" );
local Trace = require( "bots/laning/advanced/trace" );
local count = 0;
local function eq( a, b ) assert( a == b, tostring( a ) .. " ~= " .. tostring( b ) ) end;
local function near( a, b ) assert( math.abs( a - b ) < 0.00001, tostring( a ) .. " != " .. tostring( b ) ) end;
local function test( name, fn ) fn(); count = count + 1; print( "PASS CREEPS_XP_TOWER " .. name ) end;
local function fixture()
    local s = { time = 100, enemy_visible = true, tower_context_verified = true,
        hero = { id = "self", alive = true, x = 0, y = 0, mana = 100, max_mana = 100, mana_regen = 0,
            hp = 500, max_hp = 1000, hp_fraction = 0.5, level = 2, souls = 10, max_souls = 20,
            souls_per_creep = 1, attack_range = 550, attack_point_s = 0.3, attack_cycle_s = 1.4, projectile_speed = 1000,
            xp_needed_to_level = 30 },
        targets = {}, razes = {}, capabilities = { joint_executor = true, cross_raze_timing_verified = true },
        xp_rules = { verified = true, radius = 1500 }, wave = {}, towers = {}, tower_shots = {} };
    s.targets[1] = { id = "c", kind = "enemy_creep", creep_type = "melee", x = 450, y = 0, visible = true,
        alive = true, hp = 100, max_hp = 550, regen = 0, attack_damage_effective = 55, magic_multiplier = 1,
        raze_stacks = 0, bounty_gold_min = 30, bounty_gold_max = 40, bounty_xp = 60,
        xp_allied_recipients = 1, xp_recipients_verified = true, xp_factor = 1 };
    for i, range in ipairs( { 200, 450, 700 } ) do
        s.razes["r" .. i] = { learned = true, base_damage = 40, damage_per_soul = 2, stack_bonus = 10, stack_duration_s = 6,
            range = range, radius = 250, mana_cost = 30, cast_point_s = 0.55, ready_in_s = 0, cooldown_s = 9,
            no_target_verified = true, geometry_verified = true };
    end
    return s;
end
local function attack() return { kind = "attack", target_id = "c" } end;
local function raze( i ) return { kind = "raze", ability_id = "r" .. i, target_id = "c" } end;
local function evaluate( s, steps ) return P.Evaluate( s, { option_id = 8, option_key = "fixture", candidate_key = "fixture", steps = steps }, C ) end;
local function shot( id, at, low, high ) return { attack_id = id, target_id = "c", source = "observed_projectile", released = true,
    impact_time_verified = true, at_s = at, damage_min = low, damage_max = high or low } end;

test( "both teams and all upgrades keep melee ranged flagbearer siege distinct", function()
    for _, team in ipairs( { "goodguys", "badguys" } ) do
        for _, suffix in ipairs( { "", "_upgraded", "_upgraded_mega" } ) do
            for _, subtype in ipairs( { "melee", "ranged", "flagbearer", "siege" } ) do
                local name = subtype == "siege" and "npc_dota_" .. team .. "_siege" .. suffix
                    or "npc_dota_creep_" .. team .. "_" .. subtype .. suffix;
                eq( Cr.Classify( name ), subtype );
            end
        end
    end
    eq( Cr.Classify( "npc_dota_goodguys_siege_diretide" ), "unknown" );
    eq( Cr.Type( { is_ranged = true, attack_range = 690 } ), "unknown" );
end );
test( "visible getters read actual creep stats and bounty without type defaults", function()
    local u = { CanBeSeen = function() return true end, GetUnitName = function() return "npc_dota_goodguys_siege" end,
        GetHealth = function() return 123 end, GetMaxHealth = function() return 1111 end,
        GetBountyGoldMin = function() return 59 end, GetBountyGoldMax = function() return 72 end, GetBountyXP = function() return 88 end };
    local p = Cr.Observe( u ); eq( p.hp, 123 ); eq( p.max_hp, 1111 ); eq( p.creep_type, "siege" ); eq( p.is_ranged, false );
    u.CanBeSeen = function() return false end; eq( Cr.Observe( u ), nil );
end );
test( "equal raw raze has different outcomes after individual creep resistance", function()
    for _, pair in ipairs( { { "melee", 1, 1 }, { "flagbearer", 0.6, 0 }, { "siege", 0.2, 0 } } ) do
        local s = fixture(); s.targets[1].hp = 50; s.targets[1].creep_type = pair[1]; s.targets[1].magic_multiplier = pair[2];
        local p = evaluate( s, { raze( 2 ) } ); assert( p.available ); eq( p.features.secured_creeps, pair[3] );
    end
end );
test( "attack plus stacked raze can secure protected creep while single raze cannot", function()
    local s = fixture(); s.targets[1].creep_type = "flagbearer"; s.targets[1].magic_multiplier = 0.6; s.targets[1].raze_stacks = 1;
    s.targets[1].stack_expires_at = 106; s.targets[1].hp = 90;
    eq( evaluate( s, { raze( 2 ) } ).features.secured_creeps, 0 );
    eq( evaluate( s, { attack(), raze( 2 ) } ).features.secured_creeps, 1 );
end );
test( "gold interval and subtype stay separate from confirmed reward", function()
    local s = fixture(); s.targets[1].hp = 30; s.targets[1].creep_type = "siege";
    local p = evaluate( s, { attack() } ); eq( p.features.gold_min, 30 ); eq( p.features.gold_max, 40 );
    eq( p.features.secured_by_type.siege, 1 ); eq( p.features.ranged_secured, 0 ); eq( p.predictions_are_outcomes, false );
    s.targets[1].bounty_gold_min = nil; eq( evaluate( s, { attack() } ).features.gold_unknown_kills, 1 );
end );
test( "arbitrary nonlinear magic query does not reuse an average resistance", function()
    eq( D.MagicDamage( 60, { nonlinear_damage_unknown = true, magic_damage_by_raw = { ["60"] = 17 } } ), 17 );
    eq( D.MagicDamage( 70, { nonlinear_damage_unknown = true, magic_damage_by_raw = { ["60"] = 17 } } ), nil );
end );
test( "flag death changes later damage only after verified aura linger", function()
    local s = fixture(); local t = s.targets[1]; t.defense_dependencies_verified = true;
    t.defense_dependencies = { { source_id = "flag", linger_s = 0.5 } };
    t.magic_multiplier, t.regen = 0.6, 3;
    t.defense_after_deaths = { flag = { magic_multiplier = 1, attack_damage_effective = 55, regen = 0 } };
    local deaths = { flag = { at = 0.25, kind = "enemy_creep" } };
    eq( Cr.DefenseView( t, 0.7, deaths ).magic_multiplier, 0.6 );
    eq( Cr.DefenseView( t, 0.8, deaths ).magic_multiplier, 1 );
    near( Cr.HPUpperAt( t, 1, deaths ), 102.25 ); -- regen 3 только до 0.75
end );
test( "unknown aura transitions mask a chain rather than invent resistance", function()
    local s = fixture(); local flag = s.targets[1]; flag.id, flag.creep_type, flag.hp = "flag", "flagbearer", 30;
    local t = fixture().targets[1]; t.hp = 200; s.targets[2] = t;
    local p = evaluate( s, { { kind = "raze", ability_id = "r1", target_id = "flag" }, raze( 2 ) } );
    eq( p.available, false ); eq( p.mask_reason, "flag_aura_dependencies_unknown" );
    t.defense_dependencies_verified, t.defense_dependencies = true, {}; assert( evaluate( s, { { kind = "raze", ability_id = "r1", target_id = "flag" }, raze( 2 ) } ).available );
end );
test( "own mana regen is capped and unavailable mana cannot fund a spell", function()
    local s = fixture(); s.hero.mana, s.hero.max_mana, s.hero.mana_regen = 60, 60, 100;
    s.razes.r1.ready_in_s = 1; s.razes.r1.mana_cost = 70;
    eq( evaluate( s, { raze( 1 ) } ).mask_reason, "insufficient_mana" );
    s.hero.mana, s.hero.max_mana = 20, 100; s.razes.r1.mana_cost = 30;
    local p = evaluate( s, { raze( 1 ) } ); assert( p.available ); assert( p.mana_after_estimate <= 100 );
end );
test( "own resources include mana and XP needed to level", function()
    local b = {};
    for k, v in pairs( { GetMana = 10, GetMaxMana = 100, GetManaRegen = 2, GetHealth = 500, GetMaxHealth = 800,
        IsAlive = true, GetLevel = 2, GetXPNeededToLevel = 45 } ) do local value = v; b[k] = function() return value end end;
    local p = R.ReadOwnResources( b ); eq( p.mana, 10 ); eq( p.mana_regen, 2 ); eq( p.xp_needed_to_level, 45 );
end );
test( "XP eligibility depends on death position not attack or spell range", function()
    local s = fixture(); s.targets[1].x = 1400;
    local r = X.AtDeath( s, s.targets[1], 0.5 ); eq( r.xp, 60 ); eq( r.eligible, true );
    s.targets[1].x = 1600; eq( X.AtDeath( s, s.targets[1], 0.5 ).status, "outside" );
end );
test( "XP sharing modifiers and unknown scenario rules stay explicit", function()
    local s = fixture(); local t = s.targets[1]; t.xp_allied_recipients, t.xp_factor = 2, 0.5;
    eq( X.AtDeath( s, t, 0 ).xp, 15 );
    t.xp_factor = nil; eq( X.AtDeath( s, t, 0 ).status, "xp_modifiers_unknown" );
    s.xp_rules.verified = false; eq( X.AtDeath( s, t, 0 ).status, "xp_rules_unknown" );
end );
test( "XP boundary uncertainty and dead hero do not become guaranteed experience", function()
    local s = fixture(); s.targets[1].x, s.targets[1].position_error_per_s = 1499, 10;
    eq( X.AtDeath( s, s.targets[1], 1 ).status, "boundary_uncertain" );
    s.hero.alive = false; eq( X.AtDeath( s, s.targets[1], 1 ).xp, 0 );
end );
test( "passive XP forecast exists independently of our last hits", function()
    local s = fixture(); s.expected_creep_deaths = { { target_id = "c", at_s = 1, source = "visible_forecast" } };
    local a = P.Build( s, C ); eq( a.experience.in_range_xp, 60 ); eq( a.experience.level_timing, "possible_from_forecast" );
    eq( a.option_masks[21].available, true );
    s.targets[1].x = 1600; local b = P.Build( s, C ); eq( b.experience.requires_reposition, true );
    eq( b.option_masks[22].available, false ); assert( b.option_masks[22].reasons.xp_movement_executor_pending );
end );
test( "tower damage belongs to target and duplicated projectile is counted once", function()
    local s = fixture(); local a = shot( "a", 0.2, 100 ); s.tower_shots = { a, a, shot( "b", 0.4, 90 ) };
    local low, high, hits = T.DamageBefore( s, "c", 0.5 ); eq( low, 190 ); eq( high, 190 ); eq( hits, 2 );
    eq( T.DamageBefore( s, "self", 0.5 ), 0 );
end );
test( "last hit after tower shot is computed from HP and target effective damage", function()
    local s = fixture(); s.targets[1].hp = 155; s.tower_shots = { shot( "a", 0.2, 100 ) };
    local windows = T.LastHitWindows( s, s.targets[1], 55, 4 ); eq( #windows, 1 ); eq( windows[1].after_hits, 1 );
    eq( evaluate( s, { attack() } ).features.secured_creeps, 1 );
    s.targets[1].hp = 300; eq( #T.LastHitWindows( s, s.targets[1], 55, 4 ), 0 );
end );
test( "unreleased tower target prediction cannot be treated as a flying projectile", function()
    local s = fixture(); local a = shot( "a", 0.2, 100 ); a.released = false; s.tower_shots = { a };
    eq( T.DamageBefore( s, "c", 1 ), 0 );
end );
test( "tower overkill and simultaneous impact do not invent a last hit", function()
    local s = fixture(); s.targets[1].hp = 55; s.tower_shots = { shot( "a", 0.2, 40, 70 ) };
    eq( evaluate( s, { attack() } ).mask_reason, "tower_may_kill_before_action" );
    s.tower_shots = { shot( "a", 0.75, 40 ) }; eq( evaluate( s, { attack() } ).mask_reason, "tower_impact_order_unknown" );
end );
test( "observed HP trend cannot double count separate tower projectile damage", function()
    local s = fixture(); s.targets[1].hp_loss_per_s = 10; s.tower_shots = { shot( "a", 0.2, 10 ) };
    eq( evaluate( s, { attack() } ).mask_reason, "tower_damage_double_count_unknown" );
end );
test( "tower range and hero damage change pressure permission", function()
    local s = fixture(); s.towers = { { enemy = true, alive = true, visible = true, range_verified = true,
        x = 500, y = 0, attack_range = 700, target_id = "self", damage_by_target = { self = { min = 90, max = 100 } } } };
    local p = evaluate( s, { attack() } ); assert( p.available ); eq( p.tower.in_enemy_range, true );
    eq( p.tower.incoming_max, 100 ); eq( p.tower.pressure_safe_proven, false );
    s.hero.hp = 90; eq( evaluate( s, { attack() } ).mask_reason, "tower_pressure_unsafe_or_unknown" );
    s.hero.hp = 500; s.towers[1].range_verified = false;
    -- Unknown range remains explicit; cannot be declared safe by absence of in_range.
    eq( T.Pressure( s, { steps = { attack() } } ).status, "tower_range_unknown" );
    eq( evaluate( s, { attack() } ).mask_reason, "tower_pressure_unsafe_or_unknown" );
end );
test( "conditional tower hit count varies with creep HP and target-specific damage", function()
    local s = fixture(); local t = s.targets[1]; t.hp = 550;
    local tower = { seconds_per_attack = 1, first_impact_s = 0.2, damage_by_target = { c = { min = 100, max = 100 } } };
    local a = T.ConditionalSequence( t, 60, tower, 12 ); eq( a.windows[1].after_hits, 5 ); eq( a.confirmed_future_hits, false );
    t.hp, t.creep_type = 935, "siege"; tower.damage_by_target.c = { min = 200, max = 200 };
    local b = T.ConditionalSequence( t, 150, tower, 12 ); eq( b.windows[1].after_hits, 4 );
end );
test( "ranged creep preparation damage is an interval instead of a fixed extra hit", function()
    local s = fixture(); local t = s.targets[1]; t.hp, t.creep_type = 300, "ranged";
    local tower = { seconds_per_attack = 1, first_impact_s = 0.2, damage_by_target = { c = { min = 100, max = 100 } } };
    local a = T.ConditionalSequence( t, 60, tower, 5 ); eq( #a.windows, 0 );
    local found = false;
    for _, p in ipairs( a.preparation ) do if p.after_hits == 2 then eq( p.damage_min, 40 ); eq( p.damage_must_be_below, 100 ); found = true end end;
    assert( found );
end );
test( "waiting for tower impact is a real scheduler wait not an immediate observe", function()
    local s = fixture(); local p = evaluate( s, { { kind = "observe", duration_s = 0.5 }, attack() } );
    local scheduler = S.New(); assert( S.Begin( scheduler, 7, "joint", p, 100, C, s.capabilities ) );
    eq( S.Next( scheduler, { time = 100, snapshot_time = 100 }, C ).status, "waiting_window" );
    eq( S.Next( scheduler, { time = 100.49, snapshot_time = 100.49 }, C ).status, "waiting_window" );
    eq( S.Next( scheduler, { time = 100.5, snapshot_time = 100.5 }, C ).status, "submit" );
end );
test( "conditional tower counts are exposed to planner and serialized context", function()
    local s = fixture(); s.targets[1].hp = 550;
    s.towers = { { id = "allied_mid", visible = true, alive = true, enemy = false, x = 450, y = 0,
        range_verified = true, attack_range = 700, target_id = "c", seconds_per_attack = 1,
        first_impact_s = 0.2, damage_by_target = { c = { min = 100, max = 100 } } } };
    local out = P.Build( s, C ); eq( #out.tower_farm, 1 );
    eq( out.tower_farm[1].conditional_sequence.windows[1].after_hits, 5 );
    local record = Trace.Record( s, out, { status = "not_submitted" } );
    assert( Trace.Encode( record ):find( '"confirmed_future_hits":false', 1, true ) );
    eq( record.context.tower_farm[1].target_id, "c" );
end );
print( "CREEPS_XP_TOWER PASSED " .. count );
require = nativeRequire;
