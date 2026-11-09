local U=require(GetScriptDirectory().."/laning/tactical/util");
local B=require(GetScriptDirectory().."/laning/tactical/broker");
local C=require(GetScriptDirectory().."/laning/vision/config");
local P=require(GetScriptDirectory().."/laning/profile");
local T=require(GetScriptDirectory().."/laning/tactical/config");
local Site=require(GetScriptDirectory().."/laning/vision/site");
local I=require(GetScriptDirectory().."/laning/vision/ward_items");
local Idle=require(GetScriptDirectory().."/laning/vision/idle");
local M={};local derivedPoint;
local function state(bot)
    local s=B.State(bot);if not s then return end;
    s.sentry=s.sentry or {completed={}};return s.sentry,s;
end;
function M.Enabled(bot)
    return T.enabled==true and T.wards==true and C.support_enabled and Site.Participant(bot) and P.wards_enabled==true and P.ward_phase_enabled==true
        and P.runtime_enabled~=true and C.calibration_only~=true;
end;
function M.Point()
    local fixed=U.Point(C.sentry_fixed_location);if fixed then return fixed end;
    if not C.sentry_use_rune_midpoint or RUNE_POWERUP_1==nil or RUNE_POWERUP_2==nil then return nil,"sentry_coordinate_unavailable" end;
    if derivedPoint then return derivedPoint end;
    local a=U.Point(U.Global("GetRuneSpawnLocation",RUNE_POWERUP_1));
    local b=U.Point(U.Global("GetRuneSpawnLocation",RUNE_POWERUP_2));
    if not a or not b or U.Distance(a,b)<100 then return nil,"rune_landmarks_unavailable" end;
    local p={x=(a.x+b.x)/2,y=(a.y+b.y)/2,z=0};
    if U.Global("GetHeightLevel",U.Vector(p))~=1 or U.Global("IsLocationPassable",U.Vector(p))~=true then return nil,"midpoint_not_walkable_river" end;
    local ground=U.Global("GetGroundHeight",U.Vector(p));if U.Number(ground) then p.z=ground end;
    derivedPoint=p;return p;
end;
local function nextCheck(now) return math.floor(now/60)*60+45+(now%60>=45 and 60 or 0) end;
local function primary(now,prefetch)
    for i,w in ipairs(C.sentry_windows) do
        if now>=w.start-(prefetch and C.prefetch_s or 0) and now<=w.finish then
            return {key="sentry:"..i,start=w.start,finish=w.finish,primary=true};
        end;
    end;
end;
local function window(now,s,prefetch)
    if now>=C.recovery_end_s then return end;
    local w=primary(now,prefetch);if w and not s.completed[w.key] then return w end;
    w=s.recovery;if w and now<=w.finish and (prefetch or now>=w.start) then return w end;
end;
M.Stock=function(bot) return I.Stock(bot,"sentry") end;
function M.StartupAttempt(bot,result)
    local s,b=state(bot);if not s then return end;
    if not U.Number(result) or (PURCHASE_ITEM_SUCCESS~=nil and result==PURCHASE_ITEM_SUCCESS) then s.pending=U.Now()
    else s.buy_after=nextCheck(U.Now()) end;
    B.Emit(b,"sentry_startup_purchase",{result=result,location=M.Point(),coordinate_source=C.sentry_fixed_location and "fixed" or "river_rune_midpoint",outcome="unverified"});
end;
function M.TryStartup(bot)
    if not M.Enabled(bot) then return false end;
    local s=state(bot);local now=U.Now();if not s or not now or s.startup_resolved then return false end;
    if now>30 then s.startup_resolved=true;return false end;
    if now< -90 or now<(s.startup_after or -math.huge) then return false end;
    local stock=I.Stock(bot,"sentry");if not stock then s.startup_after=nextCheck(now);return false end;
    if stock.total>0 then s.startup_resolved=true;return false end;
    local count=U.Global("GetItemStockCount","item_ward_sentry");local cost=U.Global("GetItemCost","item_ward_sentry");local gold=U.Call(bot,"GetGold");
    s.startup_resolved=true;
    if not U.Number(count) or count<1 or not U.Number(cost) or cost<0 or not U.Number(gold) or gold<cost or PURCHASE_ITEM_SUCCESS==nil then
        s.buy_after=nextCheck(now);return false;
    end;
    local ok,result=pcall(function() return bot:ActionImmediate_PurchaseItem("item_ward_sentry") end);
    M.StartupAttempt(bot,ok and result or nil);return true;
