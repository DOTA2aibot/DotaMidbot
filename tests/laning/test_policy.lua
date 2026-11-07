local Policy = dofile( "laning/policy.lua" );
local C = dofile( "laning/config.lua" );
local tests = 0;
local function test( name, fn ) fn(); tests = tests + 1; print( "PASS " .. name ) end;
local function eq( a, b ) assert( a == b, tostring( a ) .. " ~= " .. tostring( b ) ) end;
local function state()
    return { time = 120, alive = true, hp_fraction = 1, enemy_count = 1, ally_count = 1,
        enemy_creeps = {}, allied_creeps = {}, enemy_heroes = {}, anchor_safe = true, anchor_distance = 0 };
end
local function target( hp )
    return { id = "a", visible = true, alive = true, in_range = true, hp = hp or 40,
        max_hp = 300, regen = 0, damage = 50, eta_s = 0.5, distance = 300 };
end
test( "last hit has priority over deny and harass", function()
    local s = state(); s.enemy_creeps = { target() }; s.allied_creeps = { target() }; s.enemy_heroes = { target( 500 ) };
    eq( Policy.Decide( s, C ).reason, "last_hit" );
end );
test( "deny has priority over harass", function()
    local s = state(); s.allied_creeps = { target() }; s.enemy_heroes = { target( 500 ) };
    eq( Policy.Decide( s, C ).reason, "deny" );
end );
test( "only one-hit denies below allowed HP fraction", function()
    local s = state(); local t = target( 40 ); t.max_hp = 60; s.allied_creeps = { t };
    assert( Policy.Decide( s, C ).reason ~= "deny" );
end );
test( "regen during windup and projectile prevents false last hit", function()
    local s = state(); local t = target( 45 ); t.regen = 10; t.eta_s = 1; s.enemy_creeps = { t };
    eq( Policy.Decide( s, C ).reason, "reserve_for_creep" );
end );
test( "damage safety margin is explicit", function()
    local s = state(); s.enemy_creeps = { target( 49 ) }; eq( Policy.Decide( s, C ).kind, "wait" );
    local config = {}; for k, v in pairs( C ) do config[k] = v end; config.damage_fraction = 1;
    eq( Policy.Decide( s, config ).reason, "last_hit" );
end );
test( "visible range required, no chase", function()
    for _, field in ipairs( { "visible", "alive", "in_range" } ) do
        local s = state(); local t = target(); t[field] = false; s.enemy_creeps = { t };
        eq( Policy.Decide( s, C ).kind, "wait" );
    end
end );
test( "invulnerable and attack immune targets excluded", function()
    for _, field in ipairs( { "invulnerable", "attack_immune", "tower_danger" } ) do
        local s = state(); local t = target(); t[field] = true; s.enemy_creeps = { t };
        eq( Policy.Decide( s, C ).kind, "wait" );
    end
end );
test( "harass only with sufficient HP and no creep reserve", function()
    local s = state(); s.enemy_heroes = { target( 500 ) }; eq( Policy.Decide( s, C ).reason, "harass" );
    s.hp_fraction = 0.64; eq( Policy.Decide( s, C ).kind, "wait" );
    s.hp_fraction = 1; s.enemy_creeps = { target( 70 ) }; eq( Policy.Decide( s, C ).reason, "reserve_for_creep" );
end );
test( "safety yields even when a last hit is available", function()
    local cases = { { "hp_fraction", 0.34, "low_hp" }, { "alive", false, "dead" },
        { "casting", true, "ability_in_progress" }, { "disabled", true, "disabled" },
        { "retreating", true, "retreat_mode" }, { "tower_danger", true, "tower_danger" },
        { "enemy_count", 2, "outnumbered_visible" }, { "time", -1, "outside_lane_window" },
        { "time", 601, "outside_lane_window" } };
    for _, c in ipairs( cases ) do
        local s = state(); s.enemy_creeps = { target() }; s[c[1]] = c[2];
        eq( Policy.Decide( s, C ).kind, "yield" ); eq( Policy.Decide( s, C ).reason, c[3] );
    end
end );
test( "attack cycle is not interrupted by another order", function()
    local s = state(); s.attack_busy = true; s.enemy_creeps = { target() }; s.anchor_distance = 1000;
    eq( Policy.Decide( s, C ).reason, "attack_cycle" );
end );
test( "no pushing healthy creeps", function()
    local s = state(); s.enemy_creeps = { target( 250 ) }; eq( Policy.Decide( s, C ).reason, "hold_lane" );
end );
test( "move only toward safe anchor, no target chase", function()
    local s = state(); s.anchor_distance = 500; eq( Policy.Decide( s, C ).kind, "move" );
    s.anchor_safe = false; eq( Policy.Decide( s, C ).kind, "wait" );
end );
test( "earliest reachable kill, stable HP tie break", function()
    local s = state(); local a, b = target( 40 ), target( 30 ); a.eta_s = 1; b.eta_s = 0.5;
    s.enemy_creeps = { a, b }; eq( Policy.Decide( s, C ).target, b );
    a.eta_s = 0.5; eq( Policy.Decide( s, C ).target, b );
end );
test( "NaN and invalid damage do not become an attack", function()
    local s = state(); local t = target(); t.hp = 0 / 0; s.enemy_creeps = { t };
    eq( Policy.Decide( s, C ).kind, "wait" ); t.hp = 40; t.damage = 0;
    eq( Policy.Decide( s, C ).kind, "wait" );
end );
print( "POLICY PASSED " .. tests );
