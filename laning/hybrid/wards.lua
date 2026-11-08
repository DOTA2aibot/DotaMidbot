local Actor = require( GetScriptDirectory() .. "/laning/integration/actor" );
-- Opt-in mid ward test. Не ходит, не переключает режимы, не отменяет команды.
local A = require( GetScriptDirectory() .. "/laning/runtime/api" );
local O = require( GetScriptDirectory() .. "/laning/observer/core" );
local C = require( GetScriptDirectory() .. "/laning/observer/config" );
local M = {};
local function kind( name )
    if type( name ) ~= "string" then return nil end;
    if name:find( "observer", 1, true ) then return "observer" end;
    if name:find( "sentry", 1, true ) then return "sentry" end;
end
local function wards()
    if UNIT_LIST_ALLIED_WARDS == nil then return nil end;
    local list = O.Global( "GetUnitList", UNIT_LIST_ALLIED_WARDS );
    if type( list ) ~= "table" then return nil end;
    local out = {};
    for _, unit in ipairs( list ) do
        if #out >= 32 then break end;
        if A.Visible( unit ) then
            local p, name = A.Position( unit ), A.Call( unit, "GetUnitName" );
            if p and kind( name ) then out[#out + 1] = { handle = unit, position = p, kind = kind( name ),
                owner = A.Call( unit, "GetPlayerID" ) } end;
        end;
    end;
    return out;
end
function M.Plan( bot, s )
    s.ward_inventory_reason = nil;
    local h, position = A.Call( bot, "GetHealth" ), A.Position( bot );
    local max = A.Call( bot, "GetMaxHealth" );
    if not position or not A.Number( h ) or not A.Number( max ) or max <= 0 or h / max < C.ward_min_hp_fraction then
        return nil, "ward_health_or_position";
    end;
    if A.Call( bot, "IsAlive" ) ~= true or A.Call( bot, "IsUsingAbility" ) ~= false
        or A.Call( bot, "IsChanneling" ) ~= false or A.Call( bot, "IsStunned" ) ~= false then return nil, "ward_busy_or_disabled" end;
    local mode = A.Call( bot, "GetActiveMode" );
    if BOT_MODE_RETREAT == nil or not A.Number( mode ) or mode == BOT_MODE_RETREAT then return nil, "ward_retreat_or_mode_unknown" end;
    local current = A.Call( bot, "GetCurrentActionType" );
    -- T024 (Олег 08.11): бот почти никогда не IDLE на линии, поэтому вард не
    -- ставился вообще. Разрешаем прервать и обычное ПЕРЕДВИЖЕНИЕ (MOVE_TO) —
    -- движок штатно перевыдаст приказ на следующем тике, а спам режет
    -- ward_interval_s. Атаки/касты/pickup по-прежнему не трогаем.
    local interruptible = current ~= nil and ( ( BOT_ACTION_TYPE_IDLE ~= nil and current == BOT_ACTION_TYPE_IDLE )
        or ( BOT_ACTION_TYPE_NONE ~= nil and current == BOT_ACTION_TYPE_NONE )
        or ( BOT_ACTION_TYPE_MOVE_TO ~= nil and current == BOT_ACTION_TYPE_MOVE_TO ) );
    if not interruptible then return nil, "ward_preserve_native_action" end;
    local enemies = A.Call( bot, "GetNearbyHeroes", C.ward_enemy_radius, true, BOT_MODE_NONE );
    local towers = A.Call( bot, "GetNearbyTowers", 1600, true );
    if type( enemies ) ~= "table" or type( towers ) ~= "table" then return nil, "ward_safety_unknown" end;
    for _, enemy in ipairs( enemies ) do if A.Visible( enemy ) then return nil, "ward_enemy_nearby" end end;
    local center = O.Global( "GetLocationAlongLane", LANE_MID, 0.5 );
    local point;
    if center then
        local ok, p = pcall( function() return { x = center.x, y = center.y } end ); if ok then point = p end;
    end;
    if not point or not A.Number( point.x ) or not A.Number( point.y ) or A.Distance( point, position ) > 1800 then return nil, "ward_not_near_mid" end;
    local center_height, list = O.Height( point ), wards();
    if not center_height or not list then return nil, "ward_height_or_ward_list_unknown" end;
    local team = A.Call( bot, "GetTeam" );
    if team ~= 2 and team ~= 3 then return nil, "ward_team_unknown" end;
    local bank = O.Global( "GetLocationAlongLane", LANE_MID, team == 2 and 0.6 or 0.4 );
    if not bank or not A.Number( bank.x ) or not A.Number( bank.y ) then return nil, "ward_mid_direction_unknown" end;
    local length = A.Distance( point, bank ); if length <= 1 then return nil, "ward_mid_direction_unknown" end;
    local ux, uy = ( bank.x - point.x ) / length, ( bank.y - point.y ) / length;
    local item, item_kind, slot, cast_range, charges, secondary;
    for index = 0, 14 do
        local candidate = A.Call( bot, "GetItemInSlot", index ); local name = A.Call( candidate, "GetName" );
        if name == "item_ward_observer" or name == "item_ward_sentry" or name == "item_ward_dispenser" then
            if index <= 5 and A.Call( candidate, "IsFullyCastable" ) == true then
                item, item_kind, slot = candidate, kind( name ) or "dispenser_current_mode_unknown", index;
                cast_range = A.Call( item, "GetCastRange" ); charges = A.Call( item, "GetCurrentCharges" );
                secondary = A.Call( item, "GetSecondaryCharges" ); break;
            end;
            s.ward_inventory_reason = index > 5 and "ward_in_backpack_or_stash" or "ward_not_castable";
        end;
    end;
    if not item then return nil, s.ward_inventory_reason or "ward_not_owned" end;
    if not A.Number( cast_range ) or cast_range <= 0 or not A.Number( charges ) then return nil, "ward_cast_range_or_charges_unknown" end;
    if charges <= 0 and not ( A.Number( secondary ) and secondary > 0 ) then return nil, "ward_no_charges" end;
    for _, radius in ipairs( { 450, 750, 1000 } ) do
        for _, degrees in ipairs( { 0, 30, -30, 60, -60 } ) do
            local theta = degrees * math.pi / 180;
            local p = { x = point.x + ( ux * math.cos( theta ) - uy * math.sin( theta ) ) * radius,
                y = point.y + ( ux * math.sin( theta ) + uy * math.cos( theta ) ) * radius };
            local height = O.Height( p );
            if height and height > center_height and A.Distance( p, position ) <= cast_range - 25
                and O.Global( "IsLocationPassable", A.Vector( p ) ) == true then
                local blocked = false;
                for _, ward in ipairs( list ) do
                    if A.Distance( ward.position, p ) <= C.ward_dedup_radius
                        and ( item_kind:find( "unknown", 1, true ) or ward.kind == item_kind ) then blocked = true end;
                end;
                -- Синий вард — detection рядом с имеющимся observer, не замена обзору.
                if item_kind == "sentry" then
                    local support = false;
                    for _, ward in ipairs( list ) do if ward.kind == "observer" and A.Distance( ward.position, p ) <= 600 then support = true end end;
                    if not support then blocked = true end;
                end;
                for _, tower in ipairs( towers ) do
                    if A.Visible( tower ) then
                        local tp, range = A.Position( tower ), A.Call( tower, "GetAttackRange" );
                        if not tp or not A.Number( range ) or A.Distance( tp, p ) <= range + 150 then blocked = true end;
                    end;
                end;
                if not blocked then return { item = item, slot = slot, kind = item_kind, location = p,
                    height = height, cast_range = cast_range, charges = charges, secondary = secondary, prior_wards = list }, nil end;
            end;
        end;
    end;
    return nil, "ward_no_safe_new_highground_point_in_cast_range";
