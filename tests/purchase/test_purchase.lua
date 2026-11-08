-- Run from repository root: lua tests/purchase/test_purchase.lua (Lua 5.1).
-- Синтетические рецепты ниже проверяют алгоритм, а не текущие рецепты Dota.
local passed = 0;
local function eq( a, b ) assert( a == b, tostring( a ) .. " ~= " .. tostring( b ) ) end;
local function scenario( opt )
	opt = opt or {};
	local s = { now = 0, calls = {}, gold = 100000, result = 0, logs = {} };
	local env = setmetatable( {}, { __index = _G } );
	env.PURCHASE_ITEM_SUCCESS = 0;
	if opt.unavailable_constants then
		env.PURCHASE_ITEM_OUT_OF_STOCK = 100;
		env.PURCHASE_ITEM_INVALID_ITEM_NAME = 101;
		env.PURCHASE_ITEM_DISALLOWED_ITEM = 102;
	end;
	if ( opt.noConstant ) then env.PURCHASE_ITEM_SUCCESS = nil end;
	local function item( name ) return { GetName = function() return name end } end;
	local bot = {
        IsHero=function() return true end,IsIllusion=function() return false end,
        GetUnitName=function() return "npc_dota_hero_nevermore" end,
		GetPlayerID = function() return 7 end,
		GetItemInSlot = function( _, n ) local name = ( opt.slots or {} )[n]; return name and item( name ) or nil end,
		GetGold = function() return s.gold end,
		SetNextItemPurchaseValue = function( _, cost ) s.nextCost = cost end,
		ActionImmediate_PurchaseItem = function( _, name )
			table.insert( s.calls, name );
			if ( opt.purchase ) then return opt.purchase( s, name ) end;
			return s.result;
		end,
	};
	-- Старый метод оставлен только в mock, чтобы воспроизвести дефект исходной очереди.
	bot.Action_PurchaseItem = bot.ActionImmediate_PurchaseItem;
	env.GetBot = function() if ( opt.noBot ) then return nil end; return bot end;
	env.GameTime = function() return s.now end;
    env.GetScriptDirectory=function() return "bots" end;local cache={};
    env.require=function(path) local p=assert(path:match("laning/.*"));if p=="laning/profile" then return {economy_enabled=false} end;
        if not cache[p] then local f=assert(loadfile(p..".lua"));setfenv(f,env);cache[p]=f() end;return cache[p];end;
	env.GetItemCost = opt.cost or function() return 100 end;
	env.GetItemComponents = opt.recipe or function() return {} end;
	env.GetNumCouriers = function() return #( opt.couriers or {} ) end;
	-- T023: константы курьера в реальной Доте есть всегда — фикстура их отражает,
	-- иначе диагностика «нет API» честно печатается и ломает проверки логов.
	env.COURIER_ACTION_TAKE_AND_TRANSFER_ITEMS = 5;
	env.COURIER_STATE_IDLE, env.COURIER_STATE_AT_BASE = 0, 1;
	env.GetCourier = function( index )
		local c = opt.couriers[index + 1];
		return {
			GetPlayerID = function() return c.owner end,
			GetItemInSlot = function( _, n ) return c.slots[n] and item( c.slots[n] ) or nil end,
			GetCourierState = function() return 0 end,
		};
	end;
	env.print = function( message ) table.insert( s.logs, message ) end;
	local chunk = assert( loadfile( PURCHASE_SOURCE or "item_purchase_nevermore.lua" ) ); setfenv( chunk, env ); chunk();
	function s:tick( dt ) self.now = self.now + ( dt or 0.5 ); env.ItemPurchaseThink() end;
	return s;
end
local function test( name, fn ) fn(); passed = passed + 1; print( "PASS " .. name ) end;

