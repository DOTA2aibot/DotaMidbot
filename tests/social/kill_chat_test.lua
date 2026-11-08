local passed = 0;
local function eq( a, b ) assert( a == b, tostring( a ) .. " ~= " .. tostring( b ) ) end;
local function test( name, fn ) fn(); passed = passed + 1; print( "PASS KILL_CHAT " .. name ) end;
local function scenario()
    local s = { game = 100, real = 1000, kills = 0, sent = {}, logs = {}, attempts = 0, forbidden = 0, casts = 0, captures = 0 };
    local env = setmetatable( {}, { __index = _G } ); env._G = env; local cache = {};
    env.GetScriptDirectory = function() return "bots" end;
    env.DotaTime = function() return s.game end; env.GameTime = env.DotaTime;
    env.RealTime = function() return s.real end;
    env.GetHeroKills = function( id ) eq( id, 1 ); s.reads = ( s.reads or 0 ) + 1; return s.kills end;
    env.IsPlayerBot = function( id ) return id == 1 end;
    env.print = function( message ) if s.logger_error then error( "sink failed" ) end; s.logs[#s.logs + 1] = message end;
    local cfg = { enabled = true, version = "kill-chat-1", message = "??", poll_interval_s = .25,
        chat_interval_s = 3, freshness_gap_s = 2, event_ttl_s = 15, max_pending = 5 };
    local profile = { observer_enabled = true, runtime_enabled = false };
    local observation = { next_sample = -math.huge, next_error = -math.huge, sequence = 0 };
    env.require = function( path )
        local p = assert( path:match( "laning/.*" ) );
        if p == "laning/social/kill_chat_config" then return cfg end;
        if p == "laning/profile" then return profile end;
        if p == "laning/runtime/guard" then return { AbilityGate = function() return false end } end;
        if p == "laning/observer/config" then return { interval_s = 1, shadow_enabled = false } end;
        if p == "laning/hybrid/shadow" or p == "laning/hybrid/wards" then return {} end;
        if p == "laning/observer/core" then return {
            State = function() return observation end,
            PollCasts = function() end, PollAttacks = function() end,
            Capture = function() s.captures = s.captures + 1; return { hero = {} } end,
            Emit = function() observation.sequence = observation.sequence + 1 end,
        } end;
        if not cache[p] then local f = assert( loadfile( p .. ".lua" ) ); setfenv( f, env ); cache[p] = f() end;
        return cache[p];
    end;
    local bot = {}; s.bot, s.env, s.cfg, s.profile = bot, env, cfg, profile;
    function bot:GetUnitName() return "npc_dota_hero_nevermore" end;
    function bot:IsHero() return true end; function bot:IsIllusion() return false end;
    function bot:GetPlayerID() return 1 end; function bot:IsAlive() return s.alive ~= false end;
    function bot:ActionImmediate_Chat( message, all )
        s.attempts = s.attempts + 1; eq( message, "??" ); eq( all, true );
        s.sent[#s.sent + 1] = { message = message, all = all, real = s.real };
        if s.chat_error then error( "unknown after submission" ) end;
    end;
    function bot:GetAbilityPoints() return 0 end;
    function bot:GetAbilityByName( name ) return { GetName = function() return name end } end;
    function bot:IsUsingAbility() return false end; function bot:IsChanneling() return false end;
    function bot:IsSilenced() return false end;
    function bot:Action_UseAbility() s.casts = s.casts + 1 end;
    for _, name in ipairs( { "Action_MoveToLocation", "Action_AttackUnit", "Action_ClearActions", "ActionImmediate_Courier" } ) do
        bot[name] = function() s.forbidden = s.forbidden + 1; error( "forbidden " .. name ) end;
    end;
    env.DebugPause = function() s.forbidden = s.forbidden + 1; error( "pause forbidden" ) end;
    env.PauseGame = env.DebugPause;
    env.GetBot = function() return bot end;
    s.module = env.require( "bots/laning/social/kill_chat" );
    function s:tick( dt ) self.game = self.game + ( dt or .25 ); self.real = self.real + ( dt or .25 ); self.module.Tick( self.bot ) end;
    function s:run( seconds ) for i = 1, math.floor( seconds / .25 ) do self:tick() end end;
    function s:entry() return self.env.require( "bots/laning/observer/entry" ) end;
    function s:ability()
        local f = assert( loadfile( ABILITY_TEST_SOURCE or "ability_item_usage_nevermore.lua" ) ); setfenv( f, self.env ); f();
        self.env.ConsiderRequiem = function() return .5 end;
    end;
    return s;
end;
test( "fresh kill sends exactly two question marks to all chat", function()
    local s = scenario(); s:tick(); s.kills = 1; s:tick(); eq( s.attempts, 1 ); eq( s.forbidden, 0 );
end );
test( "repeated callbacks do not resend the same kill", function()
    local s = scenario(); s:tick(); s.kills = 1; s:tick(); s:run( 10 ); eq( s.attempts, 1 );
end );
test( "loading with existing kills does not replay history", function()
    local s = scenario(); s.kills = 7; s:tick(); s:run( 1 ); eq( s.attempts, 0 );
    s.kills = 8; s:tick(); eq( s.attempts, 1 );
end );
test( "illusion with same player ID neither chats nor changes real hero cursor", function()
    local s = scenario(); s:tick(); s.kills = 1;
    local illusion = setmetatable( { IsIllusion = function() return true end }, { __index = s.bot } );
    s.module.Tick( illusion ); eq( s.attempts, 0 ); s:tick(); eq( s.attempts, 1 );
end );
test( "unknown illusion state, other hero and human player cannot chat", function()
    for _, variant in ipairs( { "unknown", "other", "human" } ) do
        local s = scenario();
        if variant == "unknown" then s.bot.IsIllusion = nil
        elseif variant == "other" then s.bot.GetUnitName = function() return "npc_dota_hero_lina" end
        else s.env.IsPlayerBot = function() return false end end;
        s:tick(); s.kills = 1; s:tick(); eq( s.attempts, 0 );
    end;
end );
test( "LH or assist-like changes without kill credit produce no message", function()
    local s = scenario(); s:tick(); s.bot.GetLastHits = function() return 100 end; s:run( 1 ); eq( s.attempts, 0 );
end );
test( "multi-kill is queued and attempts are spaced in real time", function()
    local s = scenario(); s:tick(); s.kills = 3; s:tick(); s:run( 7 ); eq( s.attempts, 3 );
    assert( s.sent[2].real - s.sent[1].real >= 3 ); assert( s.sent[3].real - s.sent[2].real >= 3 );
end );
test( "large counter jump is bounded rather than an unbounded chat loop", function()
    local s = scenario(); s:tick(); s.kills = 100000; s:tick(); s:run( 14 ); eq( s.attempts, 5 );
end );
test( "queue overflow stays bounded while kills keep arriving", function()
    local s = scenario(); s:tick();
    for i = 1, 20 do s.kills = s.kills + 5; s:tick() end;
    s:run( 14 ); assert( s.attempts <= 7 );
end );
test( "chat exception after submission is not retried", function()
    local s = scenario(); s.chat_error = true; s:tick(); s.kills = 1; s:tick(); s:run( 5 ); eq( s.attempts, 1 );
    s.chat_error = false; s.kills = 2; s:tick(); eq( s.attempts, 2 );
end );
test( "logger exception does not change delivery attempts", function()
    local s = scenario(); s.logger_error = true; s:tick(); s.kills = 1; s:tick(); s:run( 4 ); eq( s.attempts, 1 );
end );
test( "dead hero and respawn do not replay a death-time kill", function()
    local s = scenario(); s:tick(); s.alive = false; s.kills = 1; s:tick();
    s.alive = true; s:tick(); eq( s.attempts, 0 ); s.kills = 2; s:tick(); eq( s.attempts, 1 );
end );
test( "long callback gap drops stale kills", function()
    local s = scenario(); s:tick(); s.kills = 1; s:tick( 30 ); eq( s.attempts, 0 );
    s.kills = 2; s:tick(); eq( s.attempts, 1 );
end );
test( "pregame kills are ignored without becoming a first-frame message", function()
    local s = scenario(); s.game = -1; s:tick(); s.kills = 1; s:tick();
    s.game = 0; s:tick(); eq( s.attempts, 0 );
end );
test( "counter reset and clock rewind reset baseline without replay", function()
    local s = scenario(); s.kills = 4; s:tick(); s.kills = 0; s:tick(); eq( s.attempts, 0 );
    s.kills = 1; s.game = -80; s:tick(); eq( s.attempts, 0 );
    s.game = 100; s:tick(); s.kills = 2; s:tick(); eq( s.attempts, 1 );
end );
test( "missing clocks, kill API and invalid counters fail closed", function()
    for _, variant in ipairs( { "clock", "kills", "fraction", "negative", "nan" } ) do
        local s = scenario(); s:tick();
        if variant == "clock" then s.env.RealTime = nil
        elseif variant == "kills" then s.env.GetHeroKills = nil
        elseif variant == "fraction" then s.kills = 1.5
        elseif variant == "negative" then s.kills = -1
        else s.kills = 0/0 end;
        s:tick(); eq( s.attempts, 0 );
    end;
end );
test( "polling is bounded and first pause-time queue expires by real time", function()
    local s = scenario(); s:tick();
    for i = 1, 100 do s.game = s.game + .001; s.real = s.real + .001; s.module.Tick( s.bot ) end;
    eq( s.reads, 1 );
    s:tick(); s.kills = 2; s:tick(); eq( s.attempts, 1 );
    s.real = s.real + 20; s.module.Tick( s.bot ); eq( s.attempts, 1 );
end );
test( "disabling drops pending messages and reenable initializes a new baseline", function()
    local s = scenario(); s:tick(); s.kills = 3; s:tick(); eq( s.attempts, 1 );
    s.cfg.enabled = false; s:tick(); s.kills = 8; s.cfg.enabled = true; s:tick(); s:run( 4 ); eq( s.attempts, 1 );
end );
test( "actual entry dispatch works even when observer is disabled", function()
    local s = scenario(); s.profile.observer_enabled = false; local entry = s:entry(); entry.Tick( s.bot );
    s.game = s.game + .25; s.real = s.real + .25; s.kills = 1; entry.Tick( s.bot );
    eq( s.attempts, 1 ); eq( s.captures, 0 ); eq( s.forbidden, 0 );
end );
test( "diagnostic runtime profile never activates kill chat", function()
    local s = scenario(); s.profile.runtime_enabled = true; local entry = s:entry(); entry.Tick( s.bot );
    s.game = s.game + .25; s.real = s.real + .25; s.kills = 1; entry.Tick( s.bot ); eq( s.attempts, 0 );
end );
test( "helper failure preserves actual observer and ability callbacks", function()
    local s = scenario(); s.module.Tick = function() error( "helper failed" ) end; s:ability();
    s.env.AbilityUsageThink(); eq( s.captures, 1 ); eq( s.casts, 1 );
    assert( not table.concat( s.logs, "\n" ):find( "[MIDBOT ability ERROR]", 1, true ) );
end );
test( "missing helper module preserves actual ability callback", function()
    local s = scenario(); local previous = s.env.require;
    s.env.require = function( path ) if path:match( "/social/kill_chat$" ) then error( "not installed" ) end; return previous( path ) end;
    s:ability(); s.env.AbilityUsageThink(); eq( s.casts, 1 ); eq( s.attempts, 0 ); eq( s.forbidden, 0 );
end );
test( "actual ability callback sends once and keeps its normal spell on chat failure", function()
    local s = scenario(); s:ability(); s.env.AbilityUsageThink(); s.chat_error = true;
    s.game = s.game + .25; s.real = s.real + .25; s.kills = 1; s.env.AbilityUsageThink();
    eq( s.attempts, 1 ); eq( s.casts, 2 ); eq( s.forbidden, 0 );
end );
print( "KILL_CHAT PASSED " .. passed .. " cases (mock API; not a Dota match)" );
