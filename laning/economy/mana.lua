local Actor = require( GetScriptDirectory() .. "/laning/integration/actor" );
-- Только покупка. Расходники использует прежний item-controller Valve.
local A = require( GetScriptDirectory() .. "/laning/runtime/api" );
local C = require( GetScriptDirectory() .. "/laning/economy/config" );
local Profile = require( GetScriptDirectory() .. "/laning/profile" );
local O = require( GetScriptDirectory() .. "/laning/observer/core" );
local M, states = {}, setmetatable( {}, { __mode = "k" } );
local function global( name, ... ) return O.Global( name, ... ) end;
local function state( bot )
    local now = A.Time(); local s = states[bot];
    if not s or ( now and s.time and now < s.time ) then
        s = { count = 0, spent = 0, accepted_count = 0, accepted_gold = 0 }; states[bot] = s;
    end;
    s.time = now; return s;
end;
local function lowmana( bot )
    local mana, max = A.Call( bot, "GetMana" ), A.Call( bot, "GetMaxMana" );
    return A.Number( mana ) and A.Number( max ) and max > 0
        and mana / max <= C.mana_fraction and max - mana >= C.mana_missing;
end;
-- Полная проверяемая перепись, включая свой courier. Ошибка чтения -> не покупать.
function M.Inventory( bot )
    local owned, supply, bottle = {}, false, false;
    local function scan( unit, last )
        for slot = 0, last do
            local ok, item = pcall( function() return unit:GetItemInSlot( slot ) end );
            if not ok then return false end;
            if item then
                local name = A.Call( item, "GetName" ); if type( name ) ~= "string" then return false end;
                owned[name] = true;
                if name == "item_bottle" then bottle = true end;
                if name == "item_clarity" or name == "item_enchanted_mango" then supply = true end;
                if name == "item_bottle" or name == "item_magic_stick" or name == "item_magic_wand" then
                    local n = A.Call( item, "GetCurrentCharges" );
                    if not A.Number( n ) or n > 0 then supply = true end;
                end;
            end;
        end;
        return true;
    end;
    if not scan( bot, 14 ) then return nil end;
    local count, id = global( "GetNumCouriers" ), A.Call( bot, "GetPlayerID" );
    if not A.Number( count ) or count < 0 or count > 10 or not A.Number( id ) then return nil end;
    for index = 0, count - 1 do
        local courier = global( "GetCourier", index );
        if not courier then return nil end;
        local owner = A.Call( courier, "GetPlayerID" ); if not A.Number( owner ) then return nil end;
        if owner == id and not scan( courier, 8 ) then return nil end;
    end;
    return { owned = owned, supply = supply, bottle = bottle };
end;
local function report( bot, s, reason, details )
    if not s.time or s.time < ( s.report_at or -math.huge ) then return end;
    s.report_at = s.time + C.mana_attempt_interval;
    details = details or {}; details.reason = reason;
    details.bought_count, details.spent_gold = s.accepted_count, s.accepted_gold;
    details.budget_count, details.budget_gold = s.count, s.spent;
    O.Emit( O.State( bot ), "mana_purchase_decision", details );
end;
function M.SkipFlask( bot )
    if Profile.economy_enabled ~= true or not lowmana( bot ) then return false end;
    local now = A.Time();
    if not now or now < 0 or now > C.mana_window_end or A.Call( bot, "IsAlive" ) ~= true then return false end;
    local hp, max = A.Call( bot, "GetHealth" ), A.Call( bot, "GetMaxHealth" );
    return A.Number( hp ) and A.Number( max ) and max > 0 and hp / max >= 0.85;
