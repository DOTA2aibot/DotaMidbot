-- Test fixture economy: replaces native purchasing for this scripted team.
-- No engine methods are replaced; all plans and recipe leaves forbid wards.
local U=require(GetScriptDirectory().."/laning/tactical/util");
local Profile=require(GetScriptDirectory().."/laning/profile");
local M,states={},setmetatable({}, {__mode="k"});
local builds={
    npc_dota_hero_juggernaut={"item_tango","item_quelling_blade","item_magic_wand","item_phase_boots","item_maelstrom","item_sange_and_yasha","item_black_king_bar","item_desolator"},
    npc_dota_hero_bristleback={"item_tango","item_bracer","item_magic_wand","item_phase_boots","item_blade_mail","item_heavens_halberd","item_black_king_bar"},
    npc_dota_hero_lion={"item_tango","item_clarity","item_magic_wand","item_tranquil_boots","item_glimmer_cape","item_force_staff","item_aether_lens"},
    npc_dota_hero_crystal_maiden={"item_tango","item_clarity","item_magic_wand","item_tranquil_boots","item_glimmer_cape","item_force_staff","item_black_king_bar"},
};
local fallback={"item_tango","item_magic_wand","item_boots","item_glimmer_cape","item_force_staff","item_black_king_bar"};
local function forbidden(name) return name=="item_ward_observer" or name=="item_ward_sentry" or name=="item_ward_dispenser" end;
local function emit(bot,s,reason,item)
    if s.last~=reason..tostring(item) then
        s.last=reason..tostring(item);pcall(print,"[MIDBOT ally_shop] actor="..tostring(U.Call(bot,"GetPlayerID")).." reason="..reason.." item="..tostring(item));
    end;
end;
local function controlledTeam(bot)
    local team=U.Call(bot,"GetTeam");local ids=U.Global("GetTeamPlayers",team);
    if not U.Number(team) or type(ids)~="table" then return false end;
    for _,id in ipairs(ids) do
        if U.Global("IsPlayerBot",id)==true and U.Global("GetSelectedHeroName",id)=="npc_dota_hero_nevermore" then return true end;
    end;return false;
end;
local function owned(bot)
    local result={};
    local function scan(unit,last)
        if not unit or type(unit.GetItemInSlot)~="function" then return false end;
        for i=0,last do local item=U.Call(unit,"GetItemInSlot",i);local name=U.Call(item,"GetName");
            if item and type(name)~="string" then return false end;
            if name then result[name]=(result[name] or 0)+1 end;
        end;return true;
    end;
    if not scan(bot,14) then return nil end;
    local n=U.Global("GetNumCouriers");if not U.Number(n) or n<0 then return nil end;
    for i=0,n-1 do local c=U.Global("GetCourier",i);local owner=U.Call(c,"GetPlayerID");
        if owner==nil then return nil end;
        if owner==U.Call(bot,"GetPlayerID") and not scan(c,8) then return nil end;
    end;return result;
end;
local function expand(name,stock,out,visiting,depth)
    if type(name)~="string" or forbidden(name) or depth>16 or visiting[name] then return false end;
    if (stock[name] or 0)>0 then stock[name]=stock[name]-1;return true end;
    if type(GetItemComponents)~="function" then return false end;
    local ok,recipe=pcall(GetItemComponents,name);if not ok then return false end;
    if recipe==nil then recipe={} end;if type(recipe)~="table" then return false end;
    if type(recipe[1])=="table" then recipe=recipe[1] end;
    if #recipe==0 or (#recipe==1 and recipe[1]==name) then out[#out+1]=name;return true end;
    visiting[name]=true;for _,part in ipairs(recipe) do if not expand(part,stock,out,visiting,depth+1) then return false end end;
    visiting[name]=nil;return true;
