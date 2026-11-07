----------------------------------------------------------------------------------------------------
-- MIDBOT: закупка Shadow Fiend (мид)
-- Список и логика по образцу Valve bots_example: покупаем следующий предмет,
-- когда хватает золота. Названия — финальные предметы (компоненты докупаются сами).
----------------------------------------------------------------------------------------------------

local tableItemsToBuy = {
	"item_tango",
	"item_wraith_band",
	"item_bottle",
	"item_flask",
	"item_magic_wand",
	"item_power_treads",
	"item_dragon_lance",
	"item_black_king_bar",
	"item_desolator",
	"item_butterfly",
	"item_satanic",
};


function ItemPurchaseThink()

	local npcBot = GetBot();

	if ( #tableItemsToBuy == 0 )
	then
		npcBot:SetNextItemPurchaseValue( 0 );
		return;
	end

	local sNextItem = tableItemsToBuy[1];

	npcBot:SetNextItemPurchaseValue( GetItemCost( sNextItem ) );

	if ( npcBot:GetGold() >= GetItemCost( sNextItem ) )
	then
		npcBot:Action_PurchaseItem( sNextItem );
		table.remove( tableItemsToBuy, 1 );
	end

end

----------------------------------------------------------------------------------------------------
