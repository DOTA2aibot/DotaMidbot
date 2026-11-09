-- Only equip/restore the Observer; no general inventory cleanup or selling.
local U=require(GetScriptDirectory().."/laning/tactical/util");
local Site=require(GetScriptDirectory().."/laning/vision/site");
local C=require(GetScriptDirectory().."/laning/vision/config");
local Tactical=require(GetScriptDirectory().."/laning/tactical/config");
local B=require(GetScriptDirectory().."/laning/tactical/broker");
local Supply=require(GetScriptDirectory().."/laning/vision/supply");
local Phase=require(GetScriptDirectory().."/laning/vision/phase");
local Schedule=require(GetScriptDirectory().."/laning/vision/schedule");
local M={};
local passives={item_branches=true,item_wraith_band=true,item_band_of_elvenskin=true,
    item_belt_of_strength=true,item_blade_of_alacrity=true,item_circlet=true,
    item_slippers=true,item_gloves=true};
local function observer(item)
    local name=U.Call(item,"GetName");local n=U.Call(item,"GetCurrentCharges");
    return (name=="item_ward_observer" or name=="item_ward_dispenser") and U.Number(n) and n>0;
end;
local function safe(bot)
    if not U.CanUse(bot) then return false end;
    if not U.HP(bot) or U.HP(bot)<Tactical.ward_min_hp then return false end;
    local mode=U.Call(bot,"GetActiveMode");
    if mode==nil or mode==BOT_MODE_ATTACK or mode==BOT_MODE_RETREAT
        or (BOT_MODE_RUNE~=nil and mode==BOT_MODE_RUNE)
        or (BOT_MODE_EVASIVE_MANEUVERS~=nil and mode==BOT_MODE_EVASIVE_MANEUVERS) then return false end;
    local action=U.Call(bot,"GetCurrentActionType");
    if action~=BOT_ACTION_TYPE_IDLE and action~=BOT_ACTION_TYPE_NONE and action~=BOT_ACTION_TYPE_MOVE_TO then return false end;
    local recent=U.Call(bot,"TimeSinceDamagedByAnyHero");if not U.Number(recent) or recent<C.recent_damage_s then return false end;
    local enemies=U.Call(bot,"GetNearbyHeroes",1100,true,BOT_MODE_NONE);
    local towers=U.Call(bot,"GetNearbyTowers",1599,true);
    if type(enemies)~="table" or type(towers)~="table" then return false end;
    for _,e in ipairs(enemies) do if U.Visible(e) then return false end end;
    for _,t in ipairs(towers) do if U.Visible(t) then
        local range=U.Call(t,"GetAttackRange");if not U.Number(range) or U.Distance(U.Pos(t),U.Pos(bot))<=range+150 then return false end;
    end end;return true;
end;
function M.Tick(bot,s)
    if not Site.Radiant(bot) or not B.Free(s) or not safe(bot) or type(bot.ActionImmediate_SwapItems)~="function" then return false end;
    local previous=s.vision_swap;
    if previous then
        local active=U.Call(bot,"GetItemInSlot",previous.active);
        local stored=U.Call(bot,"GetItemInSlot",previous.backpack);
        if not observer(active) then
            s.vision_swap=nil;
            if active==nil and stored==previous.displaced then
                return B.Fire(bot,s,"vision_restore",nil,"restore_passive_after_ward",function()
                    return bot:ActionImmediate_SwapItems(previous.backpack,previous.active);
                end,false);
            end;
        end;
        return false;
    end;
    if not Site.Context(bot) or U.Now()<(s.next_vision_swap or -math.huge) then return false end;
    if Phase.Enabled(bot) and (Schedule.Slot(U.Now())==nil or s.vision_done_slot==Schedule.Slot(U.Now())
        ) then return false end;
    for slot=0,5 do if observer(U.Call(bot,"GetItemInSlot",slot)) then return false end end;
    local spot=Site.Get(bot);if not spot then return false end;
    local exists,unknown=Site.Existing(spot);
    if unknown or (exists and not Supply.CanReplace(bot,exists,Schedule.Slot(U.Now()))) then return false end;
    local source,item;
    for slot=6,8 do local candidate=U.Call(bot,"GetItemInSlot",slot);if observer(candidate) then source,item=slot,candidate;break end end;
    if not item then return false end;
    local range=U.Call(item,"GetCastRange");
    if not U.Number(range) or U.Distance(U.Pos(bot),spot.location)>range-25+(Phase.Enabled(bot) and C.phase_max_approach or 0) then return false end;
    local target,displaced;
    for slot=0,5 do if U.Call(bot,"GetItemInSlot",slot)==nil then target=slot;break end end;
    if target==nil then for slot=0,5 do local it=U.Call(bot,"GetItemInSlot",slot);
        if passives[U.Call(it,"GetName")] then target,displaced=slot,it;break end;
    end end;
    if target==nil then
        if s.vision_inventory_reason~="no_safe_slot" then B.Emit(s,"vision_inventory_skip",{reason="no_safe_slot"});s.vision_inventory_reason="no_safe_slot" end;
        return false;
    end;
    s.next_vision_swap=U.Now()+C.swap_interval_s;
    local done=B.Fire(bot,s,"vision_equip",item,"observer_from_backpack",function()
        return bot:ActionImmediate_SwapItems(source,target);
    end,false);
    if done and U.Call(bot,"GetItemInSlot",target)==item then
        s.vision_swap={active=target,backpack=source,displaced=displaced};
        B.Emit(s,"vision_equipped",{active_slot=target,backpack_slot=source,evidence="inventory_readback"});
    end;
    return done;
end;
return M;
