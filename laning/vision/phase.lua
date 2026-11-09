-- A bounded ward MODE, not a second lane controller. Native lane mode resumes on exit.
local U=require(GetScriptDirectory().."/laning/tactical/util");
local B=require(GetScriptDirectory().."/laning/tactical/broker");
local C=require(GetScriptDirectory().."/laning/vision/config");
local Tactical=require(GetScriptDirectory().."/laning/tactical/config");
local Profile=require(GetScriptDirectory().."/laning/profile");
local Site=require(GetScriptDirectory().."/laning/vision/site");
local Schedule=require(GetScriptDirectory().."/laning/vision/schedule");
local Supply=require(GetScriptDirectory().."/laning/vision/supply");
local M={};
function M.Enabled(bot)
    return C.calibration_only~=true and Profile.ward_phase_enabled==true and Profile.runtime_enabled~=true
        and Profile.wards_enabled==true and Tactical.enabled and Tactical.wards and Site.Radiant(bot);
end;
local function skip(s,reason)
    if s.vision_phase_skip~=reason then B.Emit(s,"ward_phase_skip",{reason=reason});s.vision_phase_skip=reason end;
    return nil,reason;
end;
local function ready(bot)
    for slot=0,5 do
        local it=U.Call(bot,"GetItemInSlot",slot);local name=U.Call(it,"GetName");
        local n=U.Call(it,"GetCurrentCharges");
        if (name=="item_ward_observer" or name=="item_ward_dispenser") and U.Number(n) and n>0 and U.Ready(it) then
            local range=U.Call(it,"GetCastRange");if U.Number(range) and range>25 then return it,range end;
        end;
    end;
end;
local function safety(bot,s,spot,owned)
    if not Site.Context(bot) then return "ward_context_ended" end;
    local hp=U.HP(bot);if not hp or hp<Tactical.ward_min_hp then return "health" end;
    local recent=U.Call(bot,"TimeSinceDamagedByAnyHero");if not U.Number(recent) or recent<C.recent_damage_s then return "recent_damage" end;
    local mode=U.Call(bot,"GetActiveMode");
    if mode==nil or mode==BOT_MODE_RETREAT
        or (BOT_MODE_RUNE~=nil and mode==BOT_MODE_RUNE)
        or (BOT_MODE_EVASIVE_MANEUVERS~=nil and mode==BOT_MODE_EVASIVE_MANEUVERS) then return "priority_mode" end;
    for _,k in ipairs({"IsStunned","IsHexed","IsMuted"}) do if U.Call(bot,k)~=false then return "disabled" end end;
    -- An owned ward cast may be using an ability; let its readback finish.
    if not (owned and s.ward_pending) then
        if not U.CanUse(bot) then return "busy" end;
        local a=U.Call(bot,"GetCurrentActionType");
        if a~=BOT_ACTION_TYPE_IDLE and a~=BOT_ACTION_TYPE_NONE and a~=BOT_ACTION_TYPE_MOVE_TO and a~=BOT_ACTION_TYPE_ATTACK then return "native_action" end;
    end;
    local p=U.Pos(bot);
    local enemies=U.Call(bot,"GetNearbyHeroes",1599,true,BOT_MODE_NONE);
    local towers=U.Call(bot,"GetNearbyTowers",1599,true);
    if not p or type(enemies)~="table" or type(towers)~="table" then return "safety_unknown" end;
    -- During these15s ordinary farm/harass yields; an actual attack/threat still aborts.
    for _,e in ipairs(enemies) do if U.Visible(e) then
        local distance=math.min(U.Distance(p,U.Pos(e)),U.Distance(spot.location,U.Pos(e)));
        local range=U.Call(e,"GetAttackRange");
        if distance<=C.phase_direct_enemy_radius then return "enemy_too_close" end;
        if U.Call(e,"GetAttackTarget")==bot and (not U.Number(range) or distance<=range+150) then return "enemy_attacking" end;
        if U.Call(e,"IsUsingAbility")==true and (U.Call(e,"GetTarget")==bot or U.Call(e,"GetAbilityTarget")==bot) then return "targeted_spell" end;
    end end;
    for _,t in ipairs(towers) do if U.Visible(t) then
        local range=U.Call(t,"GetAttackRange");local q=U.Pos(t);
        if not U.Number(range) or not q or math.min(U.Distance(q,p),U.Distance(q,spot.location))<=range+150 then return "tower" end;
    end end;
end;
function M.Leave(bot,reason)
    local s=B.State(bot);local p=s and s.vision_phase;if not p then return end;
    B.Emit(s,"ward_phase_end",{reason=reason or "mode_ended",elapsed=U.Now()-p.started,slot=p.slot,
        placement_confirmed=s.vision_confirmed_at and s.vision_confirmed_at>=p.started or false});
    s.vision_phase=nil;s.vision_phase_retry=U.Now()+C.phase_retry_s;
    -- No ClearActions: do not delete an emergency item, rune, attack or another cast.
