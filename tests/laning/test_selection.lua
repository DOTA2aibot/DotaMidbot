-- Selection profile tests; do not simulate lobby slot creation or engine auto-picks.
local passed = 0;
local function eq( a, b ) assert( a == b, tostring( a ) .. " ~= " .. tostring( b ) ) end;
local function test( name, fn ) fn(); passed = passed + 1; print( "PASS SELECTION " .. name ) end;
local function scenario( mode, disabled )
    local s = { mode = mode, ids = { 5, 8, 9, 11, 15 }, humans = {}, selected = {}, picks = {}, logs = {} };
    s.profile = { name = "valve_play", controller = "valve_native", runtime_enabled = false };
    local env = setmetatable( {
        GetScriptDirectory = function() return "bots" end,
        require = function( path ) assert( path == "bots/laning/profile" ); return s.profile end,
        GetTeam = function() return 3 end,
        GetGameMode = function() return s.mode end,
        GetTeamPlayers = function() return s.ids end,
        IsPlayerBot = function( id ) return not s.humans[id] end,
        GetSelectedHeroName = function( id ) return s.selected[id] or "" end,
        SelectHero = function( id, hero ) s.picks[#s.picks + 1] = { id = id, hero = hero }; s.selected[id] = hero end,
        print = function( line ) s.logs[#s.logs + 1] = line end,
        LANE_TOP = 1, LANE_MID = 2, LANE_BOT = 3,
    }, { __index = _G } );
    local f = assert( io.open( "hero_selection.lua", "r" ) ); local source = f:read( "*a" ); f:close();
    -- Exercise the documented manual switch without editing a working tree.
    if disabled then source = source:gsub( "local SOLO_1V1 = true;", "local SOLO_1V1 = false;" ) end;
    local chunk = assert( loadstring( source, "hero_selection_test" ) ); setfenv( chunk, env ); chunk();
    s.env = env; return s;
end
test( "native 1v1 picks only one SF and preserves stable version name", function()
    local s = scenario( 21 ); s.env.Think(); eq( #s.picks, 1 ); eq( s.picks[1].hero, "npc_dota_hero_nevermore" );
    eq( #s.env.GetBotNames(), 1 ); eq( s.env.GetBotNames()[1], "MIDBOT v0.3.12-ward-recovery" );
end );
test( "ordinary all pick keeps full team and names", function()
    local s = scenario( 1 ); s.env.Think(); eq( #s.picks, 5 ); eq( #s.env.GetBotNames(), 5 );
    eq( s.picks[1].hero, "npc_dota_hero_nevermore" ); eq( s.picks[5].hero, "npc_dota_hero_crystal_maiden" );
end );
test( "manual solo switch off restores team selection in native 1v1", function()
    local s = scenario( 21, true ); s.env.Think(); eq( #s.picks, 5 ); eq( #s.env.GetBotNames(), 5 );
end );
test( "team selection skips humans with non-contiguous player IDs", function()
    local s = scenario( 1 ); s.humans[5] = true; s.selected[5] = "npc_dota_hero_furion"; s.env.Think();
    eq( #s.picks, 4 ); eq( s.picks[1].id, 8 ); eq( s.picks[1].hero, "npc_dota_hero_nevermore" );
    eq( s.selected[5], "npc_dota_hero_furion" );
end );
test( "human on bot side rejects solo setup without overwriting a human", function()
    local s = scenario( 21 ); s.humans[5] = true; s.env.Think(); eq( #s.picks, 0 );
    assert( s.logs[#s.logs]:find( "human_on_bot_side_no_pick", 1, true ) );
end );
test( "repeated solo callback never picks teammates or repicks an existing SF", function()
    local s = scenario( 21 ); s.env.Think(); s.ids = { 15, 11, 9, 8, 5 };
    for i = 1, 5 do s.env.Think() end;
    eq( #s.picks, 1 ); eq( s.picks[1].id, 5 );
end );
test( "existing SF is reused even when not in the first slot", function()
    local s = scenario( 21 ); s.selected[11] = "npc_dota_hero_nevermore"; s.env.Think(); eq( #s.picks, 0 );
    eq( s.env.UpdateLaneAssignments()[4], 2 );
end );
test( "existing other hero is not overwritten or joined by another bot", function()
    local s = scenario( 21 ); s.selected[8] = "npc_dota_hero_lion"; s.env.Think(); eq( #s.picks, 0 );
    assert( s.logs[#s.logs]:find( "unexpected_solo_hero_no_overwrite", 1, true ) );
end );
test( "extra selected bots are detected without pretending that names remove slots", function()
    local s = scenario( 21 ); s.selected[5], s.selected[8] = "npc_dota_hero_nevermore", "npc_dota_hero_lion";
    s.env.Think(); eq( #s.picks, 0 ); eq( #s.ids, 5 );
    assert( s.logs[#s.logs]:find( "extra_bot_heroes_no_pick", 1, true ) );
end );
test( "unknown game mode does not accidentally populate five heroes", function()
    for _, mode in ipairs( { 0, -1 } ) do
        local s = scenario( mode ); s.env.Think(); eq( #s.picks, 0 );
        assert( s.logs[#s.logs]:find( "game_mode_unknown_no_pick", 1, true ) );
    end;
end );
test( "unreadable selected names cannot create another solo hero", function()
    local s = scenario( 21 ); s.env.GetSelectedHeroName = function() error( "API unavailable" ) end;
    s.env.Think(); eq( #s.picks, 0 );
    assert( s.logs[#s.logs]:find( "selected_names_unknown_no_pick", 1, true ) );
end );
test( "selection log separates slot count from selected hero count without spam", function()
    local s = scenario( 21 ); s.env.Think();
    local line = s.logs[#s.logs]; assert( line:find( "bot_slots=5 selected_bot_heroes=1", 1, true ) );
    assert( line:find( "profile=solo_1v1", 1, true ) );
    local count = #s.logs; s.env.Think(); eq( #s.logs, count ); eq( #s.ids, 5 );
end );
test( "play controller attribution is visible during selection", function()
    local s = scenario( 21 ); s.env.Think();
    assert( s.logs[1]:find( "controller_profile=valve_play controller=valve_native", 1, true ) );
end );
test( "probe controller is reported separately from native play", function()
    local s = scenario( 21 ); s.profile.name, s.profile.controller = "lane_probe", "midbot_runtime"; s.env.Think();
    assert( s.logs[1]:find( "controller_profile=lane_probe controller=midbot_runtime", 1, true ) );
end );
print( "SELECTION PASSED " .. passed );
