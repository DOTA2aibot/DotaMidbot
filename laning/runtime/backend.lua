local A = require( GetScriptDirectory() .. "/laning/runtime/api" );
local Guard = require( GetScriptDirectory() .. "/laning/runtime/guard" );
local Observer = require( GetScriptDirectory() .. "/laning/runtime/observe" );
local D = require( GetScriptDirectory() .. "/laning/advanced/mechanics" );
local Trace = require( GetScriptDirectory() .. "/laning/advanced/trace" );
local PlannerConfig = require( GetScriptDirectory() .. "/laning/advanced/config" );
local M = {};
local function find( s, id ) for _, t in ipairs( s.targets ) do if t.id == id then return t end end end;
local function projectiles( bot, target )
    local out = { count = 0, handles = {}, near = false };
    local list, origin = A.Call( target, "GetIncomingTrackingProjectiles" ), A.Position( bot );
    for _, p in ipairs( type( list ) == "table" and list or {} ) do
        if p.caster == bot and p.is_attack == true then
            out.count = out.count + 1;
            if p.handle ~= nil then out.handles[tostring( p.handle )] = true end;
            if p.location and origin and A.Number( p.location.x ) and A.Number( p.location.y )
                and A.Distance( origin, p.location ) <= 180 then out.near = true end;
        end
    end
    return out;
