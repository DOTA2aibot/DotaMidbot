----------------------------------------------------------------------------------------------------
-- MIDBOT: закупка SF. Очередь продвигается только после подтверждённой покупки.
----------------------------------------------------------------------------------------------------
local PURCHASE_INTERVAL = 0.5; -- секунды между попытками, не вызывать магазин каждый кадр
local MAX_RECIPE_DEPTH = 16; -- защита от циклического/повреждённого рецепта
local tableItemsToBuy = {
	"item_tango", "item_wraith_band", "item_bottle", "item_flask", "item_magic_wand",
	"item_power_treads", "item_dragon_lance", "item_black_king_bar", "item_desolator",
	"item_butterfly", "item_satanic",
};
local pendingComponents = nil;
local nextAttemptTime = -math.huge;
local lastMessage = nil;

local function Report( message )
	if ( message ~= lastMessage ) then
		print( "[MIDBOT purchase] " .. message );
		lastMessage = message;
	end
end

local function CountSlots( unit, lastSlot, owned )
	for slot = 0, lastSlot do
		local item = unit:GetItemInSlot( slot );
		if ( item ~= nil ) then
			local name = item:GetName();
			owned[name] = ( owned[name] or 0 ) + 1;
		end
	end
end

local function OwnedItems( bot )
	local owned = {};
	CountSlots( bot, 14, owned ); -- inventory, backpack, stash
	if ( type( GetNumCouriers ) == "function" and type( GetCourier ) == "function" ) then
		for index = 0, GetNumCouriers() - 1 do
			local courier = GetCourier( index );
			if ( courier ~= nil and courier:GetPlayerID() == bot:GetPlayerID() ) then
				CountSlots( courier, 8, owned ); -- не учитывать чужого курьера
			end
		end
	end
	return owned;
end

local function ExpandRecipe( name, owned, output, visiting, depth )
	if ( type( name ) ~= "string" or name == "" ) then return false end;
	if ( ( owned[name] or 0 ) > 0 ) then
		owned[name] = owned[name] - 1;
		return true;
	end
	if ( visiting[name] or depth > MAX_RECIPE_DEPTH ) then return false end;
	local recipe = GetItemComponents( name );
	if ( recipe == nil ) then recipe = {} end;
	if ( type( recipe ) ~= "table" ) then return false end;
	-- Варианты рецепта: используем первый. Форму данных проверяем в игровом smoke.
	if ( type( recipe[1] ) == "table" ) then recipe = recipe[1] end;
	if ( #recipe == 0 or ( #recipe == 1 and recipe[1] == name ) ) then
		table.insert( output, name );
		return true;
	end
	visiting[name] = true;
	for _, component in ipairs( recipe ) do
		if ( not ExpandRecipe( component, owned, output, visiting, depth + 1 ) ) then
			visiting[name] = nil;
			return false;
		end
	end
	visiting[name] = nil;
	return true;
end

function ItemPurchaseThink()
	local bot = GetBot();
	if ( bot == nil ) then return end;
	if ( #tableItemsToBuy == 0 ) then
		bot:SetNextItemPurchaseValue( 0 );
		return;
	end
	local now = GameTime();
	if ( now < nextAttemptTime ) then return end;
	nextAttemptTime = now + PURCHASE_INTERVAL;
	-- Не подменять отсутствующую константу числом: неизвестный результат не успех.
	if ( PURCHASE_ITEM_SUCCESS == nil or type( GetItemComponents ) ~= "function" ) then
		Report( "blocked: purchase API/constants unavailable" );
		return;
	end
	local target = tableItemsToBuy[1];
	if ( pendingComponents == nil ) then
		local plan = {};
		if ( not ExpandRecipe( target, OwnedItems( bot ), plan, {}, 0 ) ) then
			Report( "blocked: invalid recipe target=" .. target );
			return;
		end
		pendingComponents = plan;
	end
	if ( #pendingComponents == 0 ) then
		table.remove( tableItemsToBuy, 1 );
		pendingComponents = nil;
		bot:SetNextItemPurchaseValue( 0 );
		Report( "plan_complete target=" .. target .. " (assembly/delivery not verified)" );
		return;
	end
	local component = pendingComponents[1];
	local cost = GetItemCost( component );
	if ( type( cost ) ~= "number" or cost <= 0 or cost ~= cost or cost == math.huge ) then
		Report( "blocked: invalid cost item=" .. component );
		return;
	end
	bot:SetNextItemPurchaseValue( cost );
	if ( bot:GetGold() < cost ) then return end;
	local result = bot:ActionImmediate_PurchaseItem( component );
	Report( "target=" .. target .. " item=" .. component .. " result=" .. tostring( result ) );
	if ( result == PURCHASE_ITEM_SUCCESS ) then
		table.remove( pendingComponents, 1 );
	end
end
