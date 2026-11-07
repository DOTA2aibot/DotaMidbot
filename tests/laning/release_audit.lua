-- REPRO assertions: PASS означает «дефект воспроизведён», не «PR готов».
local count = 0;
local function eq( a, b ) assert( a == b, tostring( a ) .. " ~= " .. tostring( b ) ) end;
local function probe( name, fn ) fn(); count = count + 1; print( "REPRO_CONFIRMED " .. name ) end;
local function purchase( opt )
    local s = { time = 0, calls = {}, logs = {} };
    local e = setmetatable( {}, { __index = _G } );
    e.PURCHASE_ITEM_SUCCESS, e.PURCHASE_ITEM_OUT_OF_STOCK, e.PURCHASE_ITEM_INVALID_ITEM_NAME, e.PURCHASE_ITEM_DISALLOWED_ITEM = 0, 1, 2, 3;
    local bot = { GetPlayerID = function() return 7 end, GetItemInSlot = function() return nil end,
        GetGold = function() return 10000 end, SetNextItemPurchaseValue = function() end,
        ActionImmediate_PurchaseItem = function( _, item ) s.calls[#s.calls + 1] = item; return opt.result or 0 end };
    e.GetBot = function() return bot end; e.GameTime = function() return s.time end;
    e.GetItemCost = function( name ) return name == "item_ward_observer" and opt.observer_cost or 100 end;
    e.GetItemComponents = function() return {} end;
    e.print = function( message ) s.logs[#s.logs + 1] = message end;
    local f = assert( loadfile( "tests/laning/audit_sources/item_purchase_nevermore.lua" ) ); setfenv( f, e ); f();
    function s:tick() self.time = self.time + 0.5; e.ItemPurchaseThink() end;
    return s;
end
probe( "PR21 free observer stops queue before purchase API and bypasses failure counter", function()
    local s = purchase( { observer_cost = 0 } );
    for i = 1, 50 do s:tick() end;
    eq( #s.calls, 1 ); eq( s.calls[1], "item_tango" );
    assert( table.concat( s.logs, "\n" ):find( "blocked: invalid cost item=item_ward_observer", 1, true ) );
end );
probe( "PR21 temporary repeated purchase failure permanently removes current item", function()
    local s = purchase( { observer_cost = 100, result = 8 } );
    for i = 1, 21 do s:tick() end;
    eq( s.calls[20], "item_tango" ); eq( s.calls[21], "item_ward_observer" );
    assert( table.concat( s.logs, "\n" ):find( "reason=too_many_failures", 1, true ) );
end );
local V = {};
V.__index = V;
function V.__add( a, b ) return setmetatable( { x = a.x + b.x, y = a.y + b.y, z = 0 }, V ) end;
function V.__mul( a, b ) return setmetatable( { x = a.x * b, y = a.y * b, z = 0 }, V ) end;
local function vector( x, y ) return setmetatable( { x = x, y = y, z = 0 }, V ) end;
local function abilityEnv( creeps )
    local e = setmetatable( {}, { __index = _G } );
    e.Vector = vector;
    e.BOT_ACTION_DESIRE_NONE, e.BOT_ACTION_DESIRE_LOW, e.BOT_ACTION_DESIRE_MODERATE, e.BOT_ACTION_DESIRE_HIGH = 0, 0.2, 0.5, 0.8;
    e.BOT_MODE_LANING, e.BOT_MODE_DEFEND_TOWER_MID = 1, 2;
    e.BOT_MODE_RETREAT, e.BOT_MODE_EVASIVE_MANEUVERS, e.BOT_MODE_ROAM, e.BOT_MODE_GANK, e.BOT_MODE_TEAM_ROAM = 3, 4, 5, 6, 7;
    e.GetUnitToLocationDistance = function( unit, loc ) local p = unit:GetLocation(); return math.sqrt( ( p.x - loc.x )^2 + ( p.y - loc.y )^2 ) end;
    local a = { IsFullyCastable = function() return true end, GetAbilityDamage = function() return 60 end };
    local bot = { GetLocation = function() return vector( 0, 0 ) end, GetActiveMode = function() return e.BOT_MODE_DEFEND_TOWER_MID end,
        GetMana = function() return 100 end, GetMaxMana = function() return 100 end,
        GetNearbyLaneCreeps = function() return creeps end, GetNearbyTowers = function() return {} end,
        GetAbilityByName = function( _, name ) if name == "nevermore_shadowraze2" then return a end end };
    local f = assert( loadfile( "tests/laning/audit_sources/ability_item_usage_nevermore.lua" ) ); setfenv( f, e ); f();
    e.InitAbilities( bot ); return e, bot, a;
end
local function creep( x, y, hp, range )
    return { GetLocation = function() return vector( x, y ) end, GetHealth = function() return hp end,
        GetAttackRange = function() return range or 100 end, GetActualIncomingDamage = function() return 12 end };
end
probe( "PR21 creep pack count combines incompatible cast directions", function()
    local creeps = { creep( 450, 0, 999 ), creep( -225, 389.711, 999 ), creep( -225, -389.711, 999 ) };
    local e, bot = abilityEnv( creeps ); local desire, loc = e.ConsiderRazeOnCreeps( bot ); assert( desire > 0 );
    local impact = e.GetRazeImpactPoint( bot, loc, 2 ); local actual = 0;
    for _, c in ipairs( creeps ) do if e.Dist2D( c:GetLocation(), impact ) <= 250 then actual = actual + 1 end end;
    eq( actual, 1 ); -- выбран pack из 3, в единственную область входит 1
end );
probe( "PR21 siege is treated as ranged secure and reductions are never queried", function()
    local e, bot = abilityEnv( { creep( 450, 0, 50, 690 ) } );
    local desire = e.ConsiderRazeOnCreeps( bot ); assert( desire > 0 ); -- 60 raw > 50 HP, но supplied actual=12
end );
probe( "PR21 selected raze is submitted through location-targeted API", function()
    local e, bot, a = abilityEnv( {} ); local used;
    e.GetBot = function() return bot end;
    e.LevelUpThink = function() end; e.ConsiderRequiem = function() return 0 end;
    e.ConsiderRazeOnHero = function() return 0.5, vector( 450, 0 ), a end;
    bot.IsUsingAbility = function() return false end; bot.IsChanneling = bot.IsUsingAbility; bot.IsSilenced = bot.IsUsingAbility;
    bot.Action_UseAbilityOnLocation = function() used = "location" end;
    bot.Action_UseAbility = function() used = "no_target" end;
    e.AbilityUsageThink(); eq( used, "location" );
end );
probe( "PR21 level logic has no alternative when listed skills cannot upgrade", function()
    local e, bot = abilityEnv( {} ); local upgrades = 0;
    bot.GetAbilityPoints = function() return 1 end;
    bot.GetAbilityByName = function() return { CanAbilityBeUpgraded = function() return false end, GetLevel = function() return 1 end } end;
    bot.ActionImmediate_LevelAbility = function() upgrades = upgrades + 1 end;
    e.LevelUpThink( bot ); eq( upgrades, 0 );
end );
print( "PR21 AUDIT: " .. count .. " REPRODUCTIONS CONFIRMED; NOT RELEASE APPROVAL" );
