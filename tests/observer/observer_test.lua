-- Isolated Bot API contract tests, not a Dota match/navmesh simulation.
local count = 0;
local function eq( a, b ) assert( a == b, tostring( a ) .. " ~= " .. tostring( b ) ) end;
local function test( name, fn ) fn(); count = count + 1; print( "PASS OBSERVER " .. name ) end;
local function scenario()
    local s = { time = 100, logs = {}, attacks = 0, moves = 0, clears = 0, casts = 0, wards_used = 0,
        hp = 1000, mana = 300, lh = 2, denies = 1, items = {}, wards = {}, mode = 1, action = 0 };
    local env = setmetatable( {}, { __index = _G } ); env._G = env; local cache = {};
    env.DotaTime = function() return s.time end; env.GameTime = env.DotaTime;
    env.GetScriptDirectory = function() return "bots" end;
    env.Vector = function( x, y, z ) return { x = x, y = y, z = z or 0 } end;
    env.GetHeightLevel = function( p ) return p.x > 200 and 2 or 1 end;
    env.GetHeroKills = function() return 0 end; env.GetHeroDeaths = function() return 0 end;
    env.GetLocationAlongLane = function( _, fraction ) return { x = ( fraction - 0.5 ) * 10000, y = 0 } end;
    env.GetUnitList = function() return s.wards end; env.IsLocationPassable = function() return not s.blocked end;
    env.BOT_MODE_NONE, env.BOT_MODE_RETREAT, env.LANE_MID, env.UNIT_LIST_ALLIED_WARDS = 0, 3, 2, 4;
    env.BOT_ACTION_TYPE_IDLE, env.BOT_ACTION_TYPE_NONE, env.BOT_ACTION_TYPE_MOVE_TO = 0, -1, 2;
    env.BOT_ACTION_DESIRE_NONE, env.BOT_ACTION_DESIRE_MODERATE = 0, 0.5;
    env.DAMAGE_TYPE_PHYSICAL, env.DAMAGE_TYPE_MAGICAL = 1, 2;
    env.print = function( line ) s.logs[#s.logs + 1] = line end;
    env.require = function( path )
        local p = path:match( "laning/.*" ); assert( p, path );
        if not cache[p] then local f = assert( loadfile( p .. ".lua" ) ); setfenv( f, env ); cache[p] = f() end;
        return cache[p];
    end;
    local function unit( name, x, hp )
        local u = { name = name, x = x, y = 0, hp = hp, max_hp = hp, visible = true };
        function u:IsNull() return false end; function u:IsAlive() return self.hp > 0 end;
        function u:CanBeSeen() return self.visible end; function u:IsInvulnerable() return false end;
        function u:IsAttackImmune() return false end; function u:IsMagicImmune() return false end;
        function u:GetLocation() return { x = self.x, y = self.y } end;
        function u:GetHealth() return self.hp end; function u:GetMaxHealth() return self.max_hp end;
        function u:GetMana() return 100 end; function u:GetHealthRegen() return 0 end;
        function u:GetArmor() return 2 end; function u:GetEvasion() return 0 end;
        function u:GetUnitName() return self.name end;
        function u:GetActualIncomingDamage( raw, damageType ) return raw * ( damageType == 2 and .75 or .9 ) end;
        function u:GetBountyGoldMin() return 30 end; function u:GetBountyGoldMax() return 40 end;
        function u:NumModifiers() return 0 end; function u:GetPlayerID() return 7 end;
        return u;
    end;
    s.unit = unit;
    local bot = unit( "npc_dota_hero_nevermore", 0, 1000 ); s.bot = bot;
    function bot:GetHealth() return s.hp end; function bot:GetMaxHealth() return 1000 end;
    function bot:GetMana() return s.mana end; function bot:GetMaxMana() return 300 end;
    function bot:GetTeam() return 2 end; function bot:GetLevel() return 4 end;
    function bot:GetGold() return 500 end;
    function bot:GetLastHits() return s.lh end; function bot:GetDenies() return s.denies end;
    function bot:GetActiveMode() return s.mode end; function bot:GetActiveModeDesire() return .5 end;
    function bot:GetCurrentActionType() return s.action end; function bot:GetLastAttackTime() return s.last_attack or 5 end;
    function bot:GetAttackRange() return 525 end; function bot:GetAttackDamage() return 100 end;
    function bot:GetBaseDamageVariance() return 10 end; function bot:GetAttackCombatProficiency() return 1 end;
    function bot:GetAttackPoint() return .5 end; function bot:GetSecondsPerAttack() return 1 end;
    function bot:GetFacing() return 0 end; function bot:IsUsingAbility() return s.casting or false end;
    function bot:IsChanneling() return false end; function bot:IsStunned() return false end;
    function bot:IsSilenced() return false end; function bot:GetAbilityPoints() return 0 end;
    function bot:IsHexed() return false end; function bot:IsDisarmed() return false end;
    function bot:GetItemInSlot( slot ) return s.items[slot] end;
    function bot:GetNearbyHeroes() return s.enemies end;
    function bot:GetNearbyLaneCreeps( _, enemy ) return enemy and s.creeps or {} end;
    function bot:GetNearbyTowers() return s.towers or {} end;
    function bot:GetAttackTarget() return s.creep end;
    function bot:Action_AttackUnit() s.attacks = s.attacks + 1 end;
    function bot:Action_MoveDirectly() s.moves = s.moves + 1 end;
    bot.Action_MoveToLocation = bot.Action_MoveDirectly;
    function bot:Action_ClearActions() s.clears = s.clears + 1 end;
    function bot:Action_UseAbility( ability ) s.casts = s.casts + 1; ability.cd = 5; s.mana = s.mana - 75 end;
    function bot:Action_UseAbilityOnLocation( item, p )
        s.wards_used = s.wards_used + 1; item.charges = item.charges - 1;
        local ward = unit( s.spawn_kind or "npc_dota_observer_wards", p.x, 100 ); ward.y = p.y;
        s.wards[#s.wards + 1] = ward;
    end;
    s.abilities = {};
    for i, name in ipairs( { "nevermore_shadowraze1", "nevermore_shadowraze2", "nevermore_shadowraze3", "nevermore_frenzy", "nevermore_requiem" } ) do
        local a = { name = name, cd = 0, ready = i <= 3, range = ( { 200, 450, 700 } )[i] };
        function a:GetName() return self.name end; function a:GetLevel() return 1 end;
        function a:IsFullyCastable() return self.ready end; function a:GetCooldownTimeRemaining() return self.cd end;
        function a:GetManaCost() return 75 end; function a:GetAbilityDamage() return 200 end;
        function a:IsInAbilityPhase() return false end;
        function a:GetSpecialValueFloat( key ) return key == "shadowraze_range" and self.range or ( key == "shadowraze_radius" and 250 or 0 ) end;
        s.abilities[name] = a;
    end;
    function bot:GetAbilityByName( name ) return s.abilities[name] end;
    function bot:GetAbilityInSlot( index ) return s.abilities[( { "nevermore_shadowraze1", "nevermore_shadowraze2", "nevermore_shadowraze3", "nevermore_frenzy", "nevermore_requiem" } )[index + 1]] end;
    s.enemy = unit( "npc_dota_hero_lina", 450, 500 ); s.creep = unit( "npc_dota_creep_badguys_ranged", 450, 50 );
    s.enemies, s.creeps = { s.enemy }, { s.creep };
    env.GetBot = function() return bot end;
    s.env = env; s.profile = env.require( "bots/laning/profile" );
    s.core = env.require( "bots/laning/observer/core" ); s.entry = env.require( "bots/laning/observer/entry" );
    s.shadow = env.require( "bots/laning/hybrid/shadow" ); s.ward = env.require( "bots/laning/hybrid/wards" );
    function s:ability_source( debug_enabled )
        local f = assert( io.open( "ability_item_usage_nevermore.lua", "r" ) ); local text = f:read( "*a" ); f:close();
        if debug_enabled then text = text:gsub( "local MIDBOT_DEBUG_MODIFIERS = false;", "local MIDBOT_DEBUG_MODIFIERS = true;" ) end;
        local chunk = assert( loadstring( text ) ); setfenv( chunk, self.env ); chunk();
    end;
    function s:ward_item( name )
        self.enemies, self.creeps = {}, {};
        local item = { name = name or "item_ward_observer", charges = 2 };
        function item:GetName() return self.name end; function item:GetCurrentCharges() return self.charges end;
        function item:GetSecondaryCharges() return 1 end; function item:IsFullyCastable() return true end;
        function item:GetCastRange() return 500 end; function item:GetToggleState() return false end;
        self.items[0] = item; return item;
    end;
    return s;
end

test( "one-Hz snapshots and shadow policy issue no orders", function()
    local s = scenario();
    for i = 0, 9 do s.time = 100 + i * .1; s.entry.Tick( s.bot ) end;
    s.time = 101.1; s.entry.Tick( s.bot );
    local snapshots = 0;
    for _, line in ipairs( s.logs ) do if line:find( '"kind":"snapshot"', 1, true ) then snapshots = snapshots + 1 end end;
    eq( snapshots, 2 ); eq( s.attacks + s.moves + s.clears + s.casts + s.wards_used, 0 );
    OBSERVER_SAMPLE_JSON = s.logs[1]:match( '%[MIDBOT observe%] (.*)' );
end );
test( "inventory, resources, mode, heights and counters are captured", function()
    local s = scenario(); s:ward_item(); local d = s.core.Capture( s.bot );
    eq( d.hero.last_hits, 2 ); eq( d.hero.items[1].name, "item_ward_observer" ); eq( d.hero.height_level, 1 );
    eq( d.hero.active_mode, 1 ); eq( d.hero.mana, 300 ); eq( d.attack_owner, "native_or_unattributed" );
end );
test( "souls zero is independent from last-hits; missing binding stays unknown", function()
    local s = scenario(); local d = s.core.Capture( s.bot ); eq( d.hero.souls, nil );
    function s.bot:NumModifiers() return 1 end;
    function s.bot:GetModifierName() return "modifier_nevermore_necromastery" end;
    function s.bot:GetModifierStackCount() return 0 end;
    d = s.core.Capture( s.bot ); eq( d.hero.souls, 0 ); eq( d.hero.last_hits, 2 );
end );
test( "hidden target resources are never read", function()
    local s = scenario(); s.enemy.visible = false; local read = 0;
    function s.enemy:GetHealth() read = read + 1; error( "hidden data" ) end;
    local d = s.core.Capture( s.bot ); eq( read, 0 ); eq( #d.targets, 1 );
end );
test( "missing terrain is unknown rather than level zero or lowground", function()
    local s = scenario(); s.env.GetHeightLevel = false; local d = s.core.Capture( s.bot );
    eq( d.height_status, "unavailable" ); eq( d.hero.height_level, nil ); eq( d.targets[1].uphill, nil );
end );
test( "uphill secure raze is only a shadow suggestion", function()
    local s = scenario(); local d = s.core.Capture( s.bot );
    local p = s.shadow.Decide( s.bot, d, s.core.State( s.bot ).handles );
    eq( p.selected.option_id, 2 ); eq( p.selected.guaranteed_kill, false ); eq( p.executed, false );
    eq( s.attacks + s.casts, 0 ); eq( p.action_masks['8'].available, false );
end );
test( "no mana masks the secure raze suggestion", function()
    local s = scenario(); s.mana = 0;
    local d = s.core.Capture( s.bot ); local p = s.shadow.Decide( s.bot, d, s.core.State( s.bot ).handles );
    eq( p.action_masks['2'].available, false );
end );
test( "wrong facing and silence each mask the raze suggestion", function()
    local s = scenario(); function s.bot:GetFacing() return 180 end;
    local d = s.core.Capture( s.bot ); local p = s.shadow.Decide( s.bot, d, s.core.State( s.bot ).handles );
    eq( p.action_masks['2'].available, false );
    function s.bot:GetFacing() return 0 end; function s.bot:IsSilenced() return true end;
    d = s.core.Capture( s.bot ); p = s.shadow.Decide( s.bot, d, s.core.State( s.bot ).handles ); eq( p.action_masks['2'].available, false );
end );
test( "ward vision does not erase the height difference", function()
    local s = scenario(); s.wards = { s.unit( "npc_dota_observer_wards", 450, 100 ) };
    local d = s.core.Capture( s.bot ); eq( d.targets[1].uphill, true );
end );
test( "native release evidence is observed but never counted as a hit", function()
    local s = scenario(); s.entry.Tick( s.bot ); s.last_attack = 6;
    function s.creep:GetIncomingTrackingProjectiles()
        return { { caster = s.bot, is_attack = true, location = { x = 20, y = 0 } } };
    end;
    s.time = 100.2; s.entry.Tick( s.bot ); local log = table.concat( s.logs, "\n" );
    assert( log:find( '"kind":"attack_release_observed"', 1, true ) );
    assert( log:find( '"hit":"unknown"', 1, true ) ); eq( s.attacks, 0 );
end );
test( "an attack timestamp without a projectile is not a release confirmation", function()
    local s = scenario(); s.entry.Tick( s.bot ); s.last_attack = 6; s.time = 100.2; s.entry.Tick( s.bot );
    local log = table.concat( s.logs, "\n" ); assert( log:find( '"kind":"attack_record_changed"', 1, true ) );
    assert( not log:find( '"kind":"attack_release_observed"', 1, true ) );
end );
test( "failure in observer never prevents the existing spell callback", function()
    local s = scenario(); s:ability_source(); s.entry.Tick = function() error( "injected observer failure" ) end;
    s.env.ConsiderRequiem = function() return .5 end;
    s.env.AbilityUsageThink(); eq( s.casts, 1 );
end );
test( "PR38 diagnostic stats coexist with structured observer without changing actions", function()
    local s = scenario(); s:ward_item(); s.enemies, s.creeps = {}, {};
    s:ability_source( true ); s.env.AbilityUsageThink();
    local log = table.concat( s.logs, "\n" );
    assert( log:find( "[MIDBOT diag] stats:", 1, true ) );
    assert( log:find( "[MIDBOT observe]", 1, true ) );
    assert( not log:find( "[MIDBOT ability ERROR]", 1, true ) );
    eq( s.casts + s.wards_used + s.attacks + s.moves, 0 );
end );
test( "missing observer module preserves baseline spells with a warning", function()
    local s = scenario(); local previous = s.env.require;
    s.env.require = function( path ) if path:find( "observer/entry", 1, true ) then error( "module unavailable" ) end; return previous( path ) end;
    s:ability_source(); s.env.ConsiderRequiem = function() return .5 end; s.env.AbilityUsageThink();
    eq( s.casts, 1 ); assert( s.logs[1]:find( "observer module unavailable", 1, true ) );
end );
test( "failure of the output sink does not change casting", function()
    local s = scenario(); s:ability_source(); s.env.print = function() error( "sink unavailable" ) end;
    s.env.ConsiderRequiem = function() return .5 end;
    s.env.AbilityUsageThink(); eq( s.casts, 1 );
end );
test( "actual cast and consumption are tracked without a hit label", function()
    local s = scenario(); s:ability_source(); s.env.ConsiderRequiem = function() return .5 end;
    s.env.AbilityUsageThink(); s.time = 100.1; s.entry.Tick( s.bot );
    local log = table.concat( s.logs, "\n" );
    assert( log:find( '"kind":"action_submitted"', 1, true ) );
    assert( log:find( '"kind":"cast_consumption_observed"', 1, true ) );
    assert( log:find( '"hit":"unknown"', 1, true ) );
end );
test( "observer can be disabled entirely without orders", function()
    local s = scenario(); s.profile.observer_enabled = false; s.entry.Tick( s.bot ); eq( #s.logs, 0 );
end );
test( "target collection is capped", function()
    local s = scenario(); for i = 1, 30 do s.creeps[i] = s.unit( "creep", i, 50 ) end;
    local d = s.core.Capture( s.bot ); eq( #d.targets, 16 ); eq( d.targets_truncated, true );
end );
test( "default play never places a ward", function()
    local s = scenario(); s:ward_item(); s.entry.AfterAbilities( s.bot ); eq( s.wards_used, 0 );
end );
test( "disabled observer or failed sink prevents new experimental ward orders", function()
    local s = scenario(); s:ward_item(); s.profile.wards_enabled = true; s.profile.observer_enabled = false;
    s.entry.AfterAbilities( s.bot ); eq( s.wards_used, 0 );
    s.profile.observer_enabled = true; s.env.print = function() error( "sink lost" ) end;
    s.entry.AfterAbilities( s.bot ); eq( s.wards_used, 0 );
end );
test( "opt-in ward places in range and observes resulting ward", function()
    local s = scenario(); s:ward_item(); s.profile.wards_enabled = true;
    s.entry.AfterAbilities( s.bot ); eq( s.wards_used, 1 ); eq( s.moves + s.attacks + s.clears, 0 );
    s.time = 100.1; s.entry.Tick( s.bot );
    assert( table.concat( s.logs, "\n" ):find( '"kind":"ward_observed"', 1, true ) );
end );
test( "nearby enemy and native movement each prevent ward use", function()
    local s = scenario(); s:ward_item(); s.enemies = { s.enemy };
    local p, why = s.ward.Plan( s.bot, s.core.State( s.bot ) ); eq( p, nil ); eq( why, "ward_enemy_nearby" );
    s.enemies = {}; s.action = 2; p, why = s.ward.Plan( s.bot, s.core.State( s.bot ) );
    eq( p, nil ); eq( why, "ward_preserve_native_action" );
end );
test( "an existing observer suppresses a redundant ward", function()
    local s = scenario(); s:ward_item(); s.wards = { s.unit( "npc_dota_observer_wards", 450, 100 ) };
    local p = s.ward.Plan( s.bot, s.core.State( s.bot ) ); eq( p, nil );
end );
test( "sentry does not substitute for observer vision", function()
    local s = scenario(); s:ward_item( "item_ward_sentry" );
    local p = s.ward.Plan( s.bot, s.core.State( s.bot ) ); eq( p, nil );
end );
test( "backpack wards are not treated as active inventory items", function()
    local s = scenario(); local item = s:ward_item(); s.items[0], s.items[6] = nil, item;
    local p, why = s.ward.Plan( s.bot, s.core.State( s.bot ) ); eq( p, nil ); eq( why, "ward_in_backpack_or_stash" );
end );
test( "unknown height and tower threat suppress placement", function()
    local s = scenario(); s:ward_item(); s.env.GetHeightLevel = false;
    local p = s.ward.Plan( s.bot, s.core.State( s.bot ) ); eq( p, nil );
    s.env.GetHeightLevel = function( p ) return p.x > 200 and 2 or 1 end;
    local tower = s.unit( "tower", 0, 2000 ); function tower:GetAttackRange() return 2000 end; s.towers = { tower };
    p = s.ward.Plan( s.bot, s.core.State( s.bot ) ); eq( p, nil );
end );
test( "ward timeout never becomes a successful placement", function()
    local s = scenario(); s:ward_item(); s.profile.wards_enabled = true;
    function s.bot:Action_UseAbilityOnLocation() s.wards_used = s.wards_used + 1 end;
    s.entry.AfterAbilities( s.bot ); s.time = 104; s.entry.Tick( s.bot );
    local log = table.concat( s.logs, "\n" ); assert( log:find( '"kind":"ward_outcome_unknown"', 1, true ) );
    assert( not log:find( '"kind":"ward_observed"', 1, true ) );
end );
test( "dispenser current-mode result is observed without assuming its toggle mapping", function()
    local s = scenario(); s:ward_item( "item_ward_dispenser" ); s.profile.wards_enabled = true;
    s.spawn_kind = "npc_dota_sentry_wards"; s.entry.AfterAbilities( s.bot ); s.time = 100.1; s.entry.Tick( s.bot );
    local log = table.concat( s.logs, "\n" ); assert( log:find( '"ward_kind":"sentry"', 1, true ) );
    eq( s.casts, 0 );
end );
OBSERVER_TEST_COUNT = count;
print( "OBSERVER PASSED " .. count );