end;
function M.Check(bot)
    if not M.Enabled(bot) then return end;
    local now=U.Now();local s,b=state(bot);if not now or not s then return end;
    if now>=C.recovery_end_s then s.recovery=nil;return end;
    local p,pointReason=M.Point();local pointKey=p and (p.x..":"..p.y) or pointReason;
    if s.pointKey~=pointKey then
        s.pointKey=pointKey;B.Emit(b,"sentry_site_state",{known=p~=nil,location=p,reason=pointReason,
            source=C.sentry_fixed_location and "fixed" or "river_rune_midpoint"});
    end;
    if not p then return end;
    local stock=I.Stock(bot,"sentry");if stock and stock.total>0 then s.pending=nil end;
    if now<45 then return end;
    local minute=math.floor(now/60);if now<minute*60+45 or s.checked==minute then return end;s.checked=minute;
    local wards,unknown=I.Allied("sentry",p,C.dedup_radius);s.recovery=nil;
    local nextMinute=(minute+1)*60;
    if wards and #wards==0 and nextMinute<C.recovery_end_s then s.recovery={key="sentry-recovery:"..nextMinute,start=nextMinute,finish=nextMinute+30} end;
    B.Emit(b,"sentry_recovery_check",{present=wards and #wards>0 or false,known=wards~=nil,reason=unknown,
        active=stock and stock.active,carried=stock and stock.backpack,stash=stock and stock.stash,courier=stock and stock.courier,
        next_check=(minute+1)*60+45,next_window=s.recovery and s.recovery.start});
