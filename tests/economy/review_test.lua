-- Cases found by self-review of PR41. Shared fixture, real production callbacks.
local scenario = ECONOMY_REVIEW_SCENARIO;
assert( type( scenario ) == "function" );
local passed = 0;
local function eq( a, b ) assert( a == b, tostring( a ) .. " ~= " .. tostring( b ) ) end;
local function test( name, fn ) fn(); passed = passed + 1; print( "PASS ECONOMY_REVIEW " .. name ) end;
local function pickup( s )
    s.env.BOT_ACTION_TYPE_PICK_UP_RUNE = 8; s.env.BOT_MODE_EVASIVE_MANEUVERS = 19;
    s.bot.IsRooted = function() return s.rooted or false end;
    s.bot.Action_PickUpRune = function( _, rune ) s.runes[#s.runes + 1] = rune; s.action = 8 end;
    s.bot.Action_ClearActions = function( _, stop ) eq( stop, true ); s.cancelled = ( s.cancelled or 0 ) + 1; s.action = 0 end;
end;
test( "enemy outside bot radius but near rune blocks pickup", function()
    local s = scenario(); pickup( s ); local enemy = s:unit();
    enemy.GetLocation = function() return { x = 800, y = 0 } end; -- T023: до руны (400,0) = 400 <= rune_enemy_radius 500
    s.bot.GetNearbyHeroes = function( _, radius ) return radius >= 800 and { enemy } or {} end;
    eq( s.rune_policy.GetDesire( s.bot ), 0 ); s.mode = 7; s.rune_policy.Think( s.bot ); eq( #s.runes, 0 );
end );
test( "wave arriving during pickup cancels the owned rune order", function()
    local s = scenario(); pickup( s ); s.mode = 7; s.rune_policy.Think( s.bot ); eq( #s.runes, 1 );
    s.creeps = { s:unit() }; s.time = 101; s.rune_policy.Think( s.bot ); eq( s.cancelled, 1 ); eq( #s.runes, 1 );
end );
test( "completed purchase missed between polls does not block all future supply", function()
    local s = scenario(); s.enemies = { s:unit() }; s.mana_policy.TryPurchase( s.bot );
    -- Engine accepted mango, delivered and consumed it before next observation.
    s.time = 190; eq( s.mana_policy.TryPurchase( s.bot ), true ); eq( #s.calls, 2 );
end );
test( "far stale hero target does not permanently suppress a safe nearby rune", function()
    local s = scenario(); pickup( s ); s.target = s:unit();
    s.target.GetLocation = function() return { x = 3000, y = 0 } end;
    eq( s.rune_policy.GetDesire( s.bot ), .85 );
end );
test( "salve skipping obeys the mana experiment time window", function()
    local s = scenario(); s.time = 601; eq( s.mana_policy.SkipFlask( s.bot ), false );
end );
test( "unknown result followed by delivery still consumes the purchase budget", function()
    local s = scenario(); s.result = nil;
    for i = 0, 3 do
        s.time = 100 + i * 100; s.mana_policy.TryPurchase( s.bot );
        s.items[0] = s:item( "item_clarity", 1 ); s.time = s.time + 5;
        s.mana_policy.TryPurchase( s.bot ); s.items[0] = nil;
    end;
    eq( #s.calls, 3 );
end );
test( "OnEnd cancels only the tracked pickup with no queued action", function()
    local s = scenario(); pickup( s ); s:load( "profiles/lane_economy/mode_rune_nevermore.lua" );
    s.mode = 7; s.env.Think(); eq( #s.runes, 1 ); s.mode = 1; s.env.OnEnd(); eq( s.cancelled, 1 );
end );
test( "new native attack retires ownership and is never cleared", function()
    local s = scenario(); pickup( s ); s.mode = 7; s.rune_policy.Think( s.bot ); s.action = 4;
    s.rune_policy.Leave( s.bot ); eq( s.cancelled, nil ); eq( s.action, 4 );
    s.action = 8; s.rune_policy.Leave( s.bot ); eq( s.cancelled, nil );
end );
test( "cast, channel or queued actions are preserved on exit", function()
    for _, kind in ipairs( { "cast", "channel", "queued", "queue_unknown" } ) do
        local s = scenario(); pickup( s ); s.mode = 7; s.rune_policy.Think( s.bot );
        if kind == "cast" then s.casting = true
        elseif kind == "channel" then s.bot.IsChanneling = function() return true end
        elseif kind == "queued" then s.bot.NumQueuedActions = function() return 1 end
        else s.bot.NumQueuedActions = nil end;
        s.rune_policy.Leave( s.bot ); eq( s.cancelled, nil );
    end;
end );
test( "no owned pickup means no clearing even if current action has rune type", function()
    local s = scenario(); pickup( s ); s.action = 8;
    s.rune_policy.Leave( s.bot ); eq( s.cancelled, nil ); eq( s.rune_policy.GetDesire( s.bot ), 0 );
end );
test( "missing cancellation enum, root and evasion suppress new rune orders", function()
    local s = scenario(); pickup( s ); s.env.BOT_ACTION_TYPE_PICK_UP_RUNE = nil; eq( s.rune_policy.GetDesire( s.bot ), 0 );
    local t = scenario(); pickup( t ); t.rooted = true; eq( t.rune_policy.GetDesire( t.bot ), 0 );
    t.rooted = false; t.mode = 19; eq( t.rune_policy.GetDesire( t.bot ), 0 );
end );
test( "pickup has a timeout and reentry cannot bypass retry cooldown", function()
    local s = scenario(); pickup( s ); s.mode = 7; s.rune_policy.Think( s.bot ); eq( #s.runes, 1 );
    s.time = 103; s.rune_policy.Think( s.bot ); eq( #s.runes, 1 ); -- no periodic order restart
    s.time = 104; eq( s.rune_policy.GetDesire( s.bot ), 0 ); s.rune_policy.Leave( s.bot ); eq( s.cancelled, 1 );
    s.time = 105; eq( s.rune_policy.GetDesire( s.bot ), 0 ); s.time = 114; assert( s.rune_policy.GetDesire( s.bot ) > 0 );
end );
test( "unseen stale target is not read for hidden location", function()
    local s = scenario(); pickup( s ); s.target = s:unit(); s.target.CanBeSeen = function() return false end;
    s.target.GetLocation = function() error( "hidden location access" ) end;
    eq( s.rune_policy.GetDesire( s.bot ), .85 );
end );
test( "unobserved nonnumeric purchase result remains unknown", function()
    for _, value in ipairs( { false, "unknown", {} } ) do
        local s = scenario(); s.result = value; s.mana_policy.TryPurchase( s.bot ); s.time = 300;
        eq( s.mana_policy.TryPurchase( s.bot ), false ); eq( #s.calls, 1 );
    end;
end );
test( "unknown mango outcomes count toward the gold cap too", function()
    local s = scenario(); s.result = nil; s.enemies = { s:unit() };
    for i = 0, 3 do
        s.time = 100 + i * 100; s.mana_policy.TryPurchase( s.bot );
        s.items[0] = s:item( "item_enchanted_mango", 1 ); s.time = s.time + 5;
        s.mana_policy.TryPurchase( s.bot ); s.items[0] = nil;
    end;
    eq( #s.calls, 2 );
end );
test( "failed attempts release budget reservation rather than exhausting supplies", function()
    local s = scenario(); s.result = 4;
    for i = 0, 4 do s.time = 100 + i * 5; s.mana_policy.TryPurchase( s.bot ) end;
    s.result = 0; s.time = 125; eq( s.mana_policy.TryPurchase( s.bot ), true ); eq( #s.calls, 6 );
end );
test( "unexpected action type retires pickup without restarting or clearing movement", function()
    local s = scenario(); pickup( s ); s.mode = 7; s.rune_policy.Think( s.bot );
    s.action = 2; s.time = 101; eq( s.rune_policy.GetDesire( s.bot ), 0 ); s.rune_policy.Think( s.bot );
    eq( s.cancelled, nil ); eq( s.action, 2 ); eq( #s.runes, 1 );
    s.time = 102; eq( s.rune_policy.GetDesire( s.bot ), 0 );
end );
print( "ECONOMY_REVIEW PASSED " .. passed .. " cases" );
