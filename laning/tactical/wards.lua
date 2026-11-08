local U=require(GetScriptDirectory().."/laning/tactical/util");
local C=require(GetScriptDirectory().."/laning/tactical/config");
local B=require(GetScriptDirectory().."/laning/tactical/broker");
local Site=require(GetScriptDirectory().."/laning/vision/site");
local Supply=require(GetScriptDirectory().."/laning/vision/supply");
local Inventory=require(GetScriptDirectory().."/laning/vision/inventory");
local M={};
local function height(p) if not p then return nil end;local h=U.Global("GetHeightLevel",U.Vector(p));if U.Number(h) and h>=1 and h<=5 then return h end end;
local function kind(name)
    if name=="npc_dota_observer_wards" or name=="item_ward_observer" then return "observer" end;
    if name=="npc_dota_sentry_wards" or name=="item_ward_sentry" then return "sentry" end;
end;
local function allies()
    if UNIT_LIST_ALLIED_WARDS==nil then return nil end;
    local list=U.Global("GetUnitList",UNIT_LIST_ALLIED_WARDS);if type(list)~="table" then return nil end;
    local out={};for _,w in ipairs(list) do if U.Visible(w) and kind(U.Call(w,"GetUnitName")) then
        local p=U.Pos(w);if p then out[#out+1]={handle=w,location=p,kind=kind(U.Call(w,"GetUnitName"))} end;
    end end;return out;
end;
local function available(bot)
    for slot=0,5 do local item=U.Call(bot,"GetItemInSlot",slot);local name=U.Call(item,"GetName");
        if U.Ready(item) and (name=="item_ward_dispenser" or kind(name)) then
            local primary=U.Call(item,"GetCurrentCharges");local secondary=U.Call(item,"GetSecondaryCharges");
            if name=="item_ward_dispenser" then
                -- Calibrated by run9082079610 at24s: toggle=true -> observed observer.
                local toggle=U.Call(item,"GetToggleState");
                if type(toggle)=="boolean" and U.Number(primary) and U.Number(secondary) then
                    return {item=item,observer=primary>0,sentry=secondary>0,mode=toggle and "observer" or "sentry",toggle=toggle};
                end;
            elseif U.Number(primary) and primary>0 then return {item=item,[kind(name)]=true,mode=kind(name)} end;
        end;
    end;
end;
local function duplicate(list,p,k)
    for _,w in ipairs(list) do if w.kind==k and U.Distance(w.location,p)<=C.ward_dedup_radius then return true end end;return false;
end;
local function lineClear(a,b,level,trees)
    local steps=math.max(1,math.ceil(U.Distance(a,b)/100));
    for i=1,steps do local p={x=a.x+(b.x-a.x)*i/steps,y=a.y+(b.y-a.y)*i/steps};
        local h=height(p);if not h or h>level then return false end;
    end;
    local dx,dy=b.x-a.x,b.y-a.y;local length=dx*dx+dy*dy;if length<=1 then return true end;
    for _,tree in ipairs(trees) do
        local t=((tree.x-a.x)*dx+(tree.y-a.y)*dy)/length;
        if t>0 and t<1 and U.Distance(tree,{x=a.x+t*dx,y=a.y+t*dy})<C.tree_corridor then return false end;
    end;
    return true;
end;
function M.Plan(bot)
    if not U.CanUse(bot) or not (U.HP(bot) and U.HP(bot)>=C.ward_min_hp) then return nil,"ward_busy_or_health" end;
    local mode=U.Call(bot,"GetActiveMode");
    if mode==nil or (BOT_MODE_RETREAT~=nil and mode==BOT_MODE_RETREAT)
        or (BOT_MODE_RUNE~=nil and mode==BOT_MODE_RUNE)
        or (BOT_MODE_ATTACK~=nil and mode==BOT_MODE_ATTACK)
        or (BOT_MODE_EVASIVE_MANEUVERS~=nil and mode==BOT_MODE_EVASIVE_MANEUVERS) then return nil,"ward_preserve_priority_mode" end;
    local action=U.Call(bot,"GetCurrentActionType");
    if action==nil or not ((BOT_ACTION_TYPE_IDLE~=nil and action==BOT_ACTION_TYPE_IDLE)
        or (BOT_ACTION_TYPE_NONE~=nil and action==BOT_ACTION_TYPE_NONE)
        or (BOT_ACTION_TYPE_MOVE_TO~=nil and action==BOT_ACTION_TYPE_MOVE_TO)) then return nil,"preserve_native_action" end;
    local enemies=U.Call(bot,"GetNearbyHeroes",C.ward_enemy_radius,true,BOT_MODE_NONE);
    local towers=U.Call(bot,"GetNearbyTowers",1599,true);
    if type(enemies)~="table" or type(towers)~="table" then return nil,"ward_safety_unknown" end;
    for _,e in ipairs(enemies) do if U.Visible(e) then return nil,"ward_enemy_nearby" end end;
    local item=available(bot);if not item then return nil,"ward_active_inventory_or_mode_unknown" end;
    local list=allies();local p=U.Pos(bot);local center=U.Point(U.Global("GetLocationAlongLane",LANE_MID,.5));
    local range=U.Call(item.item,"GetCastRange");
    if not p or not center or U.Distance(p,center)>2200 or not list or not U.Number(range) or range<=0 then return nil,"ward_context_unknown_or_not_mid" end;
    local function safe(q)
        if U.Distance(p,q)>range-25 then return false end;
        for _,t in ipairs(towers) do if U.Visible(t) then local r=U.Call(t,"GetAttackRange");
            if not U.Number(r) or U.Distance(U.Pos(t),p)<=r+150 or U.Distance(U.Pos(t),q)<=r+150 then return false end;
        end end;return true;
    end;
    if Site.Radiant(bot) then
        local spot,why=Site.Get(bot);if not spot then return nil,why end;
        if not item.observer then return nil,"fixed_observer_not_in_active_inventory" end;
        local exists,unknown=Site.Existing(spot);if unknown then return nil,unknown end;
        if exists then return nil,"fixed_observer_already_alive" end;
        if not safe(spot.location) then return nil,"fixed_observer_out_of_range_or_unsafe" end;
        return {item=item.item,kind="observer",mode=item.mode,prior=list,location=spot.location,
            height=spot.height,rune=spot.rune,rune_location=spot.rune_location,lane=spot.lane,
            expected_coverage=spot.expected_coverage,fixed=true};
    end;
    if item.observer then
        local bank1=U.Point(U.Global("GetLocationAlongLane",LANE_MID,.45));
        local bank2=U.Point(U.Global("GetLocationAlongLane",LANE_MID,.55));
        local h1,h2=height(bank1),height(bank2);
        local runes={U.Point(U.Global("GetRuneSpawnLocation",RUNE_POWERUP_1)),U.Point(U.Global("GetRuneSpawnLocation",RUNE_POWERUP_2))};
        local ids=U.Global("GetAllTrees");local trees={};
        local known=RUNE_POWERUP_1~=nil and RUNE_POWERUP_2~=nil and type(ids)=="table" and h1 and h2 and runes[1] and runes[2];
        if known then for _,id in ipairs(ids) do local t=U.Point(id) or U.Point(U.Global("GetTreeLocation",id));if not t then known=false;break end;
            if U.Distance(t,center)<=4000 then trees[#trees+1]=t end;
        end end;
        if known then
            local anchors={center,runes[1],runes[2]};local best;
            local vision=C.observer_vision_radius-C.observer_visibility_margin;
            local laneA=U.Point(U.Global("GetLocationAlongLane",LANE_MID,.48));
            local laneB=U.Point(U.Global("GetLocationAlongLane",LANE_MID,.52));
            for _,anchor in ipairs(anchors) do for _,radius in ipairs({350,650,1000}) do for i=0,7 do
                local angle=i*math.pi/4;local q={x=anchor.x+math.cos(angle)*radius,y=anchor.y+math.sin(angle)*radius};
                if safe(q) and not duplicate(list,q,"observer") then
                    local h=height(q);
                    -- True cliff above BOTH banks, not merely above the river center.
                    if h and h>=C.observer_min_height and h>math.max(h1,h2) and laneA and laneB
                        and U.Distance(q,laneA)<=vision and U.Distance(q,laneB)<=vision
                        and lineClear(q,laneA,h,trees) and lineClear(q,laneB,h,trees) then
                        for rune,rp in ipairs(runes) do if U.Distance(q,rp)<=vision and lineClear(q,rp,h,trees) then
                            local score=U.Distance(q,p)+U.Distance(q,rp)*.1;
                            if not best or score<best.score then best={item=item.item,kind="observer",location=q,height=h,
                                rune=rune==1 and RUNE_POWERUP_1 or RUNE_POWERUP_2,rune_location=rp,lane={laneA,laneB},score=score,
                                expected_coverage="range_and_terrain_and_known_tree_model",mode=item.mode,prior=list} end;
                        end end;
                    end;
                end;
            end end end;
            if best then return best end;
        end;
    end;
    if item.sentry and safe(center) and not duplicate(list,center,"sentry") then
        local h=height(center);
        if h and h<=C.river_height_max and U.Global("IsLocationPassable",U.Vector(center))==true then
            return {item=item.item,kind="sentry",location=center,height=h,mode=item.mode,prior=list};
        end;
    end;
    return nil,"no_valid_highground_coverage_or_river_point_in_range";
end;
function M.Poll(bot,s)
    if s.ward_toggle then
        local t=s.ward_toggle;local primary=U.Call(t.item,"GetCurrentCharges");local secondary=U.Call(t.item,"GetSecondaryCharges");
        if primary~=t.primary or secondary~=t.secondary then
            B.Emit(s,"ward_mode_unknown",{reason="charge_changed_during_toggle_disable_ward_executor"});s.ward_disabled=true;s.ward_toggle=nil;
        else
            local toggle=U.Call(t.item,"GetToggleState");local mode=type(toggle)=="boolean" and (toggle and "observer" or "sentry") or nil;
            if mode==t.wanted then B.Emit(s,"ward_mode_observed",{mode=mode});s.ward_toggle=nil end;
        end;
    end;
    local p=s.ward_pending;if not p then return end;
    local list=allies();
    for _,w in ipairs(list or {}) do
        local old=false;for _,v in ipairs(p.prior) do if v.handle==w.handle then old=true end end;
        if not old and w.kind==p.kind and U.Distance(w.location,p.location)<=128 then
            local primary=U.Call(p.item,"GetCurrentCharges");local secondary=U.Call(p.item,"GetSecondaryCharges");
            local spent=(U.Number(primary) and U.Number(p.primary) and primary<p.primary)
                or (U.Number(secondary) and U.Number(p.secondary) and secondary<p.secondary);
            local consumed=false;
            if p.fixed and primary==nil and p.primary==1 and type(bot.GetItemInSlot)=="function"
                and U.Call(w.handle,"GetPlayerID")==U.Call(bot,"GetPlayerID") then
                local present,known=false,true;
                for slot=0,5 do local ok,item=pcall(function() return bot:GetItemInSlot(slot) end);
                    if not ok then known=false end;if item==p.item then present=true end;
                end;
                consumed=known and not present;
            end;
            spent=spent or consumed;
            if spent then
                local data={kind=w.kind,location=w.location,owner_matches=U.Call(w.handle,"GetPlayerID")==U.Call(bot,"GetPlayerID"),height=height(w.location),evidence="new_ward_and_charge_spent"};
                if p.kind=="observer" then
                    data.rune_visible=U.Global("IsLocationVisible",U.Vector(p.rune_location));
                    data.mid_visible=U.Global("IsLocationVisible",U.Vector(p.lane[1]))==true and U.Global("IsLocationVisible",U.Vector(p.lane[2]))==true;
                    data.vision_radius=U.Call(w.handle,"GetCurrentVisionRange");data.coverage_attribution="team_visibility_not_exclusive_ward_credit";
                end;
                if consumed then data.evidence="new_owned_ward_and_item_consumed" end;
                if p.fixed and data.owner_matches then Supply.Placed(bot,w.handle,p) end;
                B.Emit(s,"ward_placement_observed",data);s.ward_pending=nil;return;
            end;
        end;
    end;
    if U.Now()-p.at>C.ward_timeout_s then B.Emit(s,"ward_outcome_unknown",{kind=p.kind,reason="placement_unconfirmed"});s.ward_pending=nil end;
end;
function M.Tick(bot,s)
    if not C.wards or s.ward_disabled or s.ward_pending or not B.Free(s) or U.Now()<(s.next_ward or -math.huge) then return false end;
    s.next_ward=U.Now()+1;
    if Inventory.Tick(bot,s) then return true end;
    local p,reason=M.Plan(bot);
    if not p then if s.ward_skip~=reason then B.Emit(s,"ward_skip",{reason=reason});s.ward_skip=reason end;return false end;
    if p.kind~=p.mode then
        -- Read back next tick; never place on a guessed dispenser mode.
        local old=s.ward_toggle;
        if old and old.item==p.item and old.wanted==p.kind and old.tries>=2 then
            B.Emit(s,"ward_mode_unknown",{reason="bounded_toggle_readback_failed"});s.next_ward=U.Now()+30;return false;
        end;
        s.ward_toggle={item=p.item,wanted=p.kind,tries=old and old.tries+1 or 1,
            primary=U.Call(p.item,"GetCurrentCharges"),secondary=U.Call(p.item,"GetSecondaryCharges")};
        return B.Fire(bot,s,"ward_mode_toggle",p.item,"select_"..p.kind,function() return bot:Action_UseAbility(p.item) end,false);
    end;
    p.primary=U.Call(p.item,"GetCurrentCharges");p.secondary=U.Call(p.item,"GetSecondaryCharges");
    B.Emit(s,"ward_plan",{kind=p.kind,location=p.location,height=p.height,rune=p.rune,coverage=p.expected_coverage});
    local done=B.Fire(bot,s,"ward",p.item,"validated_"..p.kind.."_point",function() return bot:Action_UseAbilityOnLocation(p.item,U.Vector(p.location)) end,false);
    if done then p.at=U.Now();s.ward_pending=p;s.next_ward=U.Now()+C.ward_interval_s end;
    return done;
end;
return M;
