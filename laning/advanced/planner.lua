local Mechanics = require( GetScriptDirectory() .. "/laning/advanced/mechanics" );
local Wave = require( GetScriptDirectory() .. "/laning/advanced/wave" );
local Catalog = require( GetScriptDirectory() .. "/laning/advanced/catalog" );
local Threat = require( GetScriptDirectory() .. "/laning/advanced/threat" );
local Creeps = require( GetScriptDirectory() .. "/laning/advanced/creeps" );
local XP = require( GetScriptDirectory() .. "/laning/advanced/experience" );
local Tower = require( GetScriptDirectory() .. "/laning/advanced/tower" );
local M = {};
local function copy( t ) local out = {}; for k, v in pairs( t ) do out[k] = v end; return out end;
local function kind( t ) return t.kind or "enemy_creep" end;
local function knownTarget( t )
    return t.visible and t.alive and not t.invulnerable and not t.unknown_position
        and Mechanics.Number( t.x ) and Mechanics.Number( t.y ) and Mechanics.Number( t.hp ) and t.hp > 0;
end
local function invalid( p, reason ) p.available, p.mask_reason = false, reason; return p end;
local function hasRaze( p ) for _, step in ipairs( p.steps ) do if step.kind == "raze" then return true end end; return false end;

function M.Evaluate( s, candidate, cfg )
    local p = copy( candidate ); p.available = true; p.schema = cfg.schema;
    p.policy_version = cfg.policy_version; p.features = {}; p.events = {};
    local hero, targets = s.hero, {};
    if not hero or not Mechanics.Number( hero.mana ) or not Mechanics.Number( hero.max_mana )
        or hero.mana < 0 or hero.max_mana <= 0 or hero.mana > hero.max_mana
        or not Mechanics.Number( hero.x ) or not Mechanics.Number( hero.y ) then return invalid( p, "hero_snapshot_incomplete" ) end;
    if hero.mana_regen ~= nil and ( not Mechanics.Number( hero.mana_regen ) or hero.mana_regen < 0 ) then return invalid( p, "mana_regen_invalid" ) end;
    for _, target in ipairs( s.targets or {} ) do targets[target.id] = target end;
    if #p.steps > cfg.max_steps then return invalid( p, "step_budget" ) end;
    if hasRaze( p ) and not ( s.capabilities or {} ).joint_executor then return invalid( p, "joint_executor_not_integrated" ) end;
    local castCount = 0; for _, step in ipairs( p.steps ) do if step.kind == "raze" then castCount = castCount + 1 end end;
    if castCount > 1 and not ( s.capabilities or {} ).cross_raze_timing_verified then return invalid( p, "cross_raze_timing_probe_required" ) end;
    local f = { secured_creeps = 0, ranged_secured = 0, denies = 0,
        hero_damage = 0, projected_hero_kills = 0, wave_damage = 0, mana_spent = 0, duration_s = 0, estimated_risk = 0,
        gold_min = 0, gold_max = 0, gold_unknown_kills = 0, secured_by_type = {}, projected_death_xp = 0, xp_unknown_kills = 0 };
    local timeline, ownReady, attackReady, manaSpent = {}, 0, hero.attack_ready_in_s or 0, 0;
    local manaAt, manaNow = 0, hero.mana;
    local function manaThrough( at )
        manaNow = math.min( hero.max_mana, manaNow + ( hero.mana_regen or 0 ) * ( at - manaAt ) );
        manaAt = at; return manaNow;
    end
    local spellReady = {};
    for index, step in ipairs( p.steps ) do
        local t = step.target_id and targets[step.target_id] or nil;
        if step.target_id and ( not t or not knownTarget( t ) ) then return invalid( p, "target_not_observed" ) end;
        if step.kind == "attack" then
            if hero.disabled or hero.disarmed then return invalid( p, "cannot_attack" ) end;
            if not Mechanics.Number( hero.attack_range ) or not Mechanics.Number( hero.attack_point_s )
                or not Mechanics.Number( hero.attack_cycle_s ) or not Mechanics.Number( hero.projectile_speed ) then return invalid( p, "attack_timing_unknown" ) end;
            if t.attack_immune or Mechanics.Distance( hero, t ) > hero.attack_range then return invalid( p, "attack_out_of_range_or_immune" ) end;
            if not Mechanics.AttackDamage( hero, t ) then return invalid( p, "attack_damage_unknown" ) end;
            if kind( t ) == "allied_creep" and ( not t.max_hp or t.hp / t.max_hp > 0.5 ) then return invalid( p, "deny_not_allowed" ) end;
            local release = math.max( ownReady, attackReady ) + ( t.turn_s or 0 ) + hero.attack_point_s;
            local travel = hero.projectile_speed > 0 and Mechanics.Distance( hero, t ) / hero.projectile_speed or 0;
            timeline[#timeline + 1] = { at = release + travel, kind = "attack", target_id = t.id, step = index, release_at = release };
            -- Снаряд может лететь, пока начинается cast. В игре нужен факт release, не таймер.
            ownReady, attackReady = release, release + hero.attack_cycle_s;
        elseif step.kind == "raze" then
            local spell = s.razes and s.razes[step.ability_id];
            if not spell or not spell.learned or spell.silenced or hero.silenced or hero.disabled then return invalid( p, "raze_unavailable" ) end;
            if not spell.no_target_verified or not spell.geometry_verified then return invalid( p, "ability_profile_unverified" ) end;
            if not Mechanics.Number( spell.range ) or not Mechanics.Number( spell.radius ) or not Mechanics.Number( spell.mana_cost )
                or not Mechanics.Number( spell.cast_point_s ) or not Mechanics.Number( spell.ready_in_s ) then return invalid( p, "ability_profile_missing" ) end;
            local start = math.max( ownReady, spellReady[step.ability_id] or spell.ready_in_s ) + ( t.turn_s or 0 );
            if spell.mana_cost < 0 or spell.cast_point_s < 0 or spell.ready_in_s < 0 then return invalid( p, "ability_profile_invalid" ) end;
            if manaThrough( start ) < spell.mana_cost then return invalid( p, "insufficient_mana" ) end;
            manaNow, manaSpent = manaNow - spell.mana_cost, manaSpent + spell.mana_cost;
            local hit = start + spell.cast_point_s;
            local aim = Mechanics.Predict( t, hit );
            local impact = Mechanics.Impact( hero, aim, spell );
            if not impact or Mechanics.Distance( aim, impact ) > spell.radius then return invalid( p, "raze_geometry_miss" ) end;
            timeline[#timeline + 1] = { at = hit, kind = "raze", step = index, ability_id = step.ability_id, impact = impact, profile = spell };
            ownReady = hit + ( spell.backswing_s or 0 );
            spellReady[step.ability_id] = hit + ( spell.cooldown_s or math.huge );
        elseif step.kind == "observe" then
            ownReady = ownReady + ( step.duration_s or 0 );
        else return invalid( p, "unsupported_primitive" ) end;
        if ownReady > cfg.max_plan_horizon_s then return invalid( p, "horizon_exceeded" ) end;
    end
    table.sort( timeline, function( a, b ) if a.at == b.at then return a.step < b.step end; return a.at < b.at end );
    local projected = {};
    for id, t in pairs( targets ) do projected[id] = { damage = 0, stacks = Mechanics.StacksAt( t, s.time ),
        expires = t.stack_expires_at, killed = false } end;
    local souls, deadFlags = hero.souls, {};
    for _, event in ipairs( timeline ) do
        if event.at > cfg.max_plan_horizon_s then return invalid( p, "impact_after_horizon" ) end;
        local gainedSouls, killedFlags = 0, {};
        local soulsAtImpact = Mechanics.SoulsAt( hero, souls, event.at );
        if hero.damage_projection_valid_until_s and event.at > hero.damage_projection_valid_until_s then
            return invalid( p, "damage_effect_window_expired" );
        end
        for id, t in pairs( targets ) do
            local state = projected[id];
            local hit = event.kind == "attack" and event.target_id == id;
            if event.kind == "raze" and knownTarget( t ) and kind( t ) ~= "allied_creep" and not t.magic_immune then
                local uncertainty = ( t.position_error_per_s or 0 ) * event.at;
                hit = Mechanics.Distance( Mechanics.Predict( t, event.at ), event.impact ) + uncertainty <= event.profile.radius;
            end
            if hit and not state.killed then
                local hpUpper, hpError, damageTarget = Creeps.HPUpperAt( t, event.at, deadFlags );
                if not hpUpper then return invalid( p, hpError ) end;
                local towerLow, towerHigh, towerHits, collision = Tower.DamageBefore( s, t.id, event.at );
                if collision then return invalid( p, "tower_impact_order_unknown" ) end;
                if towerHits > 0 and ( t.hp_loss_per_s or 0 ) > 0 and not t.hp_loss_excludes_tower then
                    return invalid( p, "tower_damage_double_count_unknown" );
                end
                local hpBefore = hpUpper - state.damage - towerLow;
                if hpBefore > 0 and towerHits > 0 and hpUpper - 2 * ( t.hp_prediction_error_per_s or 0 ) * event.at - state.damage - towerHigh <= 0 then
                    return invalid( p, "tower_may_kill_before_action" );
                end
                if hpBefore > 0 then
                    local damage;
                    if event.kind == "attack" then damage = Mechanics.AttackDamage( hero, damageTarget, soulsAtImpact );
                        if not damage then return invalid( p, "projected_attack_damage_unknown" ) end;
                    else
                        if state.expires and s.time + event.at >= state.expires then state.stacks = 0 end;
                        local raw, err = Mechanics.RazeRaw( event.profile, soulsAtImpact, state.stacks, hero.spell_amp );
                        if not raw then return invalid( p, err ) end;
                        damage = Mechanics.MagicDamage( raw, damageTarget );
                        if not damage then return invalid( p, "magic_damage_query_unknown" ) end;
                        state.stacks = state.stacks + 1; state.expires = s.time + event.at + event.profile.stack_duration_s;
                    end
                    if kind( t ) == "enemy_hero" then f.hero_damage = f.hero_damage + math.min( hpBefore, damage ) end;
                    if kind( t ) == "enemy_creep" then f.wave_damage = f.wave_damage + math.min( hpBefore, damage ) end;
                    state.damage = state.damage + damage;
                    if damage >= hpBefore then
                        state.killed = true;
                        if kind( t ) == "allied_creep" then f.denies = f.denies + 1;
                        elseif kind( t ) == "enemy_creep" then
                            f.secured_creeps = f.secured_creeps + 1;
                            local subtype = Creeps.Type( t );
                            f.secured_by_type[subtype] = ( f.secured_by_type[subtype] or 0 ) + 1;
                            if subtype == "ranged" then f.ranged_secured = f.ranged_secured + 1 end;
                            local low, high = Creeps.Bounty( t );
                            if low then f.gold_min, f.gold_max = f.gold_min + low, f.gold_max + high;
                            else f.gold_unknown_kills = f.gold_unknown_kills + 1 end;
                            local xp = XP.AtDeath( s, t, event.at );
                            if xp.xp ~= nil then f.projected_death_xp = f.projected_death_xp + xp.xp;
                            else f.xp_unknown_kills = f.xp_unknown_kills + 1 end;
                            if subtype == "flagbearer" then killedFlags[t.id] = { at = event.at, kind = t.kind } end;
                            gainedSouls = gainedSouls + ( hero.souls_per_creep or 0 );
                        elseif kind( t ) == "enemy_hero" then f.projected_hero_kills = f.projected_hero_kills + 1;
                        end
                    end
                end
            end
        end
        if souls and hero.max_souls then souls = math.min( hero.max_souls, souls + gainedSouls ) end;
        -- Всё одно AoE использует состояние ДО события; смерть ауры влияет на следующие попадания.
        for id, death in pairs( killedFlags ) do deadFlags[id] = death end;
        -- Без актуального max_souls прирост не выдумывается. Изменение -- projected, не факт.
        f.duration_s = math.max( f.duration_s, event.at );
        p.events[#p.events + 1] = event;
    end
    f.mana_spent = manaSpent;
    p.threat = Threat.Estimate( s, f.duration_s, cfg );
    f.estimated_risk = p.threat.damage_budget;
    p.tower = Tower.Pressure( s, p );
    if p.tower.unsafe then return invalid( p, "tower_pressure_unsafe_or_unknown" ) end;
    f.estimated_risk = f.estimated_risk + p.tower.incoming_max;
    p.experience = XP.Context( s, cfg.max_plan_horizon_s );
    local wave = Wave.Context( s, cfg ); p.wave = wave; p.features = f;
    local w = cfg.weights;
    p.baseline_utility = f.secured_creeps * w.creep + f.ranged_secured * w.ranged_creep_bonus
        + f.denies * w.deny + f.projected_hero_kills * w.hero_kill + f.hero_damage * w.hero_damage + f.mana_spent * w.mana
        + f.estimated_risk * w.risk + f.duration_s * w.duration
        + f.gold_min * ( w.gold_min or 0 )
        + f.wave_damage * ( wave.push_allowed and w.wave_damage_push or w.wave_damage_hold );
    p.mana_after_estimate = manaThrough( ownReady );
    p.reserve_violated = p.mana_after_estimate < hero.max_mana * cfg.reserve_mana_fraction;
    if p.reserve_violated then p.baseline_utility = p.baseline_utility - 5 end;
    p.predictions_are_outcomes = false;
    return p;
end

function M.Build( s, cfg )
    local candidates = {};
    local function add( id, steps, reason, precondition )
        local key = Catalog[id + 1].key;
        local p = { option_id = id, option_key = key, steps = steps, reason = reason };
        if precondition then p.available, p.mask_reason = false, precondition;
        else p = M.Evaluate( s, p, cfg ) end;
        local parts = { tostring( id ) };
        for _, step in ipairs( steps ) do
            parts[#parts + 1] = step.kind .. ":" .. tostring( step.ability_id or "" ) .. ":" .. tostring( step.target_id or "" )
                .. ( step.kind == "observe" and ":" .. tostring( step.duration_s or 0 ) or "" );
        end;
        p.candidate_key = table.concat( parts, "|" );
        candidates[#candidates + 1] = p;
    end
    add( 0, { { kind = "observe", duration_s = 0.15 } }, "equilibrium_is_an_option" );
    add( 13, { { kind = "observe", duration_s = 0.15 } }, "reserve_resources" );
    local enemyCreeps, heroes, allies, towerFarm = {}, {}, {}, {};
    local ordered = {}; for _, t in ipairs( s.targets or {} ) do if knownTarget( t ) then ordered[#ordered + 1] = t end end;
    table.sort( ordered, function( a, b )
        local pa = kind( a ) == "enemy_hero" and 1 or ( Creeps.Type( a ) == "ranged" and 2 or 3 );
        local pb = kind( b ) == "enemy_hero" and 1 or ( Creeps.Type( b ) == "ranged" and 2 or 3 );
        if pa ~= pb then return pa < pb end;
        if a.hp ~= b.hp then return a.hp < b.hp end;
        return tostring( a.id ) < tostring( b.id );
    end );
    for _, t in ipairs( ordered ) do
        if #enemyCreeps + #heroes + #allies >= cfg.max_target_candidates then break end;
        if knownTarget( t ) then
            if kind( t ) == "enemy_creep" then enemyCreeps[#enemyCreeps + 1] = t;
            elseif kind( t ) == "enemy_hero" then heroes[#heroes + 1] = t;
            elseif kind( t ) == "allied_creep" then allies[#allies + 1] = t end;
        end
    end
    local wave = Wave.Context( s, cfg );
    for _, t in ipairs( enemyCreeps ) do
        local projectedWindows = Tower.LastHitWindows( s, t, Mechanics.AttackDamage( s.hero, t ), cfg.max_plan_horizon_s );
        for _, tower in ipairs( s.towers or {} ) do
            if tower.visible and tower.alive and not tower.enemy and tower.range_verified and Mechanics.Number( tower.attack_range )
                and Mechanics.Distance( tower, t ) <= tower.attack_range then
                towerFarm[#towerFarm + 1] = { tower_id = tower.id, target_id = t.id, creep_type = Creeps.Type( t ),
                    current_tower_target_id = tower.target_id, projectile_windows = projectedWindows,
                    conditional_sequence = Tower.ConditionalSequence( t, Mechanics.AttackDamage( s.hero, t ), tower, 12 ) };
            end
        end
        add( 1, { { kind = "attack", target_id = t.id } }, "secure_creep" );
        if Mechanics.Number( s.hero.attack_point_s ) and Mechanics.Number( s.hero.projectile_speed ) then
            local travel = s.hero.projectile_speed > 0 and Mechanics.Distance( s.hero, t ) / s.hero.projectile_speed or 0;
            local delay = ( s.hero.attack_ready_in_s or 0 ) + ( t.turn_s or 0 ) + s.hero.attack_point_s + travel;
            for _, window in ipairs( projectedWindows ) do
                local wait = math.max( 0, window.at_s - delay + 0.01 );
                if wait + delay < window.until_s then
                    add( 23, { { kind = "observe", duration_s = wait }, { kind = "attack", target_id = t.id } }, "observed_tower_projectile_window" );
                end
            end
        end
        if wave.push_allowed then add( 10, { { kind = "attack", target_id = t.id } }, wave.reason ) end;
        for ability in pairs( s.razes or {} ) do
            local raze = { kind = "raze", ability_id = ability, target_id = t.id };
            local attack = { kind = "attack", target_id = t.id };
            add( 2, { raze }, "secure_or_contest_creep" );
            add( 3, { attack, raze }, "attack_release_then_cast" );
            add( 4, { raze, attack }, "cast_then_finish_creep" );
            if wave.push_allowed then add( 11, { raze, attack }, wave.reason ) end;
            for _, h in ipairs( heroes ) do
                add( 6, { raze, { kind = "attack", target_id = h.id } }, "secure_creep_then_trade" );
                add( 7, { { kind = "attack", target_id = h.id }, raze }, "projectile_trade_and_creep_secure" );
            end
        end
    end
    for _, t in ipairs( allies ) do add( 9, { { kind = "attack", target_id = t.id } }, "deny_opportunity" ) end;
    for _, h in ipairs( heroes ) do
        add( 17, { { kind = "attack", target_id = h.id } }, "ordinary_attack_trade" );
        for ability in pairs( s.razes or {} ) do
            add( 5, { { kind = "raze", ability_id = ability, target_id = h.id } }, "hero_and_creep_aoe" );
            for other in pairs( s.razes or {} ) do if other ~= ability then
                add( 8, { { kind = "raze", ability_id = ability, target_id = h.id },
                    { kind = "raze", ability_id = other, target_id = h.id } }, "same_target_stack_window" );
                for third in pairs( s.razes or {} ) do if third ~= ability and third ~= other then
                    add( 8, { { kind = "raze", ability_id = ability, target_id = h.id },
                        { kind = "raze", ability_id = other, target_id = h.id },
                        { kind = "raze", ability_id = third, target_id = h.id } }, "triple_raze_window" );
                end end
            end end
        end
    end
    -- Стабильные IDs будущих исполнителей, маски явны. Не выдаём их за реализованные приказы.
    add( 12, {}, "rune_access", not wave.rune_move_allowed and "rune_or_path_not_observed" or "rune_executor_pending" );
    add( 15, {}, "vision_highground", "ward_executor_pending" );
    add( 16, {}, "deward_after_observation", "deward_executor_pending" );
    add( 18, {}, "release_then_reposition", "movement_executor_pending" );
    add( 19, {}, "set_up_future_raze", "movement_and_geometry_probe_pending" );
    add( 20, {}, "deny_and_secure_window", "second_attack_opportunity_predictor_pending" );
    local experience = XP.Context( s, cfg.max_plan_horizon_s );
    add( 21, { { kind = "observe", duration_s = 0.15 } }, "preserve_observed_xp_window",
        experience.in_range_xp <= 0 and "no_known_xp_window" or nil );
    add( 22, {}, "recover_xp_access", experience.requires_reposition and "xp_movement_executor_pending" or "no_known_xp_loss" );
    add( 24, {}, "prepare_under_tower", "tower_target_lock_and_second_attack_predictor_pending" );
    if s.danger then
        for _, p in ipairs( candidates ) do p.available, p.mask_reason = false, "emergency_abort" end;
        candidates[#candidates + 1] = { option_id = 14, option_key = Catalog[15].key,
            available = true, steps = {}, baseline_utility = 0, reason = "emergency_abort", schema = cfg.schema };
    end
    table.sort( candidates, function( a, b )
        if a.available ~= b.available then return a.available end;
        if ( a.baseline_utility or -math.huge ) ~= ( b.baseline_utility or -math.huge ) then
            return ( a.baseline_utility or -math.huge ) > ( b.baseline_utility or -math.huge );
        end
        if a.option_id ~= b.option_id then return a.option_id < b.option_id end;
        return ( a.candidate_key or a.reason ) < ( b.candidate_key or b.reason );
    end );
    local masks = {};
    table.sort( towerFarm, function( a, b )
        if tostring( a.tower_id ) ~= tostring( b.tower_id ) then return tostring( a.tower_id ) < tostring( b.tower_id ) end;
        return tostring( a.target_id ) < tostring( b.target_id );
    end );
    for _, entry in ipairs( Catalog ) do masks[entry.id] = { available = false, reasons = {} } end;
    for _, p in ipairs( candidates ) do
        local mask = masks[p.option_id];
        if p.available then mask.available = true;
        else mask.reasons[p.mask_reason] = true end;
    end
    for _, mask in pairs( masks ) do
        if not mask.available and not next( mask.reasons ) then mask.reasons.no_parameterization_in_snapshot = true end;
    end
    return { schema = cfg.schema, policy_version = cfg.policy_version, snapshot_time = s.time,
        candidates = candidates, selected = candidates[1], wave = wave,
        option_catalog = Catalog, option_masks = masks, experience = experience, tower_farm = towerFarm,
        learning_reward = nil, simulator_only_until_executor_integrated = true };
end
return M;