end;
local function courier(bot,s,now)
    if now<(s.nextCourier or -math.huge) then return end;s.nextCourier=now+3;
    local stash=false;for i=9,14 do if U.Call(bot,"GetItemInSlot",i) then stash=true end end;
    if not stash or COURIER_ACTION_TAKE_AND_TRANSFER_ITEMS==nil then return end;
    local n=U.Global("GetNumCouriers");if not U.Number(n) then return end;
    for i=0,n-1 do local c=U.Global("GetCourier",i);
        if U.Call(c,"GetPlayerID")==U.Call(bot,"GetPlayerID") then
            local state;
            if type(GetCourierState)=="function" then state=U.Global("GetCourierState",c) else state=U.Call(c,"GetCourierState") end;
            if (COURIER_STATE_IDLE~=nil and state==COURIER_STATE_IDLE) or (COURIER_STATE_AT_BASE~=nil and state==COURIER_STATE_AT_BASE) then
                pcall(function() bot:ActionImmediate_Courier(c,COURIER_ACTION_TAKE_AND_TRANSFER_ITEMS) end);
            end;return;
        end;
    end;
end;
function M.Tick(bot)
    if Profile.name~="all_test" or Profile.ally_ward_free_shop~=true or not bot
        or U.Call(bot,"IsHero")~=true or U.Call(bot,"IsIllusion")~=false
        or U.Call(bot,"GetUnitName")=="npc_dota_hero_nevermore"
        or U.Global("IsPlayerBot",U.Call(bot,"GetPlayerID"))~=true then return end;
    local now=U.Global("GameTime");if not U.Number(now) then return end;
    local s=states[bot];if not s then s={queue={}};states[bot]=s;
        for _,name in ipairs(builds[U.Call(bot,"GetUnitName")] or fallback) do s.queue[#s.queue+1]=name end;
    end;
    if not controlledTeam(bot) then emit(bot,s,"wrong_scripted_team_no_sf",nil);return end;
    courier(bot,s,now);
    if now<(s.next or -math.huge) then return end;s.next=now+.5;
    local stock=owned(bot);if not stock then return end;
    if s.unknown then
        if (stock[s.unknown] or 0)>(s.before or 0) or (stock[s.queue[1]] or 0)>0 then
            if (stock[s.queue[1]] or 0)>0 then s.plan={}
            elseif s.plan and s.plan[1]==s.unknown then table.remove(s.plan,1) end;s.unknown=nil;
        else return end;
    end;
    local target=s.queue[1];if not target then pcall(function() bot:SetNextItemPurchaseValue(0) end);return end;
    local physical={};for name,n in pairs(stock) do physical[name]=n end;
    if not s.plan then s.plan={};if not expand(target,stock,s.plan,{},0) then
        emit(bot,s,"recipe_rejected",target);table.remove(s.queue,1);s.plan=nil;return;
    end end;
    if #s.plan==0 then table.remove(s.queue,1);s.plan=nil;return end;
    local item=s.plan[1];if forbidden(item) then emit(bot,s,"ward_blocked",item);s.plan=nil;table.remove(s.queue,1);return end;
    local cost=U.Global("GetItemCost",item);local gold=U.Call(bot,"GetGold");
    if not U.Number(cost) or cost<0 or not U.Number(gold) or PURCHASE_ITEM_SUCCESS==nil then return end;
    pcall(function() bot:SetNextItemPurchaseValue(cost) end);if gold<cost then return end;
    local ok,value=pcall(function() return bot:ActionImmediate_PurchaseItem(item) end);
    emit(bot,s,ok and "purchase_result_"..tostring(value) or "purchase_unknown",item);
    if not ok or not U.Number(value) then s.unknown=item;s.before=physical[item] or 0;return end;
    if value==PURCHASE_ITEM_SUCCESS then table.remove(s.plan,1);s.failures=0;return end;
    s.failures=(s.failures or 0)+1;
    if (PURCHASE_ITEM_INVALID_ITEM_NAME~=nil and value==PURCHASE_ITEM_INVALID_ITEM_NAME)
        or (PURCHASE_ITEM_DISALLOWED_ITEM~=nil and value==PURCHASE_ITEM_DISALLOWED_ITEM) then
        table.remove(s.queue,1);s.plan=nil;s.failures=0;
    elseif s.failures>=10 then
        table.remove(s.queue,1);s.queue[#s.queue+1]=target;s.plan=nil;s.failures=0;s.next=now+3;
    end;
end;
return M;