end;
function M.TryPurchase( bot )
    if not Actor.Real( bot ) then return false end;
    if Profile.economy_enabled ~= true then return false end;
    local s = state( bot ); local now = s.time;
    if not now or now < 0 or now > C.mana_window_end or A.Call( bot, "IsAlive" ) ~= true then return false end;
    if now < ( s.next_attempt or -math.huge ) then return false end;
    s.next_attempt = now + C.mana_attempt_interval;
    local inventory = M.Inventory( bot );
    if not inventory then report( bot, s, "inventory_or_courier_unknown" ); return false end;
    if s.pending and inventory.owned[s.pending.name] then s.pending = nil end;
    -- SUCCESS уже учтён в бюджете. Спустя интервал и полную перепись можно
    -- снова оценить нужду: предмет мог быть доставлен/съеден между опросами.
    -- Это НЕ подтверждение доставки/применения. Unknown result без предмета не истекает.
    if s.pending and s.pending.accepted and now >= s.pending.time + C.mana_purchase_interval then s.pending = nil end;
    if s.pending then report( bot, s, "paid_supply_delivery_unknown_no_rebuy" ); return false end;
    if not lowmana( bot ) then report( bot, s, "mana_sufficient_or_unknown" ); return false end;
    if inventory.supply then report( bot, s, "existing_mana_supply_use_before_buy" ); return false end;
    for _, modifier in ipairs( { "modifier_clarity_potion", "modifier_bottle_regeneration" } ) do
        local active = A.Call( bot, "HasModifier", modifier );
        if active ~= false then report( bot, s, "regen_active_or_unknown" ); return false end;
    end;
    if s.count >= C.mana_max_purchases or now < ( s.next_buy or -math.huge ) then report( bot, s, "count_or_interval_limit" ); return false end;
    local enemies = A.Call( bot, "GetNearbyHeroes", 900, true, BOT_MODE_NONE );
    if type( enemies ) ~= "table" then report( bot, s, "enemy_data_unknown" ); return false end;
    local threatened = false;
    for _, enemy in ipairs( enemies ) do if A.Visible( enemy ) then threatened = true end end;
    local item = threatened and "item_enchanted_mango" or "item_clarity";
    local cost, gold = global( "GetItemCost", item ), A.Call( bot, "GetGold" );
    if not A.Number( cost ) or cost <= 0 or not A.Number( gold ) then report( bot, s, "cost_or_gold_unknown" ); return false end;
    if s.spent + cost > C.mana_max_gold then report( bot, s, "gold_budget_limit" ); return false end;
    local reserve = 0;
    if not inventory.bottle then
        reserve = global( "GetItemCost", "item_bottle" );
        if not A.Number( reserve ) or reserve <= 0 then report( bot, s, "bottle_cost_unknown" ); return false end;
    end;
    if gold < cost + reserve then report( bot, s, "save_for_bottle_or_insufficient_gold" ); return false end;
    if PURCHASE_ITEM_SUCCESS == nil then report( bot, s, "purchase_constant_unknown" ); return false end;
    -- Ставим временный guard ДО вызова: исключение после побочного эффекта не даёт rebuy.
    local previous_next_buy = s.next_buy;
    s.pending = { name = item, time = now, accepted = false };
    s.count = s.count + 1; s.spent = s.spent + cost;
    s.next_buy = now + C.mana_purchase_interval; -- включает unknown, а не только SUCCESS
    local ok, result = pcall( function() return bot:ActionImmediate_PurchaseItem( item ) end );
    if ok and result == PURCHASE_ITEM_SUCCESS then
        s.pending.accepted = true;
        s.accepted_count = s.accepted_count + 1; s.accepted_gold = s.accepted_gold + cost;
    elseif ok and A.Number( result ) and result % 1 == 0 then
        -- Bot API возвращает integer purchase enum; остальные типы = unknown.
        s.pending = nil; s.count = s.count - 1; s.spent = s.spent - cost; s.next_buy = previous_next_buy;
    end;
    -- nil/exception = неизвестный исход; не заявлять успех и не покупать повторно.
    pcall( function() O.Emit( O.State( bot ), "mana_purchase_result", { item = item, result = result,
        accepted = ok and result == PURCHASE_ITEM_SUCCESS, outcome = "delivery_and_use_unverified",
        mana = A.Call( bot, "GetMana" ), gold_before = gold, cost = cost,
        bought_count = s.accepted_count, spent_gold = s.accepted_gold,
        budget_count = s.count, budget_gold = s.spent } ) end );
    return true; -- одна попытка покупки за callback, даже при отказе
end;
return M;
