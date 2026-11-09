local U=require(GetScriptDirectory().."/laning/tactical/util");
local C=require(GetScriptDirectory().."/laning/vision/config");
local Site=require(GetScriptDirectory().."/laning/vision/site");
local B=require(GetScriptDirectory().."/laning/tactical/broker");
local Schedule=require(GetScriptDirectory().."/laning/vision/schedule");
local Profile=require(GetScriptDirectory().."/laning/profile");
local M,states={},setmetatable({}, {__mode="k"});
local function state(bot)
    local now=U.Now();local s=states[bot];if not now then return nil end;
    if not s or now<(s.time or now) then s={};states[bot]=s end;s.time=now;return s;
end;
local function emit(bot,s,kind,data) B.Emit(B.State(bot),kind,data) end;
function M.StartupAttempt(bot,result)
    local s=state(bot);if not s then return end;
    if not U.Number(result) or (PURCHASE_ITEM_SUCCESS~=nil and result==PURCHASE_ITEM_SUCCESS) then
        s.pending=U.Now();s.pendingReported=false;s.target_slot=0;s.target_start=0;
    else s.nextBuy=U.Now()+C.purchase_retry_s end;
    emit(bot,s,"vision_startup_purchase",{result=result,outcome="delivery_unverified"});
end;
function M.Placed(bot,ward,spot)
    local s=state(bot);if not s then return end;
    s.ward=ward;s.expires=U.Now()+C.duration_s;s.pending=nil;s.last_slot=spot.vision_slot or Schedule.Slot(U.Now());s.target_slot=nil;s.target_start=nil;
    emit(bot,s,"vision_lifetime",{location=spot.location,expires_at=s.expires,duration_s=C.duration_s,evidence="placement_confirmed"});
end;
-- Primary refresh intentionally ignores every old ward; recovery never duplicates coverage.
function M.CanReplace(bot,ward,window)
    if type(window)=="number" then local w=C.windows[window+1];window=w and {slot=window,kind="primary",start=w.start,finish=w.finish} end;
    return Profile.ward_phase_enabled==true and ward and window and window.kind=="primary"
        and not Schedule.Completed(B.State(bot),window) or false;
end;
function M.StockDetails(bot)
    local d={active=0,active_castable=0,backpack=0,stash=0,courier=0,total=0};
    local function slots(unit,last,courier)
        if type(unit.GetItemInSlot)~="function" then return false end;
        for slot=0,last do
            local ok,item=pcall(unit.GetItemInSlot,unit,slot);if not ok then return false end;
            local name=U.Call(item,"GetName");if item~=nil and type(name)~="string" then return false end;
            if name=="item_ward_observer" or name=="item_ward_dispenser" then
                local n=U.Call(item,"GetCurrentCharges");if not U.Number(n) or n<0 then return false end;
                local where=courier and "courier" or (slot<=5 and "active" or (slot<=8 and "backpack" or "stash"));
                d[where]=d[where]+n;d.total=d.total+n;
                if where=="active" and U.Ready(item) then d.active_castable=d.active_castable+n end;
            end;
        end;return true;
    end;
    if not slots(bot,14,false) then return nil end;
    local n=U.Global("GetNumCouriers");local id=U.Call(bot,"GetPlayerID");
    if not U.Number(n) or n<0 or not U.Number(id) then return nil end;
    for i=0,n-1 do
        local courier=U.Global("GetCourier",i);local owner=U.Call(courier,"GetPlayerID");
        if owner==nil then return nil end;
        if owner==id and not slots(courier,8,true) then return nil end;
    end;
    return d;
end;
local function supply(bot) local d=M.StockDetails(bot);return d and d.total end;
M.Stock=supply;
local function phaseProfile(bot)
    return Site.ObserverSupported(bot) and C.calibration_only~=true and Profile.ward_phase_enabled==true
        and Profile.wards_enabled==true and Profile.runtime_enabled~=true;
