-- Реальная геометрия helper с подставным Bot API; это не Dota navmesh.
local count = 0;
local function eq( a, b ) assert( a == b, tostring( a ) .. " ~= " .. tostring( b ) ) end;
local function test( name, fn ) fn(); count = count + 1; print( "PASS MOVEMENT " .. name ) end;
local function scenario()
    local s = { hero = { x = 0, y = 0 }, towers = {}, calls = 0 };
    local env = setmetatable( {}, { __index = _G } ); local cache = {};
    env.GetScriptDirectory = function() return "bots" end;
    env.Vector = function( x, y, z ) return { x = x, y = y, z = z } end;
    env.IsLocationPassable = function( p ) s.calls = s.calls + 1; return not s.block or not s.block( p ) end;
    env.require = function( path )
        local p = path:match( "laning/.*" );
        if not cache[p] then local chunk = assert( loadfile( p .. ".lua" ) ); setfenv( chunk, env ); cache[p] = chunk() end;
        return cache[p];
    end;
    return s, env.require( "bots/laning/runtime/movement" ), { move_step = 250 }, env;
end
test( "a passable endpoint beyond an impassable segment is rejected", function()
    local s, m, cfg = scenario(); s.block = function( p ) return p.x >= 90 and p.x <= 110 end;
    local ok, reason = m.Check( s, { x = 250, y = 0 }, cfg ); eq( ok, false ); eq( reason, "move_path_impassable" );
end );
test( "a segment crossing tower range is rejected even with a safe endpoint", function()
    local s, m, cfg = scenario();
    s.towers = { { enemy = true, id = "t", x = 125, y = 0, range_verified = true, attack_range = 30, range_margin = 0 } };
    local ok, reason = m.Check( s, { x = 250, y = 0 }, cfg ); eq( ok, false ); eq( reason, "move_enters_tower_range" );
end );
test( "unknown tower profile cannot be treated as safe", function()
    local s, m, cfg = scenario(); s.towers = { { enemy = true, x = 900, y = 0, range_verified = false } };
    local ok, reason = m.Check( s, { x = 250, y = 0 }, cfg ); eq( ok, false ); eq( reason, "move_tower_range_unknown" );
end );
test( "invalid API output is not interpreted as passable", function()
    local s, m, cfg, env = scenario(); env.IsLocationPassable = function() return 1 end;
    local ok, reason = m.Check( s, { x = 250, y = 0 }, cfg ); eq( ok, false ); eq( reason, "move_passability_failed" );
end );
test( "NaN and infinity never reach the vector or passability API", function()
    local s, m, cfg = scenario();
    local ok, reason = m.Check( s, { x = 0/0, y = 0 }, cfg ); eq( ok, false ); eq( reason, "move_position_invalid" );
    local point, why = m.Plan( s, { x = math.huge, y = 0 }, cfg ); eq( point, nil ); eq( why, "move_position_invalid" ); eq( s.calls, 0 );
end );
test( "missing vector API produces a controlled rejection", function()
    local s, m, cfg, env = scenario(); env.Vector = false;
    local ok, reason = m.Check( s, { x = 250, y = 0 }, cfg ); eq( ok, false ); eq( reason, "move_vector_unavailable" );
end );
test( "a shorter step can be selected when long alternatives are blocked", function()
    local s, m, cfg = scenario(); s.block = function( p ) return p.x*p.x + p.y*p.y > 130*130 end;
    local p, reason, detail = m.Plan( s, { x = 1000, y = 0 }, cfg ); assert( p ); eq( reason, nil );
    assert( p.x > 0 and p.x*p.x+p.y*p.y <= 130*130 ); eq( detail.alternative, true );
end );
test( "candidate budget is finite when every point is blocked", function()
    local s, m, cfg = scenario(); s.block = function() return true end;
    local p, reason, detail = m.Plan( s, { x = 1000, y = 0 }, cfg ); eq( p, nil ); eq( reason, "move_point_impassable" );
    assert( detail.no_safe_step ); assert( detail.attempts <= 15 ); assert( s.calls <= 75 );
end );
test( "unobstructed movement keeps the original direct bounded step", function()
    local s, m, cfg = scenario(); local p, _, detail = m.Plan( s, { x = 1000, y = 0 }, cfg );
    eq( p.x, 250 ); eq( p.y, 0 ); eq( detail.alternative, false ); eq( detail.attempts, 1 );
end );
test( "an alternative must still approach the actual destination", function()
    local s, m, cfg = scenario(); s.block = function( p ) return p.x > 20 and math.abs( p.y ) < 10 end;
    local p = m.Plan( s, { x = 100, y = 0 }, cfg ); assert( p );
    assert( ( p.x-100 )^2+p.y^2 < 100^2 ); assert( p.x^2+p.y^2 <= 250^2+1 );
end );
test( "unknown tower data and invalid step limits fail closed", function()
    local s, m, cfg = scenario(); s.towers = nil;
    local ok, reason = m.Check( s, { x = 250, y = 0 }, cfg ); eq( ok, false ); eq( reason, "move_tower_data_unavailable" );
    cfg.move_step = -1; local p, why = m.Plan( s, { x = 1000, y = 0 }, cfg ); eq( p, nil ); eq( why, "move_step_invalid" );
end );
test( "no movement is manufactured when already at destination", function()
    local s, m, cfg = scenario(); local p, reason = m.Plan( s, { x = 0, y = 0 }, cfg );
    eq( p, nil ); eq( reason, "move_already_at_destination" ); eq( s.calls, 0 );
end );
print( "MOVEMENT PASSED " .. count );
