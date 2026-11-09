-- One read-only check per minute at:45. Purchase execution remains in supply/root purchase.
local U=require(GetScriptDirectory().."/laning/tactical/util");
local B=require(GetScriptDirectory().."/laning/tactical/broker");
local C=require(GetScriptDirectory().."/laning/vision/config");
local T=require(GetScriptDirectory().."/laning/tactical/config");
local Profile=require(GetScriptDirectory().."/laning/profile");
local Site=require(GetScriptDirectory().."/laning/vision/site");
local Supply=require(GetScriptDirectory().."/laning/vision/supply");
local Schedule=require(GetScriptDirectory().."/laning/vision/schedule");
local M={};
function M.Poll(bot,s)
    if not s or not Site.Radiant(bot) or C.calibration_only or not T.enabled or not T.wards
        or Profile.wards_enabled~=true or Profile.ward_phase_enabled~=true or Profile.runtime_enabled==true then return end;
    local now=U.Now();if not now or now<45 then return end;
    if Schedule.Stopped(now,s) then
        s.vision_recovery=nil;s.vision_recovery_purchase=nil;
        if not s.vision_stop_reported then B.Emit(s,"ward_recovery_stopped",{reason=s.vision_final_ward and "final_placement_confirmed" or "twelve_minute_limit"});s.vision_stop_reported=true end;
        return;
    end;
    local minute=math.floor(now/60);local due=minute*60+45;
    if now<due or s.vision_checked_minute==minute then return end;
    s.vision_checked_minute=minute;
    local nextWindow=Schedule.NextWindow(now);
    local data={check_at=now,next_check=due+60,next_window=nextWindow and nextWindow.start};
    local spot,why=Site.Geometry();local exists,unknown;
    if spot then exists,unknown=Site.Existing(spot) else unknown=why or "geometry_unknown" end;
    local stock=Supply.StockDetails(bot);
    s.vision_recovery_purchase=nil;
    if unknown then data.reason=unknown;s.vision_recovery=nil;
    elseif exists then data.reason="coverage_present";data.coverage=true;s.vision_recovery=nil;
    elseif not nextWindow then data.reason="no_window_before_limit";s.vision_recovery=nil;
    elseif not stock then data.reason="owned_stock_unknown";s.vision_recovery=nil;
    elseif stock.active+stock.backpack>0 then
        data.reason="recovery_window_scheduled";data.coverage=false;s.vision_recovery=nextWindow;
        s.vision_recovery_history=s.vision_recovery_history or {};
        if nextWindow.kind=="recovery" and not s.vision_recovery_keys then s.vision_recovery_keys={} end;
        if nextWindow.kind=="recovery" and not s.vision_recovery_keys[nextWindow.key] then
            s.vision_recovery_keys[nextWindow.key]=true;s.vision_recovery_history[#s.vision_recovery_history+1]=nextWindow;
        end;
    elseif stock.total>0 then data.reason="already_in_stash_or_courier";s.vision_recovery=nil;
    else
        s.vision_recovery=nil;local shop=Supply.PurchaseStatus(bot);
        data.reason=shop.available and "purchase_authorized_wait_next_check" or shop.reason;data.shop_stock=shop.stock;
        s.vision_recovery_purchase={window=nextWindow,authorized=shop.available,expires=due+60};
    end;
    if stock then data.active=stock.active;data.backpack=stock.backpack;data.stash=stock.stash;data.courier=stock.courier end;
    B.Emit(s,"ward_recovery_check",data);
end;
return M;