end;
function M.Observe(bot)
    if not phaseProfile(bot) then return end;
    local s=state(bot);if not s or U.Now()<(s.nextObserve or -math.huge) then return end;s.nextObserve=U.Now()+1;
    local d=M.StockDetails(bot);local request=Schedule.Request(U.Now(),B.State(bot));
    local slot=request and request.slot or s.target_slot;
    local deadline=request and request.start or s.target_start;
    local key=d and table.concat({d.active,d.active_castable,d.backpack,d.stash,d.courier,tostring(slot)},":") or "unknown";
    if key==s.stockKey then return end;s.stockKey=key;
    if not d then emit(bot,s,"vision_supply_state",{known=false,slot=slot});return end;
    local data={known=true,slot=slot,window_start=deadline,active=d.active,active_castable=d.active_castable,
        backpack=d.backpack,stash=d.stash,courier=d.courier,total=d.total,
        before_window=deadline and U.Now()<deadline or false,evidence="own_inventory_and_courier_readback"};
    emit(bot,s,"vision_supply_state",data);
    if d.active>0 and s.previousActive==0 and slot~=nil then emit(bot,s,"vision_delivery_observed",data) end;
    s.previousActive=d.active;
end;
function M.DeliveryNeeded(bot)
    if not phaseProfile(bot) or U.Call(bot,"IsAlive")~=true or Schedule.Stopped(U.Now(),B.State(bot)) then return nil end;
    local s=state(bot);local request=Schedule.Request(U.Now(),B.State(bot));
    if not request and s and s.target_slot~=nil then request={slot=s.target_slot,start=s.target_start} end;
    if not request then return nil end;
    local d=M.StockDetails(bot);
    if not d or d.stash<=0 or d.active+d.backpack+d.courier>0 then return nil end;
    return {slot=request.slot,window_start=request.start,reason="scheduled_observer_in_stash"};
end;
function M.ReturningCourierRequest(bot,courier,mode)
    if COURIER_STATE_RETURNING_TO_BASE==nil or mode~=COURIER_STATE_RETURNING_TO_BASE
        or U.Call(courier,"GetPlayerID")~=U.Call(bot,"GetPlayerID") then return nil end;
    local request=M.DeliveryNeeded(bot);if not request then return nil end;
    local s=state(bot);if U.Now()<(s.nextWardCourier or -math.huge) then return nil end;
    local hp,max=U.Call(courier,"GetHealth"),U.Call(courier,"GetMaxHealth");
    local distance=U.Call(courier,"DistanceFromFountain");
    local reason;
    if U.Call(courier,"IsAlive")~=true then reason="courier_not_alive"
    elseif not U.Number(hp) or not U.Number(max) or max<=0 or not U.Number(distance) or distance<0 then reason="courier_health_or_base_distance_unknown"
    elseif hp/max<C.courier_min_hp then reason="courier_low_health"
    elseif distance>C.courier_near_base then reason="returning_courier_not_near_base" end;
    if reason then
        if s.courierWaitReason~=reason then emit(bot,s,"vision_courier_wait",{reason=reason,slot=request.slot,courier_state=mode,distance_from_base=distance});s.courierWaitReason=reason end;
        return nil;
    end;
    s.courierWaitReason=nil;return request;
end;
function M.DeliveryAttempt(bot,mode,ok,accepted,courier)
    local request=M.DeliveryNeeded(bot);if not request then return end;
    local s=state(bot);s.nextWardCourier=U.Now()+C.courier_retry_s;
    emit(bot,s,"vision_courier_attempt",{slot=request.slot,window_start=request.window_start,courier_state=mode,
        api_returned=ok,api_rejected=accepted==false,distance_from_base=U.Call(courier,"DistanceFromFountain"),outcome="delivery_unverified"});
