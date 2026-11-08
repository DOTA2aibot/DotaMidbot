----------------------------------------------------------------------------------------------------
-- MIDBOT: закупка SF. Очередь продвигается после подтверждённой покупки;
-- недоступные предметы скипаются, временные отказы отправляют предмет в конец очереди.
----------------------------------------------------------------------------------------------------
local PURCHASE_INTERVAL = 0.5; -- секунды между попытками, не вызывать магазин каждый кадр
local MAX_RECIPE_DEPTH = 16; -- защита от циклического/повреждённого рецепта
local MAX_COMPONENT_FAILURES = 20; -- ~10 сек подряд неудач -> скипаем предмет, не встаём насмерть
-- Порядок по гайду Олега: танго -> варды -> ветки -> ботл -> дальше по сборке
local tableItemsToBuy = {
	"item_tango", "item_ward_observer", "item_ward_sentry", -- п.5 гайда: жёлтый+синий вард на старте
	"item_branches", "item_branches", "item_bottle", "item_flask",
	"item_wraith_band", "item_magic_wand",
	"item_power_treads", "item_dragon_lance", "item_black_king_bar", "item_desolator",
	"item_butterfly", "item_satanic",
};
local pendingComponents = nil;
local nextAttemptTime = -math.huge;
local lastMessage = nil;
local componentFailures = 0; -- подряд неудачные попытки купить текущий компонент
local ManaEconomy;
do
	local ok, mod = pcall( function() return require( GetScriptDirectory() .. "/laning/economy/mana" ) end );
	if ok then ManaEconomy = mod end;
end;

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
	if ManaEconomy then
		local ok, attempted = pcall( ManaEconomy.TryPurchase, bot );
		if ok and attempted then return end;
	end;
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
	if target == "item_flask" and pendingComponents == nil and ManaEconomy then
		local ok, skip = pcall( ManaEconomy.SkipFlask, bot );
		if ok and skip then
			table.remove( tableItemsToBuy, 1 );
			Report( "skip target=item_flask reason=healthy_but_mana_low" );
			return;
		end;
	end;
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
		componentFailures = 0;
		bot:SetNextItemPurchaseValue( 0 );
		Report( "plan_complete target=" .. target .. " (assembly/delivery not verified)" );
		return;
	end
	local component = pendingComponents[1];
	local cost = GetItemCost( component );
	-- Цена 0 — ВАЛИДНА: observer ward в текущем патче бесплатный (фикс аудита GPT:
	-- раньше cost<=0 считался ошибкой и очередь навсегда вставала на варде).
	if ( type( cost ) ~= "number" or cost < 0 or cost ~= cost or cost == math.huge ) then
		Report( "blocked: invalid cost item=" .. component );
		return;
	end
	bot:SetNextItemPurchaseValue( cost );
	if ( bot:GetGold() < cost ) then return end;
	local result = bot:ActionImmediate_PurchaseItem( component );
	Report( "target=" .. target .. " item=" .. component .. " result=" .. tostring( result ) );
	if ( result == PURCHASE_ITEM_SUCCESS ) then
		table.remove( pendingComponents, 1 );
		componentFailures = 0;
		return;
	end
	-- Кросс-зона фикс [kimi] по репорту Олега: варды выкупили со склада другие боты,
	-- и бот вечно ретраил вард, не идя дальше по списку.
	-- Предмет недоступен принципиально (нет на складе / запрещён / невалиден) —
	-- скипаем его целиком и идём к следующему.
	if ( ( PURCHASE_ITEM_OUT_OF_STOCK ~= nil and result == PURCHASE_ITEM_OUT_OF_STOCK )
		or ( PURCHASE_ITEM_INVALID_ITEM_NAME ~= nil and result == PURCHASE_ITEM_INVALID_ITEM_NAME )
		or ( PURCHASE_ITEM_DISALLOWED_ITEM ~= nil and result == PURCHASE_ITEM_DISALLOWED_ITEM ) ) then
		Report( "skip target=" .. target .. " reason=unavailable result=" .. tostring( result ) );
		pendingComponents = nil;
		componentFailures = 0;
		table.remove( tableItemsToBuy, 1 );
		return;
	end
	-- Остальные неудачи (нет золота в моменте, не у лавки и т.п.) — ретраим,
	-- но с предохранителем: 20 подряд (~10 сек) -> скип, чтобы закупка не вставала насмерть.
	componentFailures = componentFailures + 1;
	if ( componentFailures >= MAX_COMPONENT_FAILURES ) then
		-- Фикс аудита GPT: временные отказы не должны необратимо удалять предмет
		-- (можно потерять сборку, уже оплатив часть компонентов). Переносим цель
		-- в КОНЕЦ очереди — попробуем позже, а пока покупаем остальное.
		Report( "defer target=" .. target .. " reason=too_many_failures last_result=" .. tostring( result ) );
		pendingComponents = nil;
		componentFailures = 0;
		table.remove( tableItemsToBuy, 1 );
		table.insert( tableItemsToBuy, target );
	end
end