end
function M.New( cfg )
    local b = { schema = PlannerConfig.schema, joint_executor_verified = false, cfg = cfg,
        context = Observer.New( cfg ), probe_orders = 0, next_log = -math.huge, next_face = -math.huge };
    function b.Snapshot( bot )
        local now = A.Time();
        Guard.LanePulse( bot, now );
        b.snapshot, b.snapshot_error = Observer.Collect( b.context, bot );
        if b.snapshot then
            b.snapshot.capabilities.joint_executor = Guard.ChannelReady( bot, now );
            b.snapshot.integration = { operation = cfg.operation, stage = cfg.stage,
                channel_ready = b.snapshot.capabilities.joint_executor, probe_orders = b.probe_orders };
        end
        return b.snapshot;
    end
    function b.Release( bot, reason )
        local now = A.Time();
        -- Отменять только собственный ещё ожидающий приказ, пока lease действительно наш.
        if ( b.pending or b.cancelled_order ) and now and Guard.Owns( bot, b.token, now ) and reason ~= "plan_finished"
            and ( BOT_MODE_LANING ~= nil and A.Call( bot, "GetActiveMode" ) == BOT_MODE_LANING ) then
            pcall( function() bot:Action_ClearActions( true ) end );
        end
        Guard.Release( bot, b.token ); b.token, b.pending, b.requested, b.cancelled_order, b.takeover = nil, nil, nil, nil, nil;
    end
    function b.Acquire( bot, plan )
        if b.requested and b.requested ~= plan.candidate_key then b.Release( bot, "plan_replaced_before_ack" ) end;
        if not b.requested then
            local target = A.Call( bot, "GetAttackTarget" );
            b.takeover = { record = A.Call( bot, "GetLastAttackTime" ), target = target,
                projectiles = target and projectiles( bot, target ) or nil };
            b.released_attack_record = nil;
        end
        b.requested = plan.candidate_key;
        local ok, value = Guard.Acquire( bot, plan.candidate_key, A.Time() );
        if ok then b.token = value end;
        return ok, value;
    end
    function b.Filter( bot, s, planning )
        local probing = cfg.operation == "probe_attack" or cfg.operation == "probe_raze";
        for _, p in ipairs( planning.candidates ) do
            local attacks, casts = 0, 0;
            for _, step in ipairs( p.steps ) do if step.kind == "attack" then attacks = attacks + 1 elseif step.kind == "raze" then casts = casts + 1 end end;
            if probing or ( attacks == 0 and casts == 0 ) or ( cfg.stage == "attacks" and casts > 0 ) or ( cfg.stage == "raze" and ( attacks > 0 or casts > 1 ) ) then
                p.available, p.mask_reason = false, "runtime_stage_mask";
            end
            if cfg.option_allowlist and not cfg.option_allowlist[p.option_id] then p.available, p.mask_reason = false, "runtime_option_allowlist" end;
            if s.hero.casting then p.available, p.mask_reason = false, "current_action_busy" end;
        end
        if probing and not s.danger and not s.hero.casting and b.probe_orders < cfg.max_probe_orders then
            for _, t in ipairs( s.targets ) do
                if t.kind == "enemy_creep" and not t.invulnerable and not t.attack_immune then
                    local step;
                    if cfg.operation == "probe_attack" and not s.hero.disarmed and A.Number( s.hero.attack_range ) and D.Distance( s.hero, t ) <= s.hero.attack_range then
                        step = { kind = "attack", target_id = t.id };
                    elseif cfg.operation == "probe_raze" and not s.hero.silenced and not t.magic_immune then
                        for _, name in ipairs( { "nevermore_shadowraze1", "nevermore_shadowraze2", "nevermore_shadowraze3" } ) do
                            local r = s.razes[name];
                            if r and r.learned and r.no_target_verified and r.ready_in_s == 0 and r.mana_cost <= s.hero.mana then
                                local aim = D.Predict( t, r.cast_point_s ); local impact = D.Impact( s.hero, aim, r );
                                if impact and D.Distance( impact, aim ) + ( t.position_error_per_s or 0 ) * r.cast_point_s <= r.radius then
                                    step = { kind = "raze", target_id = t.id, ability_id = name }; break;
                                end;
                            end
                        end
                    end
                    if step then
                        planning.candidates[#planning.candidates + 1] = { option_id = step.kind == "attack" and 1 or 2,
                            option_key = "integration_probe", candidate_key = "probe:" .. step.kind .. ":" .. t.id,
                            steps = { step }, available = true, baseline_utility = math.huge,
                            reason = "one_order_integration_probe_not_policy_decision", diagnostic_probe = true };
                        break;
                    end
                end
            end
        end
        if cfg.operation == "execute" and cfg.lane_positioning and ( not cfg.option_allowlist or cfg.option_allowlist[0] ) and s.lane_anchor and not s.danger
            and not s.hero.casting and D.Distance( s.hero, s.lane_anchor ) > cfg.anchor_tolerance then
            local distance = D.Distance( s.hero, s.lane_anchor ); local stepLength = math.min( cfg.move_step, distance );
            local point = { x = s.hero.x + ( s.lane_anchor.x - s.hero.x ) / distance * stepLength,
                y = s.hero.y + ( s.lane_anchor.y - s.hero.y ) / distance * stepLength };
            planning.candidates[#planning.candidates + 1] = { option_id = 0, option_key = "hold_equilibrium",
                candidate_key = "0|move:mid_front",
                steps = { { kind = "move", location = point } }, available = true, baseline_utility = -0.1,
                reason = "bounded_move_toward_own_mid_front", runtime_parameterization = true };
        end
        table.sort( planning.candidates, function( a, z )
            if a.available ~= z.available then return a.available end;
            if ( a.baseline_utility or -math.huge ) ~= ( z.baseline_utility or -math.huge ) then return ( a.baseline_utility or -math.huge ) > ( z.baseline_utility or -math.huge ) end;
            return tostring( a.candidate_key or a.option_key ) < tostring( z.candidate_key or z.option_key );
        end );
        planning.selected = planning.candidates[1];
        for _, mask in pairs( planning.option_masks ) do mask.available = false end;
        for _, p in ipairs( planning.candidates ) do
            local mask = planning.option_masks[p.option_id];
            if p.available then mask.available = true else mask.reasons[p.mask_reason or "runtime_mask"] = true end;
        end
        return planning;
    end
    function b.Validate( bot, step )
        local s = b.Snapshot( bot ); local now = A.Time();
        local o = { time = now or 0, snapshot_time = s and s.time or -math.huge, valid_targets = {}, ability_ready = {},
            emergency = not s or s.danger or not Guard.Owns( bot, b.token, now ), casting = s and s.hero.casting or false };
        if not s or not step then return o end;
        local t = find( s, step.target_id );
        if step.kind == "attack" then
            o.valid_targets[step.target_id] = t ~= nil and not t.invulnerable and not t.attack_immune
                and not s.hero.disarmed
                and A.Number( s.hero.attack_range ) and D.Distance( s.hero, t ) <= s.hero.attack_range
                and ( t.kind ~= "allied_creep" or t.hp / t.max_hp <= 0.5 );
        elseif step.kind == "raze" then
            local r, ability = s.razes[step.ability_id], b.context.abilities[step.ability_id];
            o.valid_targets[step.target_id] = t ~= nil and not t.invulnerable and not t.magic_immune;
            o.ability_ready[step.ability_id] = r ~= nil and r.no_target_verified and r.learned and not s.hero.silenced
                and A.Call( ability, "IsFullyCastable" ) == true;
            if t and r then
                local aim = D.Predict( t, r.cast_point_s ); local v = A.Vector( aim );
                o.facing_ready = v ~= nil and A.Call( bot, "IsFacingLocation", v, cfg.facing_tolerance_deg ) == true;
                local impact = D.Impact( s.hero, aim, r );
                o.geometry_valid = impact ~= nil and D.Distance( aim, impact ) + ( t.position_error_per_s or 0 ) * r.cast_point_s <= r.radius;
            end
        elseif step.kind == "move" then
            local v = step.location and A.Vector( step.location );
            o.movement_valid = v ~= nil and type( IsLocationPassable ) == "function" and IsLocationPassable( v ) == true
                and D.Distance( s.hero, step.location ) <= cfg.move_step + 1;
            for _, tower in ipairs( s.towers ) do
                if tower.enemy and ( not tower.range_verified or D.Distance( tower, step.location ) <= tower.attack_range + tower.range_margin ) then o.movement_valid = false end;
            end
        end
        local current = A.Call( bot, "GetCurrentActionType" );
        local last = A.Call( bot, "GetLastAttackTime" );
        local currentTarget = A.Call( bot, "GetAttackTarget" );
        local possibleAttack = current == BOT_ACTION_TYPE_ATTACK
            or ( BOT_ACTION_TYPE_ATTACKMOVE ~= nil and current == BOT_ACTION_TYPE_ATTACKMOVE );
        -- Унаследованная непрерывная атака может не перейти в idle. Ждём её следующий
        -- наблюдаемый release, затем заменяем приказ; старый timestamp сам по себе не разрешает отменять замах.
        if b.takeover and not b.pending and currentTarget == b.takeover.target and A.Number( last )
            and A.Number( b.takeover.record ) and last > b.takeover.record then
            local after = currentTarget and projectiles( bot, currentTarget ); local fresh = false;
            if after and b.takeover.projectiles then
                for id in pairs( after.handles ) do if not b.takeover.projectiles.handles[id] then fresh = true end end;
                fresh = fresh or ( after.near and after.count > b.takeover.projectiles.count );
            end
            if fresh or cfg.probes.last_attack_time_release_verified then b.released_attack_record = last end;
        end
        o.attack_windup = not A.Number( current ) or BOT_ACTION_TYPE_ATTACK == nil or ( possibleAttack
            and ( not A.Number( last ) or last ~= b.released_attack_record ) );
        return o;
    end
    function b.Prepare( bot, step )
        if cfg.operation == "observe" then return false, "observe_mode_has_no_orders" end;
        local o = b.Validate( bot, step ); if o.emergency or o.casting or o.attack_windup then return false, "cannot_turn_now" end;
        if not o.valid_targets[step.target_id] or not o.geometry_valid then return false, "face_target_invalid" end;
        local now = A.Time(); if now < b.next_face then return true end;
        local s, t = b.snapshot, find( b.snapshot, step.target_id );
        local aim = D.Predict( t, s.razes[step.ability_id].cast_point_s );
        local distance = D.Distance( s.hero, aim ); if distance == 0 then return false, "face_direction_undefined" end;
        local dest = { x = s.hero.x + ( aim.x - s.hero.x ) / distance * cfg.face_distance,
            y = s.hero.y + ( aim.y - s.hero.y ) / distance * cfg.face_distance };
        for _, tower in ipairs( s.towers ) do
            if tower.enemy and ( not tower.range_verified or D.Distance( tower, dest ) <= tower.attack_range + tower.range_margin ) then return false, "face_move_enters_tower_range" end;
        end
        local vector = A.Vector( dest );
        if not vector or type( IsLocationPassable ) ~= "function" or IsLocationPassable( vector ) ~= true then return false, "face_location_unverified" end;
        local ok = pcall( function() bot:Action_MoveDirectly( vector ) end );
        if ok then b.next_face = now + 0.1 end;
        return ok, "face_order_submitted_not_completed";
    end
    function b.Submit( bot, order )
        if cfg.operation ~= "execute" and cfg.operation ~= "probe_attack" and cfg.operation ~= "probe_raze" then return false, "operation_has_no_orders" end;
        if ( cfg.operation == "probe_attack" and order.step.kind ~= "attack" ) or ( cfg.operation == "probe_raze" and order.step.kind ~= "raze" )
            or ( cfg.operation == "execute" and cfg.stage == "attacks" and order.step.kind == "raze" )
            or ( cfg.operation == "execute" and cfg.stage == "raze" and order.step.kind == "attack" ) then return false, "stage_changed" end;
        local o = b.Validate( bot, order.step ); local s = b.snapshot; local step = order.step;
        if o.emergency or o.casting or o.attack_windup then return false, "fresh_safety_rejected" end;
        if step.kind ~= "move" and not o.valid_targets[step.target_id] then return false, "fresh_target_rejected" end;
        local unit = b.context.handles[step.target_id];
        if step.kind ~= "move" and not A.Visible( unit ) then return false, "target_changed_before_api" end;
        local pending = { actor = A.Call( bot, "GetPlayerID" ), plan_id = order.plan_id, step_id = order.step_id,
            kind = step.kind, at = s.time, target = unit };
        local ok;
        if step.kind == "attack" then
            pending.attack_before = A.Call( bot, "GetLastAttackTime" ); pending.projectiles_before = projectiles( bot, unit );
            ok = pcall( function() bot:Action_AttackUnit( unit, true ) end );
        elseif step.kind == "raze" then
            if not o.ability_ready[step.ability_id] or not o.facing_ready or not o.geometry_valid then return false, "fresh_cast_rejected" end;
            pending.ability = b.context.abilities[step.ability_id];
            pending.cooldown_before = A.Call( pending.ability, "GetCooldownTimeRemaining" );
            pending.mana_before = s.hero.mana; pending.mana_cost = s.razes[step.ability_id].mana_cost;
            ok = pcall( function() bot:Action_UseAbility( pending.ability ) end );
        elseif step.kind == "move" and o.movement_valid then
            pending.location = step.location;
            ok = pcall( function() bot:Action_MoveToLocation( A.Vector( step.location ) ) end );
        else return false, "unsupported_order" end;
        if not ok then return false, "action_api_error" end;
        b.pending, b.takeover = pending, nil;
        if cfg.operation == "probe_attack" or cfg.operation == "probe_raze" then b.probe_orders = b.probe_orders + 1 end;
        return true; -- факт вызова API, не release/hit/kill
    end
    function b.Events( bot )
        local p, now = b.pending, A.Time(); if not p or not now then return {} end;
        local event = { actor = p.actor, plan_id = p.plan_id, step_id = p.step_id, observed_at = now };
        if not Guard.Owns( bot, b.token, now ) or not b.snapshot or b.snapshot.danger or ( p.kind == "attack" and not A.Visible( p.target ) ) then
            event.status, event.evidence = "cancelled", "lease_safety_or_target_lost";
        elseif now - p.at > cfg.command_timeout_s then event.status, event.evidence = "rejected", "release_not_confirmed";
        elseif p.kind == "attack" then
            local after = projectiles( bot, p.target ); local last = A.Call( bot, "GetLastAttackTime" );
            local newHandle = false; for id in pairs( after.handles ) do if not p.projectiles_before.handles[id] then newHandle = true end end;
            if A.Number( last ) and A.Number( p.attack_before ) and last > p.attack_before
                and ( newHandle or ( after.near and after.count > p.projectiles_before.count ) ) then
                event.status, event.evidence = "attack_released", "new_own_projectile_and_attack_record";
                b.released_attack_record = last;
            elseif cfg.probes.last_attack_time_release_verified and A.Number( last ) and A.Number( p.attack_before ) and last > p.attack_before then
                event.status, event.evidence = "attack_released", "build_calibrated_last_attack_record";
                b.released_attack_record = last;
            end
        elseif p.kind == "raze" then
            local cd = A.Call( p.ability, "GetCooldownTimeRemaining" );
            local mana = A.Call( bot, "GetMana" );
            if A.Number( cd ) and A.Number( p.cooldown_before ) and cd > p.cooldown_before + 0.001
                and A.Number( mana ) and mana <= p.mana_before - p.mana_cost + 1
                and A.Call( p.ability, "IsInAbilityPhase" ) == false and A.Call( bot, "IsUsingAbility" ) == false then
                event.status, event.evidence = "cast_completed", "own_cooldown_and_mana_transition_phase_ended";
            end
        elseif p.kind == "move" then
            local position = A.Position( bot );
            if position and D.Distance( position, p.location ) <= 40 then event.status, event.evidence = "move_completed", "observed_position" end;
        end
        if event.status then
            if event.status == "cancelled" or event.status == "rejected" then b.cancelled_order = p end;
            b.pending = nil; return { event };
        end;
        return {};
    end
    function b.Record( s, planning, event )
        if not s then return end;
        local force = event.status == "submit" or event.status == "aborted" or event.status == "plan_finished"
            or event.status == "attack_released" or event.status == "cast_completed" or event.status == "move_completed"
            or event.status == "cancelled" or event.status == "rejected";
        if not force and s.time < b.next_log then return end;
        b.next_log = s.time + cfg.log_interval_s;
        local record;
        if cfg.full_records and planning then record = Trace.Record( s, planning, event );
        else
            local selected = planning and planning.selected;
            record = { schema = b.schema, run_id = s.run_id, build = s.build, time = s.time,
                operation = cfg.operation, stage = cfg.stage, integration = s.integration,
                status = event.status, reason = event.reason, evidence = event.evidence,
                plan_id = event.plan_id, step_id = event.step_id,
                selected_option = selected and selected.option_id, selected_key = selected and selected.candidate_key,
                diagnostic_probe = selected and selected.diagnostic_probe or false,
                hero = s.hero, targets = s.targets, probe = s.probe,
                last_hits = s.last_hits, denies = s.denies, reward_status = "not_defined", outcome_attribution = "not_attributed" };
        end
        print( "[MIDBOT runtime] " .. Trace.Encode( record ) );
    end
    return b;
end
return M;
