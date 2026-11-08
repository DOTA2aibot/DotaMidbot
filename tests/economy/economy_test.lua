-- Real Lua callbacks with synthetic Bot API; no engine/fallback/navmesh claim.
local passed = 0;
local function eq( a, b ) assert( a == b, tostring( a ) .. " ~= " .. tostring( b ) ) end;
local function test( name, fn ) fn(); passed = passed + 1; print( "PASS ECONOMY " .. name ) end;
local function scenario( disabled )
    local s = { time = 100, mana = 50, gold = 1000, hp = 1000, mode = 1, items = {}, couriers = {},
        creeps = {}, enemies = {}, towers = {}, calls = {}, runes = {}, logs = {}, visible = true, passable = true, result = 0 };
    local env = setmetatable( {}, { __index = _G } ); env._G = env; local cache = {};
    env.GetScriptDirectory = function() return "bots" end;
    env.DotaTime = function() return s.time end; env.GameTime = env.DotaTime;
    env.BOT_MODE_NONE, env.BOT_MODE_LANING, env.BOT_MODE_ATTACK, env.BOT_MODE_RETREAT, env.BOT_MODE_RUNE = 0, 1, 2, 4, 7;
    env.BOT_ACTION_TYPE_ATTACK = 4;
    env.RUNE_POWERUP_1, env.RUNE_POWERUP_2, env.RUNE_STATUS_AVAILABLE, env.PURCHASE_ITEM_SUCCESS = 0, 1, 1, 0;
    env.GetRuneSpawnLocation = function( rune ) return { x = rune == 0 and 400 or 2000, y = 0 } end;
    env.GetRuneStatus = function() return s.status or 1 end;
    env.IsLocationVisible = function() return s.visible end;
    env.IsLocationPassable = function() return s.passable end;
    env.GetNumCouriers = function() return #s.couriers end;
    env.GetCourier = function( i ) return s.couriers[i + 1] end;
    env.GetItemCost = function( name ) return name == "item_bottle" and 675 or name == "item_enchanted_mango" and 70 or 50 end;
    env.GetItemComponents = function() return {} end;
    env.print = function( line ) s.logs[#s.logs + 1] = line end;
    env.require = function( path )
        local p = assert( path:match( "laning/.*" ) );
        if p == "laning/profile" then return { economy_enabled = not disabled, observer_enabled = true, name = "test", controller = "test" } end;
        if not cache[p] then local f = assert( loadfile( p .. ".lua" ) ); setfenv( f, env ); cache[p] = f() end;
        return cache[p];
    end;
    local bot = {}; s.bot = bot; s.env = env;
    function bot:GetPlayerID() return 7 end;
    function bot:GetItemInSlot( slot ) return s.items[slot] end;
    function bot:GetMana() return s.mana end; function bot:GetMaxMana() return 300 end;
    function bot:GetHealth() return s.hp end; function bot:GetMaxHealth() return 1000 end;
    function bot:GetGold() return s.gold end; function bot:IsAlive() return true end;
    function bot:GetActiveMode() return s.mode end; function bot:GetTarget() return s.target end;
    function bot:GetCurrentActionType() return s.action or 0 end;
    function bot:IsUsingAbility() return s.casting or false end; function bot:IsChanneling() return false end;
    function bot:IsStunned() return false end; function bot:IsHexed() return false end;
    function bot:HasModifier() return s.regen or false end;
    function bot:GetLocation() return { x = 0, y = 0 } end;
    function bot:GetNearbyLaneCreeps() return s.creeps end;
    function bot:GetNearbyHeroes() return s.enemies end;
    function bot:GetNearbyTowers() return s.towers end;
    function bot:SetNextItemPurchaseValue() end;
    function bot:ActionImmediate_PurchaseItem( item )
        s.calls[#s.calls + 1] = item;
        if s.purchase_error then error( "unknown after submission" ) end;
        return s.result;
    end;
    function bot:Action_PickUpRune( rune ) s.runes[#s.runes + 1] = rune end;
    for _, method in ipairs( { "Action_MoveToLocation", "Action_AttackUnit", "Action_ClearActions", "Action_UseAbility" } ) do
        bot[method] = function() error( "forbidden order " .. method ) end;
    end;
    env.GetBot = function() return bot end;
    function s:item( name, n ) return { GetName = function() return name end, GetCurrentCharges = function() return n or 0 end } end;
    function s:unit() return { IsAlive = function() return true end, CanBeSeen = function() return true end,
        IsNull = function() return false end, IsHero = function() return true end } end;
    function s:load( path ) local f = assert( loadfile( path ) ); setfenv( f, env ); return f() end;
    s.mana_policy = env.require( "bots/laning/economy/mana" );
    s.rune_policy = env.require( "bots/laning/economy/runes" );
    return s;
end;
test( "disabled profile never buys or enables rune desire", function()
    local s = scenario( true ); eq( s.mana_policy.TryPurchase( s.bot ), false ); eq( #s.calls, 0 ); eq( s.rune_policy.GetDesire( s.bot ), 0 );
end );
test( "safe low mana buys one clarity and records result", function()
    local s = scenario(); eq( s.mana_policy.TryPurchase( s.bot ), true ); eq( s.calls[1], "item_clarity" );
    assert( s.logs[#s.logs]:find( "mana_purchase_result", 1, true ) );
end );
test( "visible enemy selects mango instead of interruptible regen", function()
    local s = scenario(); s.enemies = { s:unit() }; s.mana_policy.TryPurchase( s.bot ); eq( s.calls[1], "item_enchanted_mango" );
end );
test( "bottle savings are preserved", function()
    local s = scenario(); s.gold = 700; eq( s.mana_policy.TryPurchase( s.bot ), false ); eq( #s.calls, 0 );
    s.time = 106; s.gold = 725; eq( s.mana_policy.TryPurchase( s.bot ), true );
end );
test( "bottle with charges, backpack and stash supply prevent duplicate purchases", function()
    for _, slot in ipairs( { 0, 6, 9 } ) do
        local s = scenario(); s.items[slot] = s:item( "item_bottle", 1 ); eq( s.mana_policy.TryPurchase( s.bot ), false );
    end;
end );
test( "own courier supply counts while another courier does not", function()
    for _, owner in ipairs( { 7, 8 } ) do
        local s = scenario(); s.couriers = { { GetPlayerID = function() return owner end,
            GetItemInSlot = function( _, i ) if i == 0 then return s:item( "item_clarity", 1 ) end end } };
        eq( s.mana_policy.TryPurchase( s.bot ), owner ~= 7 );
    end;
end );
test( "empty bottle permits limited refill purchase", function()
    local s = scenario(); s.items[0] = s:item( "item_bottle", 0 ); s.gold = 60;
    eq( s.mana_policy.TryPurchase( s.bot ), true ); eq( s.calls[1], "item_clarity" );
end );
test( "sufficient mana and ongoing regen do not buy", function()
    local s = scenario(); s.mana = 150; eq( s.mana_policy.TryPurchase( s.bot ), false );
    s.time = 106; s.mana = 50; s.regen = true; eq( s.mana_policy.TryPurchase( s.bot ), false );
end );
test( "unknown courier or inventory fields fail closed", function()
    local s = scenario(); s.env.GetNumCouriers = nil; eq( s.mana_policy.TryPurchase( s.bot ), false );
    local t = scenario(); t.bot.GetItemInSlot = function() error( "API unavailable" ) end; eq( t.mana_policy.TryPurchase( t.bot ), false );
end );
test( "accepted purchase remains pending without delivery and never duplicates", function()
    local s = scenario(); s.mana_policy.TryPurchase( s.bot ); s.time = 300;
    eq( s.mana_policy.TryPurchase( s.bot ), false ); eq( #s.calls, 1 );
end );
test( "observed supply then consumption respects 90 second interval", function()
    local s = scenario(); s.mana_policy.TryPurchase( s.bot );
    s.items[0] = s:item( "item_clarity", 1 ); s.time = 106; s.mana_policy.TryPurchase( s.bot );
    s.items[0] = nil; s.time = 120; eq( s.mana_policy.TryPurchase( s.bot ), false );
    s.time = 190; eq( s.mana_policy.TryPurchase( s.bot ), true ); eq( #s.calls, 2 );
end );
test( "failure retries after five seconds and unknown outcome never rebought", function()
    local s = scenario(); s.result = 4; s.mana_policy.TryPurchase( s.bot ); s.time = 101;
    eq( s.mana_policy.TryPurchase( s.bot ), false ); s.time = 105; eq( s.mana_policy.TryPurchase( s.bot ), true );
    local t = scenario(); t.purchase_error = true; t.mana_policy.TryPurchase( t.bot ); t.time = 300;
    eq( t.mana_policy.TryPurchase( t.bot ), false ); eq( #t.calls, 1 );
    local u = scenario(); u.result = nil; u.mana_policy.TryPurchase( u.bot ); u.time = 300;
    eq( u.mana_policy.TryPurchase( u.bot ), false ); eq( #u.calls, 1 );
end );
test( "gold budget limits repeated mango purchases to 140 gold", function()
    local s = scenario(); s.enemies = { s:unit() };
    for i = 0, 3 do
        s.time = 100 + i * 100; s.mana_policy.TryPurchase( s.bot );
        s.items[0] = s:item( "item_enchanted_mango", 1 ); s.time = s.time + 5; s.mana_policy.TryPurchase( s.bot ); s.items[0] = nil;
    end;
    eq( #s.calls, 2 );
end );
test( "three purchase cap and ten minute window", function()
    local s = scenario();
    for i = 0, 3 do
        s.time = 100 + i * 100; s.mana_policy.TryPurchase( s.bot );
        s.items[0] = s:item( "item_clarity", 1 ); s.time = s.time + 5; s.mana_policy.TryPurchase( s.bot ); s.items[0] = nil;
    end;
    eq( #s.calls, 3 ); local t = scenario(); t.time = 601; eq( t.mana_policy.TryPurchase( t.bot ), false );
end );
test( "healthy low mana skips salve only in explicit profile", function()
    local s = scenario(); eq( s.mana_policy.SkipFlask( s.bot ), true ); s.hp = 400; eq( s.mana_policy.SkipFlask( s.bot ), false );
    local t = scenario( true ); eq( t.mana_policy.SkipFlask( t.bot ), false );
end );
test( "actual purchase callback issues at most one buy and baseline queue continues", function()
    local s = scenario(); s:load( "item_purchase_nevermore.lua" ); s.env.ItemPurchaseThink();
    eq( #s.calls, 1 ); eq( s.calls[1], "item_clarity" ); s.time = 101; s.env.ItemPurchaseThink(); eq( s.calls[2], "item_tango" );
end );
test( "actual purchase callback preserves baseline when module fails", function()
    local s = scenario(); s.env.require = function() error( "helper missing" ) end;
    s:load( "item_purchase_nevermore.lua" ); s.env.ItemPurchaseThink(); eq( s.calls[1], "item_tango" );
end );
test( "rune desire remains below normal lane desire and never moves directly", function()
    local s = scenario(); local plan = s.rune_policy.Decide( s.bot ); assert( plan ); eq( plan.desire, .15 );
    s.mode = 7; s.rune_policy.Think( s.bot ); eq( #s.runes, 1 ); eq( s.runes[1], 0 );
    s.rune_policy.Think( s.bot ); eq( #s.runes, 1 );
end );
test( "wave, combat, retreat and target hero outrank rune", function()
    local s = scenario(); s.creeps = { s:unit() }; eq( s.rune_policy.GetDesire( s.bot ), 0 );
    s.creeps = {}; s.mode = 2; eq( s.rune_policy.GetDesire( s.bot ), 0 );
    s.mode = 4; eq( s.rune_policy.GetDesire( s.bot ), 0 );
    s.mode = 1; s.target = s:unit(); eq( s.rune_policy.GetDesire( s.bot ), 0 );
end );
test( "distant, unseen, missing and impassable rune are never pursued", function()
    local s = scenario(); s.env.GetRuneSpawnLocation = function() return { x = 700, y = 0 } end; eq( s.rune_policy.GetDesire( s.bot ), 0 );
    local t = scenario(); t.visible = false; eq( t.rune_policy.GetDesire( t.bot ), 0 );
    t.visible = true; t.status = 2; eq( t.rune_policy.GetDesire( t.bot ), 0 );
    t.status = 1; t.passable = false; eq( t.rune_policy.GetDesire( t.bot ), 0 );
end );
test( "rune missing API and unhealthy or busy bot fail closed", function()
    local s = scenario(); s.env.GetRuneStatus = nil; eq( s.rune_policy.GetDesire( s.bot ), 0 );
    local t = scenario(); t.hp = 400; eq( t.rune_policy.GetDesire( t.bot ), 0 );
    t.hp = 1000; t.casting = true; eq( t.rune_policy.GetDesire( t.bot ), 0 );
    t.casting = false; t.bot.GetNearbyLaneCreeps = function() return nil end; eq( t.rune_policy.GetDesire( t.bot ), 0 );
end );
test( "fresh rune revalidation cancels order when wave arrives", function()
    local s = scenario(); assert( s.rune_policy.GetDesire( s.bot ) > 0 ); s.mode = 7; s.creeps = { s:unit() };
    s.rune_policy.Think( s.bot ); eq( #s.runes, 0 );
end );
test( "enemy or tower risk blocks rune order", function()
    local s = scenario(); s.enemies = { s:unit() }; eq( s.rune_policy.GetDesire( s.bot ), 0 );
    s.enemies = {}; local tower = s:unit(); tower.GetLocation = function() return { x = 500, y = 0 } end;
    tower.GetAttackRange = function() return 700 end; s.towers = { tower }; eq( s.rune_policy.GetDesire( s.bot ), 0 );
end );
test( "actual rune entry exports complete callbacks without C++ fallback", function()
    local s = scenario(); s:load( "profiles/lane_economy/mode_rune_nevermore.lua" );
    eq( s.env.GetDesire(), .15 ); s.mode = 7; s.env.Think(); eq( #s.runes, 1 );
end );
test( "rune entry helper failure disables rune instead of hanging a winning mode", function()
    local s = scenario(); s.env.require = function() error( "missing" ) end;
    s:load( "profiles/lane_economy/mode_rune_nevermore.lua" ); eq( s.env.GetDesire(), 0 ); s.env.Think(); eq( #s.runes, 0 );
end );
test( "logger failure never repeats a mana purchase", function()
    local s = scenario(); s.env.print = function() error( "sink unavailable" ) end;
    eq( s.mana_policy.TryPurchase( s.bot ), true ); s.time = 300; eq( s.mana_policy.TryPurchase( s.bot ), false ); eq( #s.calls, 1 );
end );
test( "observer exposes ability upgrade diagnostics without inferring rewards", function()
    local s = scenario(); local a = { GetLevel = function() return 0 end, IsHidden = function() return true end,
        IsActivated = function() return false end, CanAbilityBeUpgraded = function() return false end,
        GetName = function() return "actual_client_ability_name" end };
    s.bot.GetAbilityByName = function() return a end; s.bot.GetAbilityPoints = function() return 2 end;
    s.bot.GetAbilityInSlot = function( _, slot ) if slot == 3 then return a end end;
    local o = s.env.require( "bots/laning/observer/core" ); local r = o.Capture( s.bot );
    eq( r.hero.ability_points, 2 ); eq( r.hero.abilities[1].hidden, true ); eq( r.hero.abilities[1].upgradable, false );
    eq( r.hero.mode_name, "BOT_MODE_LANING" ); eq( r.farm_objective.full_wave_bonus_enabled, false );
    eq( r.hero.ability_slots[1].name, "actual_client_ability_name" ); eq( r.hero.ability_slots[1].slot, 3 );
end );
print( "ECONOMY PASSED " .. passed .. " cases" );
