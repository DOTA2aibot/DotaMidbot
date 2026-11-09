-- Explicit personal ITEM mode: nearby ground pickups only, never a courier rendezvous.
local U=require(GetScriptDirectory().."/laning/tactical/util");
local B=require(GetScriptDirectory().."/laning/tactical/broker");
local Profile=require(GetScriptDirectory().."/laning/profile");
local M={};
local RADIUS=160;
function M.Enabled(bot)
    return Profile.stationary_delivery_enabled==true and Profile.runtime_enabled~=true and U.Actor(bot);
end;
local function carried(bot,item)
    for i=0,8 do if U.Call(bot,"GetItemInSlot",i)==item then return true end end;return false;
end;
local function safe(bot,s)
    if not M.Enabled(bot) or not U.CanUse(bot) or s.vision_phase or s.ward_pending then return false end;
    local mode=U.Call(bot,"GetActiveMode");
    if mode==nil or mode==BOT_MODE_RETREAT or mode==BOT_MODE_ATTACK or mode==BOT_MODE_RUNE
        or (BOT_MODE_EVASIVE_MANEUVERS~=nil and mode==BOT_MODE_EVASIVE_MANEUVERS) then return false end;
    local action=U.Call(bot,"GetCurrentActionType");
    local ownedPickup=s.delivery_pickup and BOT_ACTION_TYPE_PICK_UP_ITEM~=nil and action==BOT_ACTION_TYPE_PICK_UP_ITEM;
    if not ownedPickup and action~=BOT_ACTION_TYPE_IDLE and action~=BOT_ACTION_TYPE_NONE and action~=BOT_ACTION_TYPE_MOVE_TO then return false end;
    local hp=U.HP(bot);local recent=U.Call(bot,"TimeSinceDamagedByAnyHero");
    if not hp or hp<.65 or not U.Number(recent) or recent<4 then return false end;
    local heroes=U.Call(bot,"GetNearbyHeroes",1000,true,BOT_MODE_NONE);
    local towers=U.Call(bot,"GetNearbyTowers",1000,true);
    local creeps=U.Call(bot,"GetNearbyLaneCreeps",700,true);
    if type(heroes)~="table" or type(towers)~="table" or type(creeps)~="table" then return false end;
    for _,list in ipairs({heroes,towers,creeps}) do for _,e in ipairs(list) do if U.Visible(e) then return false end end end;
    local empty=false;
    if type(bot.GetItemInSlot)~="function" then return false end;
    for i=0,8 do local ok,it=pcall(bot.GetItemInSlot,bot,i);if not ok then return false end;if it==nil then empty=true end end;
    return empty;
end;
local function candidate(bot,s,wanted)
    if not safe(bot,s) or U.Now()<(s.delivery_pickup_retry or -math.huge) then return nil end;
    local drops=U.Global("GetDroppedItemList");if type(drops)~="table" then return nil end;
    local nearest;
    for _,drop in pairs(drops) do if type(drop)=="table" then
        local it=drop.item;local p=U.Point(drop.location);local name=U.Call(it,"GetName");
        local distance=U.Distance(U.Pos(bot),p);
        -- Public dropped Rapier remains recoverable; no theft of allied dropped consumables.
        if (not wanted or it==wanted) and U.Call(it,"IsNull")==false and U.Call(it,"IsItem")==true
            and type(name)=="string" and name:sub(1,5)=="item_"
            and (drop.owner==bot or name=="item_rapier") and p
            and U.Global("IsLocationVisible",U.Vector(p))==true and distance<=RADIUS
            and not carried(bot,it) and (not nearest or distance<nearest.distance) then
            nearest={item=it,location=p,distance=distance,name=name};
        end;
    end end;return nearest;
end;
function M.Leave(bot,reason)
    local s=B.State(bot);if not s or not s.delivery_pickup then return end;
    B.Emit(s,"ground_pickup_end",{reason=reason or "mode_ended"});s.delivery_pickup=nil;
    s.delivery_pickup_retry=U.Now()+2;
end;
function M.GetDesire(bot)
    if not M.Enabled(bot) or BOT_MODE_ITEM==nil then return 0 end;
    local s=B.State(bot);if not s then return 0 end;
    local p=s.delivery_pickup;
    if p then
        if carried(bot,p.item) then M.Leave(bot,"inventory_readback");return 0 end;
        if U.Now()>=p.deadline or not candidate(bot,s,p.item) then M.Leave(bot,"unsafe_missing_or_timeout");return 0 end;
        return .25;
    end;
    return candidate(bot,s) and .25 or 0;
end;
function M.Start(bot)
    if not M.Enabled(bot) then return end;
    local s=B.State(bot);if not s then return end;local p=candidate(bot,s);if not p then return end;
    p.deadline=U.Now()+3;p.tries=0;s.delivery_pickup=p;
    B.Emit(s,"ground_pickup_start",{item=p.name,distance=p.distance,policy="nearby_ground_only_no_courier_target"});
end;
function M.Think(bot)
    if not M.Enabled(bot) then return end;
    local s=B.State(bot);local p=s and s.delivery_pickup;if not p then return end;
    if carried(bot,p.item) then M.Leave(bot,"inventory_readback");return end;
    if U.Call(bot,"GetActiveMode")~=BOT_MODE_ITEM or U.Now()>=p.deadline or not candidate(bot,s,p.item) then M.Leave(bot,"preempted_unsafe_missing_or_timeout");return end;
    if U.Now()<(p.next_attempt or -math.huge) or p.tries>=2 or type(bot.Action_PickUpItem)~="function" then return end;
    if not B.Free(s) then return end;
    p.tries=p.tries+1;p.next_attempt=U.Now()+1;
    B.Fire(bot,s,"ground_pickup",p.item,"within_160_no_courier_rendezvous",function() return bot:Action_PickUpItem(p.item) end,false);
end;
-- Observation only. A decreasing distance is not evidence of a hero rendezvous order.
function M.Observe(bot,s)
    if not M.Enabled(bot) or not s or U.Now()<(s.delivery_next_sample or -math.huge) then return end;
    s.delivery_next_sample=U.Now()+1;
    local n=U.Global("GetNumCouriers");if not U.Number(n) or n<0 then return end;
    for i=0,n-1 do local c=U.Global("GetCourier",i);
        if U.Call(c,"GetPlayerID")==U.Call(bot,"GetPlayerID") then
            local cargo=0;local known=type(c.GetItemInSlot)=="function";
            if known then for slot=0,8 do local ok,it=pcall(c.GetItemInSlot,c,slot);if not ok then known=false end;if it then cargo=cargo+1 end end end;
            local state=U.Global("GetCourierState",c);
            if not known or cargo>0 or (COURIER_STATE_DELIVERING_ITEMS~=nil and state==COURIER_STATE_DELIVERING_ITEMS) then
                B.Emit(s,"courier_trajectory",{hero_location=U.Pos(bot),courier_location=U.Pos(c),distance=U.Pos(bot) and U.Pos(c) and U.Distance(U.Pos(bot),U.Pos(c)) or nil,
                    courier_state=state,cargo_known=known,cargo_slots=known and cargo or nil,hero_mode=U.Call(bot,"GetActiveMode"),
                    hero_action=U.Call(bot,"GetCurrentActionType"),policy="personal_item_mode_never_targets_courier"});
            end;
        end;
    end;
end;
return M;
