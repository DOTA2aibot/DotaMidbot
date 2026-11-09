-- Контрактный mock Bot API. Проверяет wiring реальных файлов, не заменяет Dota run.
local total = 0;
local function eq( a, b ) assert( a == b, tostring( a ) .. " ~= " .. tostring( b ) ) end;
local function test( name, fn ) fn(); total = total + 1; print( "PASS ADAPTER " .. name ) end;
local function scenario( options )
    options = options or {};
    local s = { time = 120, attacks = {}, moves = {}, logs = {}, enemies = {}, allies = {},
        enemy_creeps = {}, allied_creeps = {}, towers = {}, last_hits = 0, denies = 0 };
    local function unit( options )
        local u = options or {}; u.hp = u.hp or 40; u.max_hp = u.max_hp or 300;
        u.location = u.location or 300;
        function u:IsNull() return self.is_null or false end;
        function u:CanBeSeen() return not self.hidden end;
        function u:IsAlive() return not self.dead end;
        function u:IsInvulnerable() return self.invulnerable or false end;
        function u:IsAttackImmune() return false end;
        function u:IsIllusion() return false end;
        function u:GetLocation() return self.location end;
        function u:GetHealth() if self.hide_after_hp then self.hidden = true end; return self.hp end;
        function u:GetMaxHealth() return self.max_hp end;
        function u:GetHealthRegen() return 0 end;
        function u:GetActualIncomingDamage( damage ) return damage end;
        function u:GetUnitName() return self.name or "npc_dota_creep_goodguys_melee" end;
        function u:GetAttackRange() return self.range or 700 end;
        return u;
    end
    local bot = unit( { hp = 1000, max_hp = 1000, location = 0, name = "npc_dota_hero_nevermore" } );
    s.bot, s.unit = bot, unit;
    function bot:GetNearbyTowers() return s.towers end;
    function bot:GetNearbyHeroes( _, enemy ) return enemy and s.enemies or s.allies end;
    function bot:GetNearbyLaneCreeps( _, enemy ) return enemy and s.enemy_creeps or s.allied_creeps end;
    function bot:IsStunned() return self.stunned or false end;
    function bot:IsHexed() return false end;
    function bot:IsDisarmed() return false end;
    function bot:IsUsingAbility() return self.casting or false end;
    function bot:IsCastingAbility() return false end;
    function bot:IsChanneling() return false end;
    function bot:GetActiveMode() return s.retreating and 99 or 1 end;
    function bot:GetAttackProjectileSpeed() return 1000 end;
    function bot:GetAttackPoint() return 0.3 end;
    function bot:GetSecondsPerAttack() return 1 end;
    function bot:GetAttackDamage() return 55 end;
    function bot:GetBaseDamageVariance() return 5 end;
    function bot:GetAttackRange() return 500 end;
    function bot:GetTeam() return 2 end;
    function bot:GetPlayerID() return 7 end;
    function bot:GetLastHits() return s.last_hits end;
    function bot:GetDenies() return s.denies end;
    function bot:Action_AttackUnit( target, once ) s.attacks[#s.attacks + 1] = { target, once } end;
    function bot:Action_MoveToLocation( location ) s.moves[#s.moves + 1] = location end;
    local env = setmetatable( {}, { __index = _G } );
    env.GetScriptDirectory = function() return "bots" end;
    env.GetBot = function() return bot end;
    env.DotaTime = function() return s.time end;
    env.GetUnitToLocationDistance = function( u, loc ) return math.abs( u.location - loc ) end;
    env.GetUnitToUnitDistance = function( a, b ) return math.abs( a.location - b.location ) end;
    env.GetLaneFrontLocation = function() return s.anchor or 0 end;
    env.DAMAGE_TYPE_PHYSICAL, env.LANE_MID = 1, 2;
    env.BOT_MODE_RETREAT, env.BOT_MODE_NONE = 99, 0;
    env.BOT_MODE_DESIRE_MODERATE, env.BOT_MODE_DESIRE_LOW = 0.5, 0.2;
    env.print = function( line ) s.logs[#s.logs + 1] = line end;
    env.require = function( path )
        local localPath = path:match( "laning/.*" );
        local chunk = assert( loadfile( localPath .. ".lua" ) ); setfenv( chunk, env ); local result = chunk();
        -- Эти тесты оставлены для исторического primitive-adapter. Новый default тестируется отдельно.
        if localPath == "laning/config" then result.execution_mode = options.joint_options and "joint_options" or "legacy_fixture" end;
        return result;
    end;
    local chunk = assert( loadfile( "profiles/lane_probe/mode_laning_nevermore.lua" ) ); setfenv( chunk, env ); chunk();
    s.env = env;
    function s:tick( dt ) self.time = self.time + ( dt or 0 ); self.env.Think() end;
    return s;
end
test( "one attack with once=true and no windup cancellation", function()
    local s = scenario(); s.enemy_creeps = { s.unit() };
    assert( s.env.GetDesire() > 0 ); s:tick(); s:tick( 0.2 ); s:tick( 0.2 );
    eq( #s.attacks, 1 ); eq( s.attacks[1][2], true ); eq( #s.moves, 0 );
end );
test( "self is counted exactly once when absent from ally list", function()
    local s = scenario(); s.enemies = { s.unit( { hp = 500 } ), s.unit( { hp = 500 } ) };
    eq( s.env.GetDesire(), 0 ); s:tick(); eq( #s.attacks, 0 );
end );
test( "self is not double counted when present", function()
    local s = scenario(); s.allies = { s.bot }; s.enemies = { s.unit(), s.unit() };
    eq( s.env.GetDesire(), 0 );
end );
test( "fresh HP at Think invalidates cached last-hit intent", function()
    local s = scenario(); local u = s.unit(); s.enemy_creeps = { u };
    s.env.GetDesire(); u.hp = 250; s:tick(); eq( #s.attacks, 0 );
end );
test( "visibility is revalidated immediately before API submission", function()
    local s = scenario(); s.enemy_creeps = { s.unit( { hide_after_hp = true } ) };
    s:tick(); eq( #s.attacks, 0 ); assert( s.logs[#s.logs]:find( "rejected_stale_target", 1, true ) );
end );
test( "casting and retreat are never overwritten", function()
    local s = scenario(); s.enemy_creeps = { s.unit() }; s.bot.casting = true; s.anchor = 1000;
    s:tick(); eq( #s.attacks, 0 ); eq( #s.moves, 0 );
    s.bot.casting = false; s.retreating = true; s:tick( 1 ); eq( #s.attacks, 0 ); eq( #s.moves, 0 );
end );
test( "visible tower range prevents a dive", function()
    local s = scenario(); s.towers = { s.unit( { location = 300, range = 700 } ) };
    s.enemy_creeps = { s.unit() }; eq( s.env.GetDesire(), 0 ); s:tick(); eq( #s.attacks, 0 );
end );
test( "stats log actual counter increments, not successful attacks", function()
    local s = scenario(); s:tick(); s.last_hits = 1; s.denies = 1; s:tick( 1 );
    local line = s.logs[#s.logs];
    assert( line:find( '"last_hits_delta":1', 1, true ) );
    assert( line:find( '"denies_delta":1', 1, true ) );
    assert( line:find( '"outcome_attribution":"interval_only"', 1, true ) );
end );
test( "new mode applies only to SF", function()
    local s = scenario(); s.bot.name = "npc_dota_hero_lina"; eq( s.env.GetDesire(), 0 ); s:tick(); eq( #s.moves, 0 );
end );
test( "move goes to anchor, not a distant enemy", function()
    local s = scenario(); s.anchor = 200; s.enemies = { s.unit( { location = 900, hp = 500 } ) };
    s:tick(); eq( #s.attacks, 0 ); eq( s.moves[1], 200 );
end );
test( "lane assignment uses team slots for non-contiguous player IDs", function()
    local ids = { 5, 8, 9 }; local env = setmetatable( {
        GetTeam = function() return 3 end, GetTeamPlayers = function() return ids end,
        IsPlayerBot = function( id ) return id ~= 5 end,
        GetSelectedHeroName = function( id ) return id == 8 and "npc_dota_hero_nevermore" or "npc_dota_hero_lion" end,
        LANE_TOP = 1, LANE_MID = 2, LANE_BOT = 3,
    }, { __index = _G } );
    local chunk = assert( loadfile( "hero_selection.lua" ) ); setfenv( chunk, env ); chunk();
    local lanes = env.UpdateLaneAssignments(); eq( lanes[2], 2 ); eq( lanes[8], nil ); eq( #lanes, 3 );
    eq( env.GetBotNames()[1], "MIDBOT v0.3.13-resources-delivery" );
end );
test( "new default issues no orders before joint backend registration", function()
    local s = scenario( { joint_options = true } ); s.enemy_creeps = { s.unit() };
    eq( s.env.GetDesire(), 0 ); eq( s:tick(), nil ); eq( #s.attacks, 0 ); eq( #s.moves, 0 );
end );
print( "ADAPTER PASSED " .. total );
