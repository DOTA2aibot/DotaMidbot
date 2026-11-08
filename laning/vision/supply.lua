local U=require(GetScriptDirectory().."/laning/tactical/util");
local C=require(GetScriptDirectory().."/laning/vision/config");
local Site=require(GetScriptDirectory().."/laning/vision/site");
local B=require(GetScriptDirectory().."/laning/tactical/broker");
local M,states={},setmetatable({}, {__mode="k"});
local function state(bot)
    local now=U.Now();local s=states[bot];if not now then return nil end;
    if not s or now<(s.time or now) then s={};states[bot]=s end;s.time=now;return s;
end;
local function emit(bot,s,kind,data) B.Emit(B.State(bot),kind,data) end;
function M.Placed(bot,ward,spot)
    local s=state(bot);if not s then return end;
    s.ward=ward;s.expires=U.Now()+C.duration_s;s.pending=nil;
    emit(bot,s,"vision_lifetime",{location=spot.location,expires_at=s.expires,duration_s=C.duration_s,evidence="placement_confirmed"});
end;
local function supply(bot)
    local count=0;
    local function slots(unit,last)
        if type(unit.GetItemInSlot)~="function" then return false end;
        for slot=0,last do
            local item=U.Call(unit,"GetItemInSlot",slot);local name=U.Call(item,"GetName");
            if item~=nil and type(name)~="string" then return false end;
            if name=="item_ward_observer" or name=="item_ward_dispenser" then
                local n=U.Call(item,"GetCurrentCharges");if not U.Number(n) or n<0 then return false end;
                count=count+n;
            end;
        end;return true;
    end;
    if not slots(bot,14) then return nil end;
    local n=U.Global("GetNumCouriers");local id=U.Call(bot,"GetPlayerID");
    if not U.Number(n) or n<0 or not U.Number(id) then return nil end;
    for i=0,n-1 do
        local courier=U.Global("GetCourier",i);local owner=U.Call(courier,"GetPlayerID");
        if owner==nil then return nil end;
        if owner==id and not slots(courier,8) then return nil end;
    end;
    return count;
end;
function M.TryPurchase(bot)
    local ctx,why=Site.Context(bot);
    if not ctx or ctx.now < -90 then
        if Site.Radiant(bot) then local s=state(bot);local reason=why or "before_pregame_window";
            if s and s.contextReason~=reason then emit(bot,s,"vision_supply_skip",{reason=reason});s.contextReason=reason end;
        end;
        return false;
    end;
    local s=state(bot);if ctx.now<(s.nextCheck or -math.huge) then return false end;s.nextCheck=ctx.now+1;
    s.contextReason=nil;
    local spot,reason=Site.Get(bot);if not spot then
        if reason~=s.reason then emit(bot,s,"vision_supply_skip",{reason=reason});s.reason=reason end;return false;
    end;
    local count=supply(bot);if count==nil then return false end;
    if count>0 then s.pending=nil;return false end;
    local ward,unknown=Site.Existing(spot);if unknown then return false end;
    if ward and (ward.handle~=s.ward or not s.expires or s.expires-ctx.now>C.refresh_lead_s) then return false end;
    if s.pending then
        if ctx.now-s.pending>C.pending_timeout_s and not s.pendingReported then
            emit(bot,s,"vision_supply_unknown",{reason="purchase_not_observed_no_duplicate",since=s.pending});s.pendingReported=true;
        end;return false;
    end;
    if ctx.now<(s.nextBuy or -math.huge) then return false end;
    if PURCHASE_ITEM_SUCCESS==nil or type(GetItemCost)~="function" then return false end;
    local cost=U.Global("GetItemCost","item_ward_observer");local gold=U.Call(bot,"GetGold");
    if not U.Number(cost) or cost<0 or not U.Number(gold) or gold<cost then return false end;
    s.nextBuy=ctx.now+C.purchase_retry_s;s.pending=ctx.now;s.pendingReported=false;
    local ok,result=pcall(function() return bot:ActionImmediate_PurchaseItem("item_ward_observer") end);
    -- Unknown/exception can happen after a side effect; keep the pending guard.
    if ok and U.Number(result) and result~=PURCHASE_ITEM_SUCCESS then s.pending=nil end;
    emit(bot,s,"vision_supply_purchase",{item="item_ward_observer",api_returned=ok,result=result,
        reason=ward and "expiry_soon" or "missing_fixed_observer",outcome="delivery_unverified"});
    return true;
end;
return M;