end;
function M.TryPurchase(bot)
    M.Check(bot);if not M.Enabled(bot) or not M.Point() then return false end;
    local s,b=state(bot);local now=U.Now();if not s or not now or now< -90 or now>=C.recovery_end_s then return false end;
    local w=window(now,s,true);if not w or now<(s.buy_after or -math.huge) then return false end;
    local stock=I.Stock(bot,"sentry");if not stock then return false end;
    if stock.total>0 then s.pending=nil;return false end;
    if s.pending then return false end;
    local wards=I.Allied("sentry",M.Point(),C.dedup_radius);
    if not wards or (#wards>0 and not (w.primary and w.start>0)) then return false end;
    local count=U.Global("GetItemStockCount","item_ward_sentry");local cost=U.Global("GetItemCost","item_ward_sentry");local gold=U.Call(bot,"GetGold");
    s.buy_after=nextCheck(now);
    if not U.Number(count) or count<1 or not U.Number(cost) or cost<0 or not U.Number(gold) or gold<cost then
        B.Emit(b,"sentry_supply_wait",{stock=count,cost=cost,gold=gold,next_check=s.buy_after});return false;
    end;
    if PURCHASE_ITEM_SUCCESS==nil then return false end;
    s.pending=now;
    local ok,result=pcall(function() return bot:ActionImmediate_PurchaseItem("item_ward_sentry") end);
    if ok and U.Number(result) and result~=PURCHASE_ITEM_SUCCESS then s.pending=nil end;
    B.Emit(b,"sentry_supply_purchase",{result=result,api_returned=ok,window_start=w.start,outcome="unverified"});return true;
end;
function M.Candidate(bot)
    M.Check(bot);if not M.Enabled(bot) then return end;
    local s,b=state(bot);local now=U.Now();local p=M.Point();if not s or not now or not p then return end;
    local function skip(reason)
        if s.skipReason~=reason then s.skipReason=reason;B.Emit(b,"sentry_plan_skip",{reason=reason}) end;
    end;
    local w=window(now,s,false);if not w then return skip("outside_or_completed_window") end;
    if s.deferred_window==w.key then return skip("deferred_to_next_window") end;
    local wards=I.Allied("sentry",p,C.dedup_radius);
    if not wards then return skip("allied_ward_api_unknown") end;
    if #wards>0 and not (w.primary and w.start>0) then return skip("sentry_already_present") end;
    local idle,why=Idle.Check(bot,p);if not idle then return skip(why) end;
    local height=U.Global("GetHeightLevel",U.Vector(p));
    if not U.Number(height) or height>1 or U.Global("IsLocationPassable",U.Vector(p))~=true then return skip("invalid_river_point") end;
    local item=I.Find(bot,"sentry");local stored=false;
    if not item then item=I.Find(bot,"sentry",6,8);stored=item~=nil end;
    local range=U.Call(item,"GetCastRange");
    if not item or (not stored and not U.Ready(item)) or not U.Number(range) or range<=25
        or U.Distance(U.Pos(bot),p)>range-25+C.support_max_approach then return skip("item_unready_or_approach_out_of_range") end;
    s.skipReason=nil;
    return {kind="sentry",location=p,window=w,item=item,range=range,prior=wards,started=now,deadline=math.min(now+C.support_max_s,w.finish)};
end;
function M.Defer(bot,job)
    local s=state(bot);if s and job then s.deferred_window=job.window.key end;
end;
local function equip(bot,b)
    local item=I.Find(bot,"sentry");if item then return item end;
    local stored,slot=I.Find(bot,"sentry",6,8);if not stored or type(bot.ActionImmediate_SwapItems)~="function" then return end;
    if b.vision_swap or b.support_swap then return end;
    local passives={item_branches=true,item_wraith_band=true,item_band_of_elvenskin=true,item_belt_of_strength=true,
        item_blade_of_alacrity=true,item_circlet=true,item_slippers=true,item_gloves=true};
    local target,displaced;
    for i=0,5 do if U.Call(bot,"GetItemInSlot",i)==nil then target=i;break end end;
    if not target then for i=0,5 do local it=U.Call(bot,"GetItemInSlot",i);if passives[U.Call(it,"GetName")] then target=i;displaced=it;break end end end;
    if target~=nil then
        local done=B.Fire(bot,b,"sentry_equip",stored,"safe_active_slot",function() return bot:ActionImmediate_SwapItems(slot,target) end,false);
        if done and U.Call(bot,"GetItemInSlot",target)==stored and displaced then b.support_swap={active=target,backpack=slot,displaced=displaced} end;
    end;
end;
function M.Restore(bot,b)
    local swap=b.support_swap;if not swap or not B.Free(b) or b.vision_support or b.vision_phase or not U.CanUse(bot) then return false end;
    local active=U.Call(bot,"GetItemInSlot",swap.active);local count=I.Charges(active,"sentry");
    if count==0 and (I.Charges(active,"observer") or 0)==0 and U.Call(bot,"GetItemInSlot",swap.backpack)==swap.displaced then
        b.support_swap=nil;return B.Fire(bot,b,"sentry_inventory_restore",nil,"restore_passive_after_sentry",function()
            return bot:ActionImmediate_SwapItems(swap.backpack,swap.active);
        end,false);
    end;return false;
end;
function M.Execute(bot,b,job)
    if job.pending then return end;
    local item=equip(bot,b);if not B.Free(b) or not U.Ready(item) then return end;
    job.item=item;job.range=U.Call(item,"GetCastRange");if not U.Number(job.range) then return end;
    local name=U.Call(item,"GetName");
    if name=="item_ward_dispenser" then
        local toggle=U.Call(item,"GetToggleState");if type(toggle)~="boolean" then return end;
        if toggle then
            if (job.toggles or 0)>=2 or U.Now()<(job.toggle_after or -math.huge) then return end;
            job.toggles=(job.toggles or 0)+1;job.toggle_after=U.Now()+.5;
            B.Fire(bot,b,"ward_mode_toggle",item,"select_sentry",function() return bot:Action_UseAbility(item) end,false);return;
        end;
    end;
    if U.Distance(U.Pos(bot),job.location)>job.range-25 then Idle.Step(bot,b,job.location,job.range-25,"sentry_window");return end;
    job.before=I.Charges(item,"sentry");job.prior=I.Allied("sentry",job.location,C.dedup_radius);
    if not job.before or job.before<1 or not job.prior then return end;
    if B.Fire(bot,b,"ward",item,"scheduled_sentry",function() return bot:Action_UseAbilityOnLocation(item,U.Vector(job.location)) end,false) then job.pending=U.Now() end;
end;
function M.Poll(bot,b,job)
    if not job or not job.pending then return false end;
    local wards=I.Allied("sentry",job.location,C.dedup_radius);
    for _,w in ipairs(wards or {}) do
        local old=false;for _,p in ipairs(job.prior) do if p.handle==w.handle then old=true end end;
        if not old and U.Call(w.handle,"GetPlayerID")==U.Call(bot,"GetPlayerID") then
            local charges=I.Charges(job.item,"sentry");local consumed=false;
            if not charges and job.before==1 then
                local known,present=true,false;for slot=0,5 do local ok,it=pcall(function() return bot:GetItemInSlot(slot) end);known=known and ok;present=present or it==job.item end;
                consumed=known and not present;
            end;
            if (charges and charges<job.before) or consumed then
                local s=state(bot);s.completed[job.window.key]=true;s.pending=nil;s.recovery=nil;
                B.Emit(b,"sentry_placement_observed",{location=w.location,expires_at=U.Now()+C.sentry_duration_s,evidence="new_owned_ward_and_charge_consumed"});return true;
            end;
        end;
    end;return false;
end;
return M;