end
function M.Poll( bot, s )
    local now = A.Time(); if not now then return end;
    if s.ward_pending then
        local pending, list = s.ward_pending, wards(); local found;
        for _, w in ipairs( list or {} ) do
            local prior = false;
            for _, old in ipairs( pending.prior_wards ) do if old.handle == w.handle then prior = true end end;
            if not prior and A.Distance( w.position, pending.location ) <= 128 then found = w; break end;
        end;
        local charge = A.Call( pending.item, "GetCurrentCharges" );
        local secondary = A.Call( pending.item, "GetSecondaryCharges" );
        local spent = A.Number( charge ) and charge < pending.charges
            or ( A.Number( secondary ) and A.Number( pending.secondary ) and secondary < pending.secondary );
        if found and spent then
            local matches;
            if A.Number( found.owner ) and found.owner >= 0 then matches = found.owner == A.Call( bot, "GetPlayerID" ) end;
            O.Emit( s, "ward_observed", { action_id = pending.id, ward_kind = found.kind,
                location = found.position, evidence = "charge_spent_and_new_nearby_ward",
                owner_matches = matches, owner_status = matches == nil and "unknown" or "observed",
                attribution = "owner_or_combat_binding_required_for_exclusive_credit" } );
            s.ward_pending = nil;
        elseif now - pending.at > C.ward_timeout_s then
            O.Emit( s, "ward_outcome_unknown", { action_id = pending.id, evidence = "placement_not_confirmed" } );
            s.ward_pending = nil;
        end;
        return true;
    end;
end
function M.Tick( bot, s )
    if not Actor.Real(bot) or Actor.Blocked(bot) then return end;
    local now = A.Time(); if not now then return end;
    if M.Poll( bot, s ) then return end;
    if now < ( s.next_ward or -math.huge ) then return end;
    s.next_ward = now + 1;
    local plan, reason = M.Plan( bot, s );
    if not plan then
        if reason ~= s.ward_last_reason or now >= ( s.next_ward_reason or 0 ) then
            O.Emit( s, "ward_skip", { reason = reason } ); s.next_ward_reason = now + 10; s.ward_last_reason = reason;
        end;
        return;
    end;
    -- Повторяем всю проверку перед API. Не доверяем старой точке/инвентарю.
    plan, reason = M.Plan( bot, s ); if not plan then return end;
    local logged = O.Emit( s, "ward_proposal", { location = plan.location, item_kind = plan.kind,
        option_id = 15, reason = "safe_in_range_mid_highground", executed = false } );
    if not logged then return end; -- при отказе logger не начинаем новый экспериментальный приказ
    local ok = pcall( function() bot:Action_UseAbilityOnLocation( plan.item, A.Vector( plan.location ) ) end );
    s.next_ward = now + C.ward_interval_s;
    if not ok then O.Emit( s, "ward_api_failed", { reason = "item_action_rejected" } ); return end;
    plan.id = O.Action( bot, "ward", plan.item, plan.location, "safe_in_range_mid_highground" );
    plan.at = now; s.ward_pending = plan;
end
return M;