end;
local function candidate(bot,s)
    if not M.Enabled(bot) or BOT_MODE_WARD==nil then return skip(s,"profile_or_mode_disabled") end;
    local now=U.Now();local window=Schedule.Window(now);local slot=window and window.slot;
    if slot==nil or s.vision_done_slot==slot then return skip(s,"schedule_complete") end;
    if now<(s.vision_phase_retry or -math.huge) then return nil,"retry_wait" end;
    if s.ward_pending or s.ward_disabled then return skip(s,"ward_unconfirmed_or_disabled") end;
    local spot,why=Site.Get(bot);if not spot then return skip(s,why) end;
    local exists,unknown=Site.Existing(spot);
    if unknown or (exists and not Supply.CanReplace(bot,exists,slot)) then return skip(s,unknown or "observer_alive") end;
    local whyUnsafe=safety(bot,s,spot,false);if whyUnsafe then return skip(s,whyUnsafe) end;
    local item,range=ready(bot);if not item then return skip(s,"active_observer_not_ready") end;
    local distance=U.Distance(U.Pos(bot),spot.location);
    if distance>range-25+C.phase_max_approach then return skip(s,"approach_too_far") end;
    s.vision_phase_skip=nil;
    return {spot=spot,item=item,range=range,slot=slot,started=now,deadline=math.min(now+C.phase_max_s,window.finish+Tactical.ward_timeout_s),window_finish=window.finish,
        distance=distance,progress_at=now};
end;
function M.Holds(bot,s)
    local p=s and s.vision_phase;if not p then return false end;
    local reason;
    if not M.Enabled(bot) then reason="disabled"
    elseif U.Call(bot,"GetActiveMode")~=BOT_MODE_WARD then reason="mode_preempted"
    elseif s.vision_confirmed_at and s.vision_confirmed_at>=p.started then reason="placement_confirmed"
    elseif p.awaiting_ward and not s.ward_pending then reason="placement_unconfirmed"
    elseif not s.ward_pending and Schedule.Slot(U.Now())~=p.slot then reason="window_closed"
    elseif U.Now()>=p.deadline then reason="timeout"
    else reason=safety(bot,s,p.spot,true) end;
    if reason then M.Leave(bot,reason);return false end;
    return true;
end;
function M.Poll(bot,s)
    if not M.Enabled(bot) or not s then return end;
    s.vision_window_reports=s.vision_window_reports or {};
    for i,w in ipairs(C.windows) do
        local slot=i-1;
        if U.Now()>w.finish+Tactical.ward_timeout_s and not s.vision_window_reports[slot] then
            s.vision_window_reports[slot]=true;
            local done=s.vision_done_slot==slot;
            B.Emit(s,done and "ward_window_complete" or "ward_window_missed",{slot=slot,start=w.start,finish=w.finish,
                last_reason=s.vision_phase_skip or "not_selected_or_busy",confirmed=done});
        end;
    end;
end;
function M.GetDesire(bot)
    local s=B.State(bot);if not s then return 0 end;M.Poll(bot,s);
    if s.vision_phase then return M.Holds(bot,s) and C.phase_desire or 0 end;
    local p=candidate(bot,s);return p and C.phase_desire or 0;
end;
function M.Start(bot)
    local s=B.State(bot);if not s then return end;
    local p=candidate(bot,s);if not p then return end;
    s.vision_phase=p;
    B.Emit(s,"ward_phase_start",{slot=p.slot,location=p.spot.location,deadline=p.deadline,
        distance=p.distance,rune_distance=p.spot.rune_distance,coverage=p.spot.expected_coverage});
end;
function M.Think(bot)
    local s=B.State(bot);if not M.Holds(bot,s) or not B.Free(s) then return end;
    local p=s.vision_phase;
    if s.ward_pending then return end;
    local exists,unknown=Site.Existing(p.spot);
    if unknown or (exists and not Supply.CanReplace(bot,exists,p.slot)) then M.Leave(bot,unknown or "observer_already_present");return end;
    local item,range=ready(bot);
    if not item or item~=p.item then M.Leave(bot,"item_changed_or_not_ready");return end;
    local distance=U.Distance(U.Pos(bot),p.spot.location);
    if distance<=range-25 then
        -- The only ward executor; same entity/charge readback as before.
        local Ward=require(GetScriptDirectory().."/laning/tactical/wards");
        Ward.Tick(bot,s);return;
    end;
    if distance<p.distance-C.phase_min_progress then p.distance=distance;p.progress_at=U.Now() end;
    if U.Now()-p.progress_at>=C.phase_stall_s then M.Leave(bot,"no_path_progress");return end;
    if U.Now()<(p.next_move or -math.huge) then return end;
    -- Walk toward a passable position inside cast range, never onto an unwalkable ward cliff.
    local from=U.Pos(bot);local target;
    for _,fraction in ipairs({.80,.60,.40,.20,0}) do
        local d=(range-40)*fraction;
        local q={x=p.spot.location.x+(from.x-p.spot.location.x)*d/distance,
            y=p.spot.location.y+(from.y-p.spot.location.y)*d/distance,z=from.z};
        if U.Global("IsLocationPassable",U.Vector(q))==true then target=q;break end;
    end;
    if not target then M.Leave(bot,"no_passable_cast_position");return end;
    p.next_move=U.Now()+C.phase_move_interval_s;
    B.Fire(bot,s,"ward_approach",nil,"bounded_ward_mode",function() return bot:Action_MoveToLocation(U.Vector(target)) end,false);
end;
return M;