test( "failure retries; success advances exactly once", function()
	local s = scenario(); s.result = 4; s:tick(); s:tick();
	eq( s.calls[1], "item_tango" ); eq( s.calls[2], "item_tango" );
	s.result = 0; s:tick(); s:tick(); s:tick(); eq( s.calls[3], "item_tango" );
	eq( s.calls[4], "item_branches" ); eq( #s.calls, 4 );
end );
test( "nil result is not success", function()
	local s = scenario( { purchase = function() return nil end } ); s:tick(); s:tick();
	eq( s.calls[1], "item_tango" ); eq( s.calls[2], "item_tango" );
end );
test( "insufficient gold does not skip", function()
	local s = scenario(); s.gold = 0; s:tick(); eq( #s.calls, 0 ); eq( s.nextCost, 100 );
	s.gold = 100; s:tick(); eq( s.calls[1], "item_tango" );
end );
test( "attempt throttling", function()
	local s = scenario(); s.result = 4; s:tick( 0 ); s:tick( 0.1 ); s:tick( 0.1 );
	eq( #s.calls, 1 ); s:tick( 0.3 ); eq( #s.calls, 2 );
end );
test( "nested recipe, repeated component and first variant", function()
	local s = scenario( { recipe = function( name )
		if ( name == "item_wraith_band" ) then return { { "part_a", "bundle", "part_a" }, { "unused" } } end;
		if ( name == "bundle" ) then return { "part_b", "part_c" } end; return {};
	end } );
	for i = 1, 16 do s:tick() end;
	eq( table.concat( s.calls, "," ), "item_tango,item_branches,item_branches,item_bottle,item_flask,part_a,part_b,part_c,part_a,item_magic_wand" );
end );
test( "stash and own courier credit; other courier excluded", function()
	local s = scenario( { slots = { [9] = "part_a" },
		couriers = { { owner = 7, slots = { [0] = "part_b" } }, { owner = 8, slots = { [0] = "part_a" } } },
		recipe = function( name ) if ( name == "item_wraith_band" ) then return { { "part_a", "part_a", "part_b" } } end; return {} end,
	} );
	for i = 1, 13 do s:tick() end; eq( table.concat( s.calls, "," ), "item_tango,item_branches,item_branches,item_bottle,item_flask,part_a,item_magic_wand" );
end );
test( "delayed delivery and auto-combination do not rebuild paid components", function()
	local s = scenario( { recipe = function( name )
		if ( name == "item_wraith_band" ) then return { { "part_a", "part_b" } } end; return {};
	end } );
	-- Инвентарь пуст даже после успеха: компоненты могут ещё доставляться/собираться.
	for i = 1, 14 do s:tick() end; eq( table.concat( s.calls, "," ), "item_tango,item_branches,item_branches,item_bottle,item_flask,part_a,part_b,item_magic_wand" );
end );
test( "cycle blocks and log is deduplicated", function()
	local s = scenario( { recipe = function( name )
		if ( name == "item_tango" ) then return { { "cycle" } } end;
		if ( name == "cycle" ) then return { { "item_tango" } } end; return {};
	end } );
	s:tick(); s:tick(); eq( #s.calls, 0 ); eq( #s.logs, 1 );
end );
test( "self leaf recipe", function()
	local s = scenario( { recipe = function( name ) return { { name } } end } );
	s:tick(); eq( s.calls[1], "item_tango" );
end );
test( "malformed recipe blocks", function()
	local s = scenario( { recipe = function() return "bad" end } ); s:tick(); eq( #s.calls, 0 );
end );
test( "invalid costs never submit", function()
	for _, cost in ipairs( { -1, math.huge, "unknown" } ) do
		local s = scenario( { cost = function() return cost end } ); s:tick(); s:tick(); eq( #s.calls, 0 );
	end
end );
test( "all targets terminate without duplicate spending", function()
	local s = scenario(); for i = 1, 30 do s:tick() end;
	eq( #s.calls, 13 ); eq( s.calls[13], "item_satanic" ); eq( s.nextCost, 0 );
end );
test( "shop and stock failures retain position", function()
	for _, result in ipairs( { 1, 2, 3, 5, 6, 7 } ) do
		local s = scenario(); s.result = result; s:tick(); s:tick();
		eq( s.calls[1], "item_tango" ); eq( s.calls[2], "item_tango" );
	end
end );
test( "missing constant blocks rather than nil equals nil", function()
	local s = scenario( { noConstant = true, purchase = function() return nil end } );
	s:tick(); eq( #s.calls, 0 );
end );
test( "missing bot is harmless", function()
	local s = scenario( { noBot = true } ); s:tick(); eq( #s.calls, 0 );
end );
test( "failed middle component retries without repurchasing paid predecessor", function()
	local s = scenario( { recipe = function( name )
		if ( name == "item_wraith_band" ) then return { { "part_a", "part_b" } } end; return {};
	end, purchase = function( state, name )
		if name == "part_b" then
			state.part_b_calls = ( state.part_b_calls or 0 ) + 1;
			if state.part_b_calls < 3 then return 4 end;
		end;
		return 0;
	end } );
	for i = 1, 16 do s:tick() end;
	eq( table.concat( s.calls, "," ), "item_tango,item_branches,item_branches,item_bottle,item_flask,part_a,part_b,part_b,part_b,item_magic_wand" );
end );
test( "inventory and backpack components are reused", function()
	local s = scenario( { slots = { [0] = "part_a", [6] = "part_b" },
		recipe = function( name ) if ( name == "item_wraith_band" ) then return { { "part_a", "part_b" } } end; return {} end,
	} );
	for i = 1, 12 do s:tick() end;
	eq( table.concat( s.calls, "," ), "item_tango,item_branches,item_branches,item_bottle,item_flask,item_magic_wand" );
end );
test( "zero cost is a valid purchase rather than a queue blocker", function()
	local s = scenario( { cost = function() return 0 end } ); s:tick(); eq( s.calls[1], "item_tango" );
end );
test( "known unavailable result skips target but nil still retries", function()
	local s = scenario( { unavailable_constants = true } ); s.result = 100; s:tick(); s:tick();
	eq( s.calls[1], "item_tango" ); eq( s.calls[2], "item_branches" );
	local t = scenario( { unavailable_constants = true, purchase = function() return nil end } );
	t:tick(); t:tick(); eq( t.calls[1], "item_tango" ); eq( t.calls[2], "item_tango" );
end );
print( "PURCHASE PASSED " .. passed .. " tests (mock API, not a Dota runtime test)" );