end;
function M.PurchaseStatus(bot)
    local s=state(bot);if not s then return {available=false,reason="clock_unknown"} end;
    if s.shopAt==U.Now() then return s.shopStatus end;
    local stock=U.Global("GetItemStockCount","item_ward_observer");
    local cost=U.Global("GetItemCost","item_ward_observer");local gold=U.Call(bot,"GetGold");
    local out={stock=stock,cost=cost,gold=gold,available=false};
    if not U.Number(stock) or stock<0 then out.reason="shop_stock_unknown"
    elseif stock<1 then out.reason="shop_out_of_stock"
    elseif not U.Number(cost) or cost<0 or not U.Number(gold) then out.reason="shop_cost_or_gold_unknown"
    elseif gold<cost then out.reason="shop_not_affordable"
    else out.available=true;out.reason="available" end;
    s.shopAt=U.Now();s.shopStatus=out;return out;
end;
function M.TryPurchase(bot)
    if C.calibration_only==true then return false end;
    local phase=phaseProfile(bot);local ctx,why;
    if phase then
        local now=U.Now();if now and now>=-90 and not Schedule.Stopped(now,B.State(bot)) then ctx={now=now} end;
    else ctx,why=Site.Context(bot) end;
    if not ctx or ctx.now < -90 then return false end;
    local broker=B.State(bot);local s=state(bot);
    local request=phase and Schedule.Request(ctx.now,broker) or nil;
    if phase and (not request or Schedule.Completed(broker,request)) then return false end;
    if ctx.now<(s.nextCheck or -math.huge) then return false end;s.nextCheck=phase and math.min(ctx.now+1,Schedule.NextCheck(ctx.now)) or ctx.now+1;
    local spot,reason;if phase then spot,reason=Site.Geometry(bot) else spot,reason=Site.Get(bot) end;if not spot then
        if reason~=s.reason then emit(bot,s,"vision_supply_skip",{reason=reason or "site_unknown"});s.reason=reason end;return false;
    end;
    local count=supply(bot);if count==nil then return false end;
    if count>0 then s.pending=nil;return false end;
    local ward,unknown=Site.Existing(spot);if unknown then return false end;
    if ward then
        if phase then if not M.CanReplace(bot,ward,request) then return false end;
        elseif ward.handle~=s.ward or not s.expires or s.expires-ctx.now>C.refresh_lead_s then return false end;
    end;
    if s.pending then
        if ctx.now-s.pending>C.pending_timeout_s and not s.pendingReported then
            emit(bot,s,"vision_supply_unknown",{reason="purchase_not_observed_no_duplicate",since=s.pending});s.pendingReported=true;
        end;return false;
    end;
    if ctx.now<(s.nextBuy or -math.huge) then return false end;
    if PURCHASE_ITEM_SUCCESS==nil or type(GetItemCost)~="function" then return false end;
    if phase then
        local status=M.PurchaseStatus(bot);
        if not status.available then
            s.nextBuy=Schedule.NextCheck(ctx.now);
            emit(bot,s,"vision_supply_wait",{reason=status.reason,stock=status.stock,slot=request.slot,next_check=s.nextBuy});
            if broker.vision_recovery_purchase then broker.vision_recovery_purchase.authorized=false end;
            return false;
        end;
    else
        local cost=U.Global("GetItemCost","item_ward_observer");local gold=U.Call(bot,"GetGold");
        if not U.Number(cost) or cost<0 or not U.Number(gold) or gold<cost then return false end;
    end;
    s.nextBuy=phase and Schedule.NextCheck(ctx.now) or ctx.now+C.purchase_retry_s;s.pending=ctx.now;s.pendingReported=false;
    if request then s.target_slot=request.slot;s.target_start=request.start end;
    if phase and broker.vision_recovery_purchase then broker.vision_recovery_purchase.authorized=false end;
    local ok,result=pcall(function() return bot:ActionImmediate_PurchaseItem("item_ward_observer") end);
    if ok and U.Number(result) and result~=PURCHASE_ITEM_SUCCESS then s.pending=nil end;
    emit(bot,s,"vision_supply_purchase",{item="item_ward_observer",api_returned=ok,result=result,
        reason=request and (request.kind.."_window_supply") or (ward and "expiry_soon" or "missing_fixed_observer"),slot=request and request.slot,outcome="delivery_unverified"});
    return true;
end;
return M;
