-- End-to-end wiring реальных Lua-модулей с изолированным Bot API.
-- Не является игровым run или подтверждением API установленного клиента.
local passed = 0;
local function eq( a, b ) assert( a == b, tostring( a ) .. " ~= " .. tostring( b ) ) end;
local function test( name, fn ) fn(); passed = passed + 1; print( "PASS RUNTIME " .. name ) end;
local function scenario( operation )
    local s = { time = 120, attacks = {}, casts = {}, moves = {}, logs = {}, cleared = 0, last_attack = 0 };
    local env = setmetatable( {}, { __index = _G } ); local cache = {};
    env.DotaTime = function() return s.time end;
    env.GetScriptDirectory = function() return "bots" end;
    env.Vector = function( x, y, z ) return { x = x, y = y, z = z or 0 } end;
    env.IsLocationPassable = function() return not s.impassable end;
    env.GetLaneFrontLocation = function() return { x = 1000, y = 0 } end;
    env.DAMAGE_TYPE_PHYSICAL, env.DAMAGE_TYPE_MAGICAL = 1, 2;
    env.DOTA_ABILITY_BEHAVIOR_NO_TARGET = 4;
    env.BOT_MODE_RETREAT, env.BOT_MODE_LANING, env.BOT_MODE_NONE = 3, 1, 0;
    env.BOT_ACTION_DESIRE_NONE, env.BOT_ACTION_DESIRE_LOW, env.BOT_ACTION_DESIRE_MODERATE = 0, 0.2, 0.5;
    env.BOT_ACTION_TYPE_ATTACK, env.BOT_ACTION_TYPE_ATTACKMOVE, env.BOT_MODE_DESIRE_MODERATE = 7, 8, 0.5; env.LANE_MID = 2;
    env.print = function( line ) s.logs[#s.logs + 1] = line end;
    env.require = function( path )
        local p = path:match( "laning/.*" );
        if not cache[p] then local chunk = assert( loadfile( p .. ".lua" ) ); setfenv( chunk, env ); cache[p] = chunk() end;
        return cache[p];
    end;
    local function unit( id, kind, x, hp )
        local u = { id = id, kind = kind, x = x, y = 0, hp = hp, max_hp = hp, projectiles = {}, stacks = 0 };
        function u:IsNull() return false end;
        function u:CanBeSeen() return not self.hidden end;
        function u:IsAlive() return self.hp > 0 end;
        function u:IsInvulnerable() return false end;
        function u:IsAttackImmune() return self.attack_immune or false end;
        function u:IsMagicImmune() return false end;
        function u:GetLocation() return { x = self.x, y = self.y } end;
        function u:GetHealth() return self.hp end;
        function u:GetMaxHealth() return self.max_hp end;
        function u:GetHealthRegen() return 0 end;
        function u:GetArmor() return 0 end;
        function u:GetUnitName() return self.kind == "hero" and "npc_dota_hero_nevermore" or "npc_dota_creep_badguys_ranged" end;
        function u:GetVelocity() return { x = 0, y = 0 } end;
        function u:GetActualIncomingDamage( raw, damageType ) return raw * ( damageType == 2 and ( self.magic_factor or 1 ) or 1 ) end;
        function u:GetBountyGoldMin() return 40 end;
        function u:GetBountyGoldMax() return 50 end;
        function u:GetBountyXP() return 60 end;
        function u:GetMana() return self.mana or 100 end;
        function u:GetMaxMana() return self.max_mana or 300 end;
        function u:GetLevel() return 3 end;
        function u:GetIncomingTrackingProjectiles() return self.projectiles end;
        function u:NumModifiers() return 1 end;
        function u:GetModifierName() return self.kind == "hero" and "modifier_nevermore_necromastery" or "modifier_nevermore_shadowraze_debuff" end;
        function u:GetModifierByName() return self.stacks > 0 and 0 or -1 end;
        function u:GetModifierStackCount() return self.stacks end;
        function u:GetModifierRemainingDuration() return 6 end;
        return u;
    end
    local bot = unit( "bot", "hero", 0, 1000 ); bot.mana, bot.stacks = 250, 10;
    local creep, enemy = unit( "c", "creep", 450, 40 ), unit( "h", "hero", 450, 1000 );
    s.bot, s.creep, s.enemy, s.unit = bot, creep, enemy, unit;
    s.enemy_creeps, s.allied_creeps, s.enemies, s.towers = { creep }, {}, {}, {};
    function bot:GetTeam() return 2 end;
    function bot:GetPlayerID() return 7 end;
    function bot:IsStunned() return self.stunned or false end;
    function bot:IsHexed() return false end;
    function bot:IsDisarmed() return self.disarmed or false end;
    function bot:IsSilenced() return self.silenced or false end;
    function bot:IsUsingAbility() return s.casting or false end;
    function bot:IsCastingAbility() return s.casting or false end;
    function bot:IsChanneling() return false end;
    function bot:GetActiveMode() return s.retreat and 3 or 1 end;
    function bot:GetManaRegen() return 0 end;
    function bot:GetXPNeededToLevel() return 100 end;
    function bot:GetAttackRange() return 550 end;
    function bot:GetSecondsPerAttack() return 1 end;
    function bot:GetAttackPoint() return 0.3 end;
    function bot:GetAttackProjectileSpeed() return 1000 end;
    function bot:GetSpellAmp() return 0 end;
    function bot:GetAttackDamage() return 55 end;
    function bot:GetBaseDamageVariance() return 5 end;
    function bot:GetAttackCombatProficiency() return 1 end;
    function bot:GetCurrentActionType() return s.action or 0 end;
    function bot:GetLastAttackTime() return s.last_attack end;
    function bot:GetLastHits() return s.last_hits or 0 end;
    function bot:GetDenies() return 0 end;
    function bot:GetNearbyLaneCreeps( _, isEnemy ) return isEnemy and s.enemy_creeps or s.allied_creeps end;
    function bot:GetNearbyHeroes( _, isEnemy ) return isEnemy and s.enemies or {} end;
    function bot:GetNearbyTowers() return s.towers end;
    function bot:IsFacingLocation() return not s.not_facing end;
    function bot:Action_AttackUnit( target, once ) s.attacks[#s.attacks + 1] = { target = target, once = once }; s.action = 7 end;
    function bot:Action_UseAbility( ability ) s.casts[#s.casts + 1] = ability end;
    function bot:Action_MoveDirectly( location ) s.moves[#s.moves + 1] = location end;
    bot.Action_MoveToLocation = bot.Action_MoveDirectly;
    function bot:Action_ClearActions() s.cleared = s.cleared + 1; s.action = 0 end;
    local abilities = {};
    for i, range in ipairs( { 200, 450, 700 } ) do
        local a = { name = "nevermore_shadowraze" .. i, cd = 0, phase = false,
            values = { shadowraze_damage = 40, damage_per_soul = 2, stack_bonus_damage = 10,
                duration = 6, shadowraze_range = range, shadowraze_radius = 250, shadowraze_cooldown = 3 } };
        function a:GetName() return self.name end;
        function a:GetLevel() return 1 end;
        function a:GetBehavior() return 4 end;
        function a:GetSpecialValueFloat( name ) return self.values[name] or 0 end;
        function a:GetManaCost() return 30 end;
        function a:GetCastPoint() return 0.55 end;
        function a:GetCooldown() return 9 end;
        function a:GetCooldownTimeRemaining() return self.cd end;
        function a:IsFullyCastable() return self.cd == 0 and bot.mana >= 30 end;
        function a:IsInAbilityPhase() return self.phase end;
        abilities[a.name] = a;
    end
    function bot:GetAbilityByName( name ) return abilities[name] end;
    s.abilities, s.env = abilities, env;
    s.profile = env.require( "bots/laning/profile" );
    s.profile.name, s.profile.controller, s.profile.runtime_enabled = "lane_probe", "midbot_runtime", true;
    s.cfg = env.require( "bots/laning/runtime/config" ); s.cfg.operation, s.cfg.lane_positioning = operation or "observe", false;
    s.guard = env.require( "bots/laning/runtime/guard" );
    s.observer = env.require( "bots/laning/runtime/observe" );
    s.backend = env.require( "bots/laning/runtime/backend" ).New( s.cfg );
    s.bridge = env.require( "bots/laning/advanced/bridge" );
    s.entry = env.require( "bots/laning/runtime/entry" );
    function s:channel() self.guard.LanePulse( self.bot, self.time ); self.guard.AbilityGate( self.bot ) end;
    function s:own( key )
        self:channel(); local p = { candidate_key = key or "p" };
        local ok, reason = self.backend.Acquire( self.bot, p ); eq( ok, false ); eq( reason, "awaiting_ability_plan_ack" );
        assert( self.guard.AbilityGate( self.bot ) ); assert( self.backend.Acquire( self.bot, p ) );
    end;
    function s:submit( kind )
        self:own();
        local snapshot = self.backend.Snapshot( self.bot ); local id = snapshot.targets[1].id;
        local order = { plan_id = "execution-1", step_id = 1, step = { kind = kind, target_id = id, ability_id = "nevermore_shadowraze2" } };
        assert( self.backend.Submit( self.bot, order ) ); return order;
    end
    return s;
end

test( "real collector emits serializable observations and exact visible bounty", function()
    local s = scenario(); local snap = s.backend.Snapshot( s.bot );
    eq( snap.hero.mana, 250 ); eq( snap.targets[1].creep_type, "ranged" ); eq( snap.targets[1].bounty_gold_min, 40 );
    local trace = s.env.require( "bots/laning/advanced/trace" ); assert( trace.Encode( snap ) );
    eq( snap.targets[1].attack_damage_effective, nil ); -- unverified estimate не переименован в ready profile
end );
test( "invisible enemies never expose resource getters", function()
    local s = scenario(); s.enemy.hidden = true; s.enemies = { s.enemy };
    s.enemy.GetMana = function() error( "hidden mana queried" ) end;
    local snap = s.backend.Snapshot( s.bot ); eq( #snap.enemy_knowledge, 0 );
end );
test( "observed enemy resources become last_seen under fog without cooldown reads", function()
    local s = scenario(); s.enemies = { s.enemy }; s.backend.Snapshot( s.bot ); s.enemy.hidden = true; s.time = s.time + 0.1;
    local snap = s.backend.Snapshot( s.bot ); eq( snap.enemy_knowledge[1].resource_status, "last_seen" );
    eq( snap.enemy_knowledge[1].spells.nevermore_shadowraze1, nil );
end );
test( "missing own API returns a clear failure and no orders", function()
    local s = scenario( "probe_attack" ); s.bot.GetMana = nil;
    eq( s.entry.Desire( s.bot ), 0 ); eq( #s.attacks, 0 ); eq( #s.casts, 0 );
end );
test( "observe mode collects through GetDesire but never submits", function()
    local s = scenario( "observe" ); eq( s.entry.Desire( s.bot ), 0 ); s:channel(); s.entry.Think( s.bot );
    assert( #s.logs > 0 ); eq( #s.attacks, 0 ); eq( #s.casts, 0 ); eq( #s.moves, 0 );
end );
test( "missing ability hook blocks even diagnostic attack", function()
    local s = scenario( "probe_attack" ); eq( s.entry.Desire( s.bot ), 0 ); s.entry.Think( s.bot ); eq( #s.attacks, 0 );
end );
test( "handshake and per-plan ACK are different barriers", function()
    local s = scenario(); s:channel(); assert( s.guard.ChannelReady( s.bot, s.time ) );
    local ok, reason = s.backend.Acquire( s.bot, { candidate_key = "p" } ); eq( ok, false ); eq( reason, "awaiting_ability_plan_ack" );
    eq( s.guard.Owns( s.bot, s.backend.token, s.time ), false );
end );
test( "expired heartbeat cannot renew an old plan silently", function()
    local s = scenario(); s:own(); local token = s.backend.token;
    s.time = s.time + 1; s.guard.LanePulse( s.bot, s.time ); eq( s.guard.Owns( s.bot, token, s.time ), false );
    s.guard.AbilityGate( s.bot ); local ok, reason = s.backend.Acquire( s.bot, { candidate_key = "p" } );
    eq( ok, false ); eq( reason, "awaiting_ability_plan_ack" );
end );
test( "single attack probe reaches actual Action_AttackUnit once", function()
    local s = scenario( "probe_attack" ); s.entry.Desire( s.bot ); s:channel(); s.entry.Think( s.bot ); eq( #s.attacks, 0 );
    s.guard.AbilityGate( s.bot ); s.time = s.time + 0.16; s:channel(); s.entry.Think( s.bot );
    eq( #s.attacks, 1 ); eq( s.attacks[1].once, true );
    s.time = s.time + 0.1; s:channel(); s.entry.Think( s.bot ); eq( #s.attacks, 1 );
end );
test( "submission and elapsed windup do not confirm attack release", function()
    local s = scenario( "probe_attack" ); s:submit( "attack" ); s.time = s.time + 0.31; s:channel();
    s.last_attack = 1; eq( #s.backend.Events( s.bot ), 0 );
end );
test( "new own projectile plus changed attack record confirms release", function()
    local s = scenario( "probe_attack" ); s:submit( "attack" ); s.time = s.time + 0.1; s:channel(); s.last_attack = 1;
    s.creep.projectiles = { { handle = 91, caster = s.bot, is_attack = true, location = { x = 40, y = 0 } } };
    local events = s.backend.Events( s.bot ); eq( #events, 1 ); eq( events[1].status, "attack_released" );
    eq( events[1].observed_at, s.time ); eq( #s.backend.Events( s.bot ), 0 );
end );
test( "foreign and anonymous projectiles cannot acknowledge our attack", function()
    local s = scenario( "probe_attack" ); s:submit( "attack" ); s.last_attack = 1;
    s.creep.projectiles = { { handle = 91, caster = s.enemy, is_attack = true, location = { x = 40, y = 0 } },
        { handle = 92, is_attack = true, location = { x = 40, y = 0 } } };
    eq( #s.backend.Events( s.bot ), 0 );
end );
test( "old projectile and unchanged attack record cannot become a new release", function()
    local s = scenario( "probe_attack" ); s.creep.projectiles = { { handle = 91, caster = s.bot, is_attack = true, location = { x = 40, y = 0 } } };
    s:submit( "attack" ); s.last_attack = 1; eq( #s.backend.Events( s.bot ), 0 );
end );
test( "target disappearance cancels instead of following into fog", function()
    local s = scenario( "probe_attack" ); s:submit( "attack" ); s.creep.hidden = true;
    eq( s.backend.Events( s.bot )[1].status, "cancelled" );
end );
test( "unconfirmed command times out and cleans up only owned actions", function()
    local s = scenario( "probe_attack" ); s:submit( "attack" );
    for i = 1, 21 do s.time = s.time + 0.1; s:channel() end;
    eq( s.backend.Events( s.bot )[1].status, "rejected" ); s.backend.Release( s.bot, "timeout" ); eq( s.cleared, 1 );
end );
test( "lost ownership must not clear another callback action", function()
    local s = scenario( "probe_attack" ); s:submit( "attack" ); s.time = s.time + 1;
    s.backend.Release( s.bot, "stale" ); eq( s.cleared, 0 );
end );
test( "raze is submitted as no-target only after fresh facing check", function()
    local s = scenario( "probe_raze" ); s:own(); local snap = s.backend.Snapshot( s.bot );
    local step = { kind = "raze", target_id = snap.targets[1].id, ability_id = "nevermore_shadowraze2" };
    s.not_facing = true;
    local ok = s.backend.Submit( s.bot, { plan_id = "p", step_id = 1, step = step } ); eq( ok, false ); eq( #s.casts, 0 );
    assert( s.backend.Prepare( s.bot, step ) ); eq( #s.moves, 1 ); eq( #s.casts, 0 );
    s.not_facing = false; assert( s.backend.Submit( s.bot, { plan_id = "p", step_id = 1, step = step } ) ); eq( #s.casts, 1 );
end );
test( "caster mana and cooldown transition confirm consumption not a hit", function()
    local s = scenario( "probe_raze" ); s:submit( "raze" ); eq( #s.backend.Events( s.bot ), 0 );
    s.abilities.nevermore_shadowraze2.cd, s.bot.mana = 9, 220;
    local event = s.backend.Events( s.bot )[1]; eq( event.status, "cast_completed" ); eq( event.reward, nil );
end );
test( "cooldown alone or unfinished cast phase cannot complete cast", function()
    local s = scenario( "probe_raze" ); s:submit( "raze" ); local a = s.abilities.nevermore_shadowraze2;
    a.cd = 9; eq( #s.backend.Events( s.bot ), 0 ); s.bot.mana, a.phase = 220, true; eq( #s.backend.Events( s.bot ), 0 );
end );
test( "silence and changed mana reject cast at submission", function()
    local s = scenario( "probe_raze" ); s:own(); local snap = s.backend.Snapshot( s.bot );
    local order = { plan_id = "p", step_id = 1, step = { kind = "raze", target_id = snap.targets[1].id, ability_id = "nevermore_shadowraze2" } };
    s.bot.mana = 20; eq( s.backend.Submit( s.bot, order ), false ); s.bot.mana, s.bot.silenced = 250, true;
    eq( s.backend.Submit( s.bot, order ), false );
end );
test( "unverified damage and cast-point readings keep policy attacks masked", function()
    local s = scenario( "execute" ); s:channel(); local snap = s.backend.Snapshot( s.bot );
    local planner, cfg = s.env.require( "bots/laning/advanced/planner" ), s.env.require( "bots/laning/advanced/config" );
    local planning = s.backend.Filter( s.bot, snap, planner.Build( snap, cfg ) ); eq( planning.option_masks[1].available, false );
end );
test( "bounded mid positioning is validated and finished by observed position", function()
    local s = scenario( "execute" ); s.cfg.lane_positioning = true; s:own();
    local step = { kind = "move", location = { x = 250, y = 0 } };
    assert( s.backend.Submit( s.bot, { plan_id = "p", step_id = 1, step = step } ) );
    eq( #s.moves, 1 ); eq( #s.backend.Events( s.bot ), 0 ); s.bot.x = 250;
    eq( s.backend.Events( s.bot )[1].status, "move_completed" );
end );
test( "impassable positioning cannot submit a move", function()
    local s = scenario( "execute" ); s:own(); s.impassable = true;
    eq( s.backend.Submit( s.bot, { plan_id = "p", step_id = 1, step = { kind = "move", location = { x = 250, y = 0 } } } ), false ); eq( #s.moves, 0 );
end );
test( "end-to-end chosen raze-secure then hero attack waits for real cast evidence", function()
    local s = scenario( "execute" ); s.cfg.stage = "combos"; s.cfg.option_allowlist = { [6] = true };
    for key in pairs( s.cfg.probes ) do if type( s.cfg.probes[key] ) == "boolean" then s.cfg.probes[key] = true end end;
    s.enemies = { s.enemy };
    s.entry.Desire( s.bot ); s:channel(); s.entry.Think( s.bot ); s.guard.AbilityGate( s.bot );
    s.time = s.time + 0.16; s:channel(); s.entry.Think( s.bot ); eq( #s.casts, 1 ); eq( #s.attacks, 0 );
    s.time = s.time + 0.1; s:channel(); s.entry.Think( s.bot ); eq( #s.attacks, 0 );
    s.casts[1].cd, s.bot.mana, s.creep.hp = 9, 220, 0;
    s.time = s.time + 0.1; s:channel(); s.entry.Think( s.bot );
    eq( #s.attacks, 1 ); eq( s.attacks[1].target, s.enemy );
end );
test( "isolated Lua module states cannot invent a shared handshake", function()
    local a, z = scenario(), scenario();
    a.guard.LanePulse( a.bot, a.time ); eq( z.guard.AbilityGate( a.bot ), false );
    eq( a.guard.ChannelReady( a.bot, a.time ), false );
end );
test( "probe limit remains one after completion and reentry", function()
    local s = scenario( "probe_attack" ); s.entry.Desire( s.bot ); s:channel(); s.entry.Think( s.bot ); s.guard.AbilityGate( s.bot );
    s.time = s.time + 0.16; s:channel(); s.entry.Think( s.bot ); eq( #s.attacks, 1 );
    s.last_attack = 1; s.creep.projectiles = { { handle = 31, caster = s.bot, is_attack = true, location = { x = 40, y = 0 } } };
    for i = 1, 10 do s.time = s.time + 0.1; s:channel(); s.entry.Think( s.bot ) end;
    s.entry.Leave( s.bot ); s:channel(); s.entry.Think( s.bot ); eq( #s.attacks, 1 );
end );
test( "attack then raze can cast while its confirmed projectile is still flying", function()
    local s = scenario( "execute" ); s.cfg.stage = "combos"; s.cfg.option_allowlist = { [7] = true };
    for k in pairs( s.cfg.probes ) do if type( s.cfg.probes[k] ) == "boolean" then s.cfg.probes[k] = true end end;
    s.enemies = { s.enemy };
    s.entry.Desire( s.bot ); s:channel(); s.entry.Think( s.bot ); s.guard.AbilityGate( s.bot );
    s.time = s.time + 0.16; s:channel(); s.entry.Think( s.bot ); eq( #s.attacks, 1 ); eq( #s.casts, 0 );
    s.time = s.time + 0.1; s:channel(); s.entry.Think( s.bot ); eq( #s.casts, 0 );
    s.last_attack = 1; s.enemy.projectiles = { { handle = 41, caster = s.bot, is_attack = true, location = { x = 80, y = 0 } } };
    s.time = s.time + 0.05; s:channel(); s.entry.Think( s.bot ); eq( #s.casts, 1 ); eq( #s.enemy.projectiles, 1 );
end );
test( "missing current action API cannot interrupt an unknown windup", function()
    local s = scenario( "probe_attack" ); s:own(); local snap = s.backend.Snapshot( s.bot ); s.bot.GetCurrentActionType = nil;
    eq( s.backend.Submit( s.bot, { plan_id = "p", step_id = 1, step = { kind = "attack", target_id = snap.targets[1].id } } ), false ); eq( #s.attacks, 0 );
end );
test( "wait after release starts at observed event time rather than original submit", function()
    local s = scenario(); local scheduler = s.env.require( "bots/laning/advanced/scheduler" );
    local state = scheduler.New();
    local plan = { available = true, candidate_key = "p", steps = { { kind = "attack", target_id = "c" }, { kind = "observe", duration_s = 0.5 } } };
    local cfg = s.env.require( "bots/laning/advanced/config" );
    assert( scheduler.Begin( state, 7, "joint", plan, 120, cfg, {} ) );
    local o = { time = 120, snapshot_time = 120, valid_targets = { c = true } }; local order = scheduler.Next( state, o, cfg );
    assert( scheduler.Event( state, { actor = 7, plan_id = order.plan_id, step_id = 1, status = "attack_released", observed_at = 120.4 } ) );
    o.time, o.snapshot_time = 120.6, 120.6; eq( scheduler.Next( state, o, cfg ).status, "waiting_window" );
    o.time, o.snapshot_time = 120.9, 120.9; eq( scheduler.Next( state, o, cfg ).status, "submit" );
end );
test( "own cast waiting keeps mode ownership but retreat immediately yields", function()
    local s = scenario( "probe_raze" ); s.entry.Desire( s.bot ); s:channel(); s.entry.Think( s.bot ); s.guard.AbilityGate( s.bot );
    s.time = s.time + 0.16; s:channel(); s.entry.Think( s.bot ); eq( #s.casts, 1 );
    s.casting = true; s.time = s.time + 0.1; s:channel(); assert( s.entry.Desire( s.bot ) > 0 );
    s.retreat = true; s.time = s.time + 0.1; eq( s.entry.Desire( s.bot ), 0 ); eq( s.guard.AbilityGate( s.bot ), false );
end );
test( "last attack record fallback requires explicit release calibration", function()
    local s = scenario( "probe_attack" ); s:submit( "attack" ); s.last_attack = 1;
    eq( #s.backend.Events( s.bot ), 0 ); s.cfg.probes.last_attack_time_release_verified = true;
    local event = s.backend.Events( s.bot )[1]; eq( event.status, "attack_released" ); eq( event.evidence, "build_calibrated_last_attack_record" );
end );
test( "unknown attack timing and active cast never become a new probe order", function()
    local s = scenario( "probe_attack" ); s.casting = true; s.entry.Desire( s.bot ); s:channel();
    s.entry.Think( s.bot ); eq( #s.attacks, 0 );
    s.cfg.probes.attack_point_seconds_verified = true; s.bot.GetAttackProjectileSpeed = function() return 0 end;
    eq( s.backend.Snapshot( s.bot ).hero.attack_point_s, nil );
end );
test( "PR23 IsReady hook alone cannot invent heartbeat or block all fallback casts", function()
    local s = scenario( "probe_attack" ); local chunk = assert( loadfile( "tests/laning/audit_sources/t016_pr23_b0773c2.lua" ) );
    setfenv( chunk, s.env ); chunk();
    s.entry.Desire( s.bot ); eq( s.env.JointExecutorOwnsBot( s.bot ), false );
    eq( s.guard.ChannelReady( s.bot, s.time ), false ); s.entry.Think( s.bot ); eq( #s.attacks, 0 );
end );
test( "PR23 modifier helpers are not silently assumed compatible with NumModifiers SDK", function()
    local s = scenario(); local chunk = assert( loadfile( "tests/laning/audit_sources/t016_pr23_b0773c2.lua" ) );
    setfenv( chunk, s.env ); chunk();
    eq( pcall( s.env.GetSoulsCount, s.bot ), false );
    local snap = s.backend.Snapshot( s.bot ); eq( snap.probe.own_modifiers[1].stacks, 10 );
end );
test( "HasActivePlan is a read-only status alias not permanent registration ownership", function()
    local s = scenario(); local backend = { schema = s.backend.schema, joint_executor_verified = true,
        Snapshot = s.backend.Snapshot, Validate = s.backend.Validate, Submit = s.backend.Submit,
        Events = s.backend.Events, Record = s.backend.Record };
    assert( s.bridge.Register( 7, backend ) ); eq( s.bridge.IsReady( 7 ), true ); eq( s.bridge.HasActivePlan( 7 ), false );
end );
test( "continuous inherited attack is replaced only after its next observed release", function()
    for _, action in ipairs( { 7, 8 } ) do
    local s = scenario( "probe_attack" ); s.action, s.last_attack = action, 1;
    s.bot.GetAttackTarget = function() return s.creep end;
    s:own(); local snap = s.backend.Snapshot( s.bot );
    local order = { plan_id = "p", step_id = 1, step = { kind = "attack", target_id = snap.targets[1].id } };
    eq( s.backend.Submit( s.bot, order ), false ); eq( #s.attacks, 0 );
    s.last_attack = 2; s.creep.projectiles = { { handle = 71, caster = s.bot, is_attack = true, location = { x = 80, y = 0 } } };
    assert( s.backend.Submit( s.bot, order ) ); eq( #s.attacks, 1 );
    eq( #s.backend.Events( s.bot ), 0 ); -- старый native projectile не подтверждает новую атаку
    end
end );
print( "RUNTIME PASSED " .. passed );

-- Append to runtime_test.lua to reuse its isolated API fixture and real modules.
local audited = 0;
local function audit( name, fn ) fn(); audited = audited + 1; print( "PASS COMBINED_PR25 " .. name ) end;
local function loadCandidate( s, missingGuard, debugEnabled, currentAbility )
    local f = assert( io.open( currentAbility and "ability_item_usage_nevermore.lua"
        or "tests/laning/audit_sources/t016_merged_f4bf3aa.lua", "r" ) ); local text = f:read( "*a" ); f:close();
    if debugEnabled then text = text:gsub( "local MIDBOT_DEBUG_MODIFIERS = false;", "local MIDBOT_DEBUG_MODIFIERS = true;" ) end;
    local previous = s.env.require;
    if missingGuard then s.env.require = function( path )
        if path:match( "runtime/guard$" ) then error( "not installed in old build" ) end;
        return previous( path );
    end end;
    local chunk = assert( loadstring( text, "PR25-exact-ability" ) ); setfenv( chunk, s.env ); chunk(); s.env.require = previous;
    s.env.GetBot = function() return s.bot end; s.env.GameTime = function() return s.time end;
    s.level_reads, s.autonomous = 0, 0;
    s.bot.GetAbilityPoints = function() s.level_reads = s.level_reads + 1; return 0 end;
    s.env.ConsiderRequiem = function() s.autonomous = s.autonomous + 1; return 0 end;
    s.env.ConsiderRazeOnHero = function() return 0 end;
    s.env.ConsiderRazeOnCreeps = function() return 0 end;
end
audit( "actual PR25 callback supplies heartbeat while observe keeps autonomy", function()
    local s = scenario( "observe" ); loadCandidate( s ); s.entry.Desire( s.bot ); s.env.AbilityUsageThink();
    eq( s.guard.ChannelReady( s.bot, s.time ), true ); eq( s.autonomous, 1 ); eq( s.level_reads, 1 );
    s.entry.Think( s.bot ); eq( #s.attacks, 0 ); eq( #s.casts, 0 );
end );
audit( "actual callback ACKs only the requested plan and still executes leveling", function()
    local s = scenario( "probe_attack" ); loadCandidate( s ); s.guard.LanePulse( s.bot, s.time ); s.env.AbilityUsageThink();
    local ok, reason = s.backend.Acquire( s.bot, { candidate_key = "p" } ); eq( ok, false ); eq( reason, "awaiting_ability_plan_ack" );
    s.autonomous = 0; s.env.AbilityUsageThink(); assert( s.backend.Acquire( s.bot, { candidate_key = "p" } ) );
    eq( s.autonomous, 0 ); eq( s.level_reads, 2 );
    s.backend.Release( s.bot, "plan_finished" ); s.env.AbilityUsageThink(); eq( s.autonomous, 1 );
end );
audit( "casting early return does not starve heartbeat", function()
    local s = scenario( "observe" ); loadCandidate( s ); s.casting = true;
    s.guard.LanePulse( s.bot, s.time ); s.env.AbilityUsageThink();
    eq( s.guard.ChannelReady( s.bot, s.time ), true ); eq( s.autonomous, 0 );
end );
audit( "NumModifiers-only and GetModifierCount-only helpers both work", function()
    local s = scenario(); loadCandidate( s ); eq( s.env.GetSoulsCount( s.bot ), 10 );
    s.creep.stacks = 2; eq( s.env.GetRazeDebuffStacks( s.creep ), 2 );
    s.bot.NumModifiers = nil; s.bot.GetModifierCount = function() return 1 end;
    eq( s.env.GetSoulsCount( s.bot ), 10 );
    s.bot.GetModifierCount = nil; eq( s.env.GetSoulsCount( s.bot ), nil );
end );
audit( "old build without guard retains autonomous abilities", function()
    local s = scenario(); loadCandidate( s, true ); s.env.AbilityUsageThink(); eq( s.autonomous, 1 );
    eq( s.env.JointExecutorOwnsBot( s.bot ), false );
end );
audit( "actual PR25 hook completes the full one-attack runtime path", function()
    local s = scenario( "probe_attack" ); loadCandidate( s );
    s.entry.Desire( s.bot ); s.env.AbilityUsageThink(); s.entry.Think( s.bot ); eq( #s.attacks, 0 );
    s.time = s.time + 0.16; s.entry.Desire( s.bot ); s.env.AbilityUsageThink(); s.entry.Think( s.bot ); eq( #s.attacks, 1 );
    s.creep.projectiles = { { handle = 901, caster = s.bot, is_attack = true, location = { x = 50, y = 0 } } }; s.last_attack = 1;
    s.time = s.time + 0.1; s.entry.Desire( s.bot ); s.env.AbilityUsageThink(); s.entry.Think( s.bot );
    s.autonomous = 0; s.env.AbilityUsageThink(); eq( s.autonomous, 1 ); eq( s.bridge.HasActivePlan( 7 ), false );
end );
audit( "actual PR25 hook supports chosen raze-secure then hero attack", function()
    local s = scenario( "execute" ); loadCandidate( s ); s.cfg.stage = "combos"; s.cfg.option_allowlist = { [6] = true };
    for key in pairs( s.cfg.probes ) do if type( s.cfg.probes[key] ) == "boolean" then s.cfg.probes[key] = true end end;
    s.enemies = { s.enemy };
    s.entry.Desire( s.bot ); s.env.AbilityUsageThink(); s.entry.Think( s.bot );
    s.time = s.time + 0.16; s.entry.Desire( s.bot ); s.env.AbilityUsageThink(); s.entry.Think( s.bot ); eq( #s.casts, 1 ); eq( #s.attacks, 0 );
    s.casts[1].cd, s.bot.mana, s.creep.hp = 9, 220, 0;
    s.time = s.time + 0.1; s.entry.Desire( s.bot ); s.env.AbilityUsageThink(); s.entry.Think( s.bot ); eq( #s.attacks, 1 ); eq( s.attacks[1].target, s.enemy );
end );
audit( "debug diagnostics with NumModifiers do not read hidden enemies", function()
    local s = scenario(); loadCandidate( s, false, true ); s.enemies = { s.enemy }; s.enemy.hidden = true;
    s.enemy.NumModifiers = function() error( "hidden modifiers read" ) end;
    assert( pcall( s.env.DebugPrintModifiers, s.bot ) ); assert( #s.logs > 0 );
end );
print( "COMBINED_PR25 PASSED " .. audited );

local stability = 0;
local function stabletest( name, fn ) fn(); stability = stability + 1; print( "PASS STABILITY " .. name ) end;
local function frame( s )
    s.entry.Desire( s.bot ); s.env.AbilityUsageThink(); local result = s.entry.Think( s.bot );
    s.time = s.time + 0.1; return result;
end
stabletest( "lane probe travels from base toward mid and submits exactly one attack via actual callback", function()
    local s = scenario( "lane_probe" ); loadCandidate( s ); s.cfg.lane_positioning = true;
    s.bot.x, s.creep.x = -2000, 1000;
    local applied = 0;
    for i = 1, 70 do
        frame( s );
        if #s.moves > applied then
            for j = applied + 1, #s.moves do
                assert( s.moves[j].x > s.bot.x ); assert( s.moves[j].x - s.bot.x <= s.cfg.move_step + 1 );
                s.bot.x, s.bot.y = s.moves[j].x, s.moves[j].y;
            end;
            applied = #s.moves;
        end;
        if #s.attacks > 0 then
            s.last_attack = 1;
            s.creep.projectiles = { { caster = s.bot, is_attack = true, location = { x = s.bot.x + 30, y = 0 } } };
        end;
    end;
    assert( #s.moves > 0 ); eq( #s.attacks, 1 ); eq( #s.casts, 0 );
    eq( s.cfg.probes.attack_damage_verified, false ); eq( s.cfg.probes.attack_point_seconds_verified, false );
    eq( s.cfg.probes.last_attack_time_release_verified, false );
    local found = false; for _, line in ipairs( s.logs ) do if line:find( '"status":"attack_released"', 1, true ) then found = true end end;
    assert( found, "handleless projectile plus changed record must confirm observed release" );
end );
stabletest( "one-hit probe cannot farm repeatedly or cast even through direct submission", function()
    local s = scenario( "lane_probe" ); s.bot.x = 600; s:submit( "attack" );
    local snap = s.backend.Snapshot( s.bot );
    local ok, reason = s.backend.Submit( s.bot, { step = { kind = "attack", target_id = snap.targets[1].id } } );
    eq( ok, false ); eq( reason, "probe_limit_reached" );
    eq( s.backend.Submit( s.bot, { step = { kind = "raze" } } ), false ); eq( #s.attacks, 1 ); eq( #s.casts, 0 );
end );
stabletest( "observe remains strictly without orders despite enabled lane positioning", function()
    local s = scenario( "observe" ); loadCandidate( s ); s.cfg.lane_positioning = true; s.bot.x = -2000;
    for i = 1, 30 do frame( s ) end;
    eq( #s.moves, 0 ); eq( #s.attacks, 0 ); eq( #s.casts, 0 );
end );
stabletest( "missing hook never permits lane-probe movement", function()
    local s = scenario( "lane_probe" ); s.cfg.lane_positioning = true; s.bot.x = -2000;
    for i = 1, 20 do s.entry.Think( s.bot ); s.time = s.time + 0.1 end;
    eq( #s.moves, 0 ); eq( #s.attacks, 0 );
    local d = s.guard.Diagnostics( s.bot, s.time ); eq( d.ability_calls, 0 ); eq( d.channel_ready, false );
end );
stabletest( "nearby enemy hero disables controlled lane probe without adding harassment", function()
    local s = scenario( "lane_probe" ); loadCandidate( s ); s.cfg.lane_positioning = true; s.enemies = { s.enemy };
    for i = 1, 20 do frame( s ) end;
    eq( #s.moves, 0 ); eq( #s.attacks, 0 ); eq( #s.casts, 0 ); eq( s.entry.Desire( s.bot ), 0 );
end );
stabletest( "freshly entered tower threat rejects an already acknowledged diagnostic attack", function()
    local s = scenario( "lane_probe" ); s.bot.x = 600; s:own();
    local snap = s.backend.Snapshot( s.bot ); local tower = s.unit( "tower", "tower", 800, 2000 );
    tower.GetAttackRange = function() return 700 end; tower.GetSecondsPerAttack = function() return 1 end;
    s.towers = { tower };
    eq( s.backend.Submit( s.bot, { step = { kind = "attack", target_id = snap.targets[1].id } } ), false );
    eq( #s.attacks, 0 );
end );
stabletest( "probe never attacks a hero or a creep outside the mid neighborhood", function()
    local s = scenario( "lane_probe" ); s.bot.x, s.creep.x = -2000, -1800; s:own();
    local snap = s.backend.Snapshot( s.bot );
    eq( s.backend.Submit( s.bot, { step = { kind = "attack", target_id = snap.targets[1].id } } ), false );
    s.bot.x, s.enemy.x, s.enemies = 600, 700, { s.enemy }; snap = s.backend.Snapshot( s.bot );
    eq( s.backend.Submit( s.bot, { step = { kind = "attack", target_id = snap.targets[#snap.targets].id } } ), false );
    eq( #s.attacks, 0 );
end );
stabletest( "lane probe holds mode at mid after its one order while other modes can still retreat", function()
    local s = scenario( "lane_probe" ); loadCandidate( s ); s.bot.x = 1000; s.enemy_creeps = {};
    frame( s ); assert( s.entry.Desire( s.bot ) > 0 ); eq( #s.moves, 0 ); eq( #s.attacks, 0 );
    s.retreat = true; eq( s.entry.Desire( s.bot ), 0 );
end );
stabletest( "sparse heartbeat is measured and expired ownership stays blocked", function()
    local s = scenario( "lane_probe" ); s:own(); local first = s.guard.Diagnostics( s.bot, s.time );
    eq( first.lease_state, "acked" ); eq( first.ability_seen_age_s, 0 );
    s.time = s.time + 0.5; s.guard.LanePulse( s.bot, s.time );
    local d = s.guard.Diagnostics( s.bot, s.time ); eq( d.channel_ready, false ); eq( d.ability_seen_age_s, 0.5 );
    eq( d.owner_ttl_s, 0.35 ); eq( s.guard.Owns( s.bot, s.backend.token, s.time ), false );
end );
stabletest( "ability callback before lane callback is recorded without inventing accepted heartbeat", function()
    local s = scenario( "observe" ); eq( s.guard.AbilityGate( s.bot ), false );
    local d = s.guard.Diagnostics( s.bot, s.time ); eq( d.ability_calls, 1 ); eq( d.channel_ready, false );
    eq( d.ability_accepted_age_s, nil ); s.guard.LanePulse( s.bot, s.time );
    s.guard.AbilityGate( s.bot ); eq( s.guard.ChannelReady( s.bot, s.time ), true );
end );
stabletest( "lane probe has a bounded local approach when creep is just beyond attack range", function()
    local s = scenario( "lane_probe" ); loadCandidate( s ); s.cfg.lane_positioning = true;
    s.bot.x, s.creep.x = 1000, 1600;
    for i = 1, 4 do frame( s ) end;
    assert( #s.moves > 0 ); assert( s.moves[1].x > 1000 and s.moves[1].x <= 1250 ); eq( #s.attacks, 0 );
end );
stabletest( "absence of a mid anchor never creates a lane-probe order", function()
    local s = scenario( "lane_probe" ); loadCandidate( s ); s.cfg.lane_positioning = true; s.env.GetLaneFrontLocation = nil;
    for i = 1, 10 do frame( s ) end;
    eq( #s.moves, 0 ); eq( #s.attacks, 0 );
end );
stabletest( "pregame and expired lane window cannot run controlled lane probe", function()
    for _, time in ipairs( { -1, 601 } ) do
        local s = scenario( "lane_probe" ); loadCandidate( s ); s.time = time;
        frame( s ); eq( #s.moves, 0 ); eq( #s.attacks, 0 );
    end;
end );
stabletest( "missing current-action API cannot become movement from base", function()
    local s = scenario( "lane_probe" ); loadCandidate( s ); s.cfg.lane_positioning = true; s.bot.x = -2000;
    s.bot.GetCurrentActionType = nil;
    for i = 1, 20 do frame( s ) end;
    eq( #s.moves, 0 ); eq( #s.attacks, 0 );
end );
stabletest( "lane mode selection survives heartbeat pause without granting command ownership", function()
    local s = scenario( "lane_probe" ); loadCandidate( s ); s.cfg.lane_positioning = true; s.bot.x = -2000;
    s.entry.Desire( s.bot ); s.env.AbilityUsageThink(); s.time = s.time + 0.5;
    assert( s.entry.Desire( s.bot ) > 0 );
    local result = s.entry.Think( s.bot ); eq( result.status, "waiting_owner" );
    eq( #s.moves, 0 ); eq( #s.attacks, 0 ); eq( s.guard.ChannelReady( s.bot, s.time ), false );
end );
stabletest( "fresh enemy threat wins over holding lane during a heartbeat pause", function()
    local s = scenario( "lane_probe" ); loadCandidate( s ); s.entry.Desire( s.bot ); s.env.AbilityUsageThink();
    s.time = s.time + 0.5; s.enemies = { s.enemy };
    eq( s.entry.Desire( s.bot ), 0 ); eq( #s.moves, 0 );
end );
stabletest( "probe log identifies driver, actual mode, heartbeat ages and diagnostic status", function()
    local s = scenario( "lane_probe" ); loadCandidate( s ); frame( s ); frame( s );
    local joined = table.concat( s.logs, "\n" );
    assert( joined:find( '"diagnostic_probe":true', 1, true ) );
    assert( joined:find( '"ability_seen_age_s":', 1, true ) );
    assert( joined:find( '"active_mode":1', 1, true ) );
    assert( joined:find( '"think_calls":', 1, true ) );
    assert( joined:find( '"reason":"awaiting_ability_plan_ack"', 1, true ) );
end );
print( "STABILITY PASSED " .. stability );

local movementTests = 0;
local function movetest( name, fn ) fn(); movementTests = movementTests + 1; print( "PASS MOVE_RUNTIME " .. name ) end;
local function positioning( s )
    s.cfg.lane_positioning = true;
    local snapshot = s.backend.Snapshot( s.bot );
    local planner = s.env.require( "bots/laning/advanced/planner" );
    local config = s.env.require( "bots/laning/advanced/config" );
    return s.backend.Filter( s.bot, snapshot, planner.Build( snapshot, config ) );
end
movetest( "blocked movement is masked before a plan acquires ownership", function()
    local s = scenario( "lane_probe" ); s.bot.x, s.creep.x, s.impassable = -2000, 1000, true;
    local p = positioning( s );
    for _, candidate in ipairs( p.candidates ) do
        for _, step in ipairs( candidate.steps ) do
            if step.kind == "move" then eq( candidate.available, false ); eq( candidate.mask_reason, "move_point_impassable" ) end;
        end;
    end;
    eq( p.selected.available, false ); eq( #s.moves, 0 );
end );
movetest( "persistent blockage waits instead of repeatedly submitting invalid points", function()
    local s = scenario( "lane_probe" ); loadCandidate( s ); s.cfg.lane_positioning = true;
    s.bot.x, s.creep.x, s.impassable = -2000, 1000, true;
    for i = 1, 25 do frame( s ) end;
    eq( #s.moves, 0 ); eq( #s.attacks, 0 );
    local log = table.concat( s.logs, "\n" );
    assert( log:find( '"reason":"move_point_impassable"', 1, true ) );
    assert( not log:find( 'unsupported_order', 1, true ) );
end );
movetest( "blocked direct step can choose a checked bounded side step", function()
    local s = scenario( "lane_probe" ); s.bot.x, s.creep.x = -2000, 1000;
    s.env.IsLocationPassable = function( v ) return not ( v.x > -1950 and math.abs( v.y ) < 20 ) end;
    local p = positioning( s ); eq( p.selected.available, true );
    local step = p.selected.steps[1]; eq( step.kind, "move" );
    assert( step.location.x > s.bot.x and math.abs( step.location.y ) > 20 );
    s:own( p.selected.candidate_key );
    assert( s.backend.Submit( s.bot, { plan_id = "side", step_id = 1, step = step } ) );
    eq( #s.moves, 1 ); eq( #s.attacks, 0 );
end );
movetest( "point becoming blocked after ACK fails with a precise reason", function()
    local s = scenario( "execute" ); s:own(); s.impassable = true;
    local ok, reason = s.backend.Submit( s.bot, { step = { kind = "move", location = { x = 250, y = 0 } } } );
    eq( ok, false ); eq( reason, "move_point_impassable" ); eq( #s.moves, 0 );
end );
movetest( "position drift cannot extend an acknowledged step", function()
    local s = scenario( "execute" ); s:own(); s.bot.x = -100;
    local ok, reason = s.backend.Submit( s.bot, { step = { kind = "move", location = { x = 250, y = 0 } } } );
    eq( ok, false ); eq( reason, "move_step_too_long" ); eq( #s.moves, 0 );
end );
movetest( "unavailable passability API is a controlled wait", function()
    local s = scenario( "lane_probe" ); s.bot.x, s.creep.x = -2000, 1000; s.env.IsLocationPassable = false;
    local p = positioning( s ); eq( p.selected.available, false );
    eq( p.selected.mask_reason, "move_passability_unavailable" ); eq( #s.moves, 0 );
end );
movetest( "throwing passability API cannot crash the driver", function()
    local s = scenario( "execute" ); s:own();
    s.env.IsLocationPassable = function() error( "test API failure" ) end;
    local ok, reason = s.backend.Submit( s.bot, { step = { kind = "move", location = { x = 250, y = 0 } } } );
    eq( ok, false ); eq( reason, "move_passability_failed" ); eq( #s.moves, 0 );
end );
movetest( "compact records include the rejected point and fresh validation phase", function()
    local s = scenario( "execute" ); s:own(); s.impassable = true;
    local ok, reason = s.backend.Submit( s.bot, { step = { kind = "move", location = { x = 250, y = 0 } } } );
    eq( ok, false ); s.backend.Record( s.backend.snapshot, nil, { status = "aborted", reason = reason } );
    local log = s.logs[#s.logs];
    assert( log:find( '"movement":', 1, true ) );
    assert( log:find( '"phase":"submission"', 1, true ) );
    assert( log:find( '"destination":{"x":250,"y":0}', 1, true ) );
end );
print( "MOVE_RUNTIME PASSED " .. movementTests );

local profileTests = 0;
local function profiletest( name, fn ) fn(); profileTests = profileTests + 1; print( "PASS PROFILE_RUNTIME " .. name ) end;
profiletest( "play profile cannot create heartbeat, channel or ownership", function()
    local s = scenario( "lane_probe" ); s.profile.runtime_enabled = false;
    eq( s.guard.LanePulse( s.bot, s.time ), nil ); eq( s.guard.AbilityGate( s.bot ), false );
    eq( s.guard.ChannelReady( s.bot, s.time ), false );
    local ok, reason = s.guard.Acquire( s.bot, "p", s.time ); eq( ok, false ); eq( reason, "runtime_profile_disabled" );
    eq( s.guard.Diagnostics( s.bot, s.time ).ability_calls, 0 );
end );
profiletest( "play rejects accidental runtime entry calls before and after ten minutes", function()
    local s = scenario( "lane_probe" ); s.profile.runtime_enabled = false; s.cfg.lane_positioning = true;
    for _, time in ipairs( { 0, 120, 599, 600, 601, 900 } ) do
        s.time = time; eq( s.entry.Desire( s.bot ), 0 ); s.entry.Think( s.bot );
    end;
    eq( #s.moves, 0 ); eq( #s.attacks, 0 ); eq( #s.casts, 0 );
end );
profiletest( "disabled profile revokes a previous lease without clearing other actions", function()
    local s = scenario( "lane_probe" ); s:own(); local token = s.backend.token;
    assert( s.guard.Owns( s.bot, token, s.time ) ); s.profile.runtime_enabled = false;
    eq( s.guard.AbilityGate( s.bot ), false ); eq( s.guard.Owns( s.bot, token, s.time ), false );
    eq( s.guard.Diagnostics( s.bot, s.time ).lease_state, "none" );
    s.entry.Leave( s.bot ); eq( s.cleared, 0 );
end );
profiletest( "actual merged PR32 ability callback stays autonomous in play", function()
    local s = scenario( "lane_probe" ); loadCandidate( s, false, false, true );
    s.profile.runtime_enabled = false; s.env.AbilityUsageThink();
    eq( s.autonomous, 1 ); eq( s.level_reads, 1 );
    local log = table.concat( s.logs, "\n" ); assert( not log:find( "[MIDBOT ability ERROR]", 1, true ) );
end );
profiletest( "truthy nonboolean config cannot enable the controller", function()
    local s = scenario( "lane_probe" ); s.profile.runtime_enabled = "true";
    eq( s.entry.Desire( s.bot ), 0 ); eq( s.guard.AbilityGate( s.bot ), false );
end );
profiletest( "actual merged callback still acknowledges a probe in enabled profile", function()
    local s = scenario( "probe_attack" ); loadCandidate( s, false, false, true );
    s.entry.Desire( s.bot ); s.env.AbilityUsageThink();
    s.entry.Think( s.bot ); eq( #s.attacks, 0 );
    s.env.AbilityUsageThink(); s.time = s.time + 0.16; s.entry.Think( s.bot );
    eq( #s.attacks, 1 );
end );
print( "PROFILE_RUNTIME PASSED " .. profileTests );
