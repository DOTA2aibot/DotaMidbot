-- Bounded ROAM mode during delivery deviations; never follows or targets a courier.
local U=require(GetScriptDirectory().."/laning/tactical/util");
local B=require(GetScriptDirectory().."/laning/tactical/broker");
local C=require(GetScriptDirectory().."/laning/items/delivery_guard_config");
local Profile=require(GetScriptDirectory().."/laning/profile");
local M={};
function M.Enabled(bot)
    return Profile.delivery_lane_guard==true and Profile.runtime_enabled~=true and U.Actor(bot);
end;
local function anchor(bot)
    local mid=U.Point(U.Global("GetLocationAlongLane",LANE_MID,.5));
    local front=U.Point(U.Global("GetLaneFrontLocation",U.Call(bot,"GetTeam"),LANE_MID,0));
    if not mid or not front or U.Distance(mid,front)>C.anchor_radius or U.Distance(U.Pos(bot),mid)>C.mid_radius
        or U.Global("IsLocationPassable",U.Vector(front))~=true then return nil end;
    return front;
end;
local function delivery(bot)
    if COURIER_STATE_DELIVERING_ITEMS==nil then return nil end;
    local n=U.Global("GetNumCouriers");if not U.Number(n) or n<0 then return nil end;
    for i=0,n-1 do local c=U.Global("GetCourier",i);
        if U.Call(c,"GetPlayerID")==U.Call(bot,"GetPlayerID") and U.Call(c,"IsAlive")==true
            and U.Global("GetCourierState",c)==COURIER_STATE_DELIVERING_ITEMS then
            local count=0;if type(c.GetItemInSlot)~="function" then return nil end;
            for slot=0,8 do local ok,item=pcall(c.GetItemInSlot,c,slot);if not ok then return nil end;if item then count=count+1 end end;
            local p=U.Pos(c);if count>0 and p then return p end;
        end;
    end;
end;
local function safe(bot,s,goal)
    if not M.Enabled(bot) or not U.CanUse(bot) or U.Call(bot,"IsRooted")==true or not goal then return false end;
    local hp=U.HP(bot);local recent=U.Call(bot,"TimeSinceDamagedByAnyHero");
    if not hp or hp<C.min_hp or not U.Number(recent) or recent<C.recent_damage_s then return false end;
    local mode=U.Call(bot,"GetActiveMode");
    if mode==nil or mode==BOT_MODE_RUNE or mode==BOT_MODE_WARD or mode==BOT_MODE_ATTACK
        or (BOT_MODE_EVASIVE_MANEUVERS~=nil and mode==BOT_MODE_EVASIVE_MANEUVERS)
        or (s and (s.ward_pending or s.vision_phase)) then return false end;
    local action=U.Call(bot,"GetCurrentActionType");
    if not (s and s.delivery_guard) and action~=BOT_ACTION_TYPE_MOVE_TO and action~=BOT_ACTION_TYPE_IDLE and action~=BOT_ACTION_TYPE_NONE then return false end;
    local enemies=U.Call(bot,"GetNearbyHeroes",C.threat_radius,true,BOT_MODE_NONE);
    local towers=U.Call(bot,"GetNearbyTowers",1599,true);
    local missiles=U.Call(bot,"GetIncomingTrackingProjectiles");
    if type(enemies)~="table" or type(towers)~="table" or type(missiles)~="table" or #missiles>0 then return false end;
    for _,e in ipairs(enemies) do if U.Visible(e) then return false end end;
    for _,t in ipairs(towers) do if U.Visible(t) then
        local range=U.Call(t,"GetAttackRange");if not U.Number(range) or math.min(U.Distance(U.Pos(bot),U.Pos(t)),U.Distance(goal,U.Pos(t)))<=range+150 then return false end;
    end end;return true;
end;
function M.Sample(bot,s)
    if not M.Enabled(bot) or not s or U.Now()<(s.delivery_guard_sample or -math.huge) then return end;
    s.delivery_guard_sample=U.Now()+C.sample_s;
    local hero=U.Pos(bot);local courier=delivery(bot);local goal=anchor(bot);local previous=s.delivery_guard_previous;
    s.delivery_guard_previous={at=U.Now(),hero=hero,courier=courier,goal=goal};
    if previous and hero and courier and goal and previous.hero and previous.courier and previous.goal
        and U.Now()-previous.at<=1 and U.Call(bot,"GetCurrentActionType")==BOT_ACTION_TYPE_MOVE_TO then
        local vx,vy=hero.x-previous.hero.x,hero.y-previous.hero.y;
        local dx,dy=previous.courier.x-previous.hero.x,previous.courier.y-previous.hero.y;
        local length=math.sqrt(dx*dx+dy*dy);local progress=length>1 and (vx*dx+vy*dy)/length or 0;
        local away=U.Distance(hero,goal)-U.Distance(previous.hero,goal);
        if progress>=C.progress_min and away>=C.away_min and U.Distance(hero,courier)>C.courier_min_distance then
            s.delivery_guard_detected=U.Now()+1.5;
            if U.Now()>=(s.delivery_guard_report or -math.huge) then
                B.Emit(s,"delivery_lane_deviation",{hero_location=hero,courier_location=courier,lane_goal=goal,
                    hero_projection_towards_courier=progress,away_from_lane=away,mode=U.Call(bot,"GetActiveMode"),
                    attribution="observed_deviation_not_proof_of_native_intent"});s.delivery_guard_report=U.Now()+2;
            end;
        end;
    end;
end;
function M.Leave(bot,reason)
    local s=B.State(bot);if not s or not s.delivery_guard then return end;
    B.Emit(s,"delivery_lane_guard_end",{reason=reason or "mode_ended"});s.delivery_guard=nil;s.delivery_guard_retry=U.Now()+C.retry_s;
end;
local function eligible(bot,s,owned)
    local goal=anchor(bot);local c=delivery(bot);
    if not safe(bot,s,goal) or not c or U.Distance(U.Pos(bot),c)<=C.courier_min_distance then return nil end;
    if not owned and (U.Now()>(s.delivery_guard_detected or -math.huge) or U.Now()<(s.delivery_guard_retry or -math.huge)) then return nil end;
    return goal;
end;
function M.GetDesire(bot)
    if not M.Enabled(bot) or BOT_MODE_ROAM==nil then return 0 end;
    local s=B.State(bot);if not s then return 0 end;M.Sample(bot,s);
    if s.delivery_guard and U.Now()>=s.delivery_guard.deadline then M.Leave(bot,"bounded_timeout");return 0 end;
    if not eligible(bot,s,s.delivery_guard~=nil) then M.Leave(bot,"delivery_ended_or_priority_safety");return 0 end;
    return C.desire;
end;
function M.Start(bot)
    local s=B.State(bot);if not s then return end;M.Sample(bot,s);local goal=eligible(bot,s,false);if not goal then return end;
    s.delivery_guard={started=U.Now(),deadline=U.Now()+C.lease_s,goal=goal};
    B.Emit(s,"delivery_lane_guard_start",{goal=goal,policy="farm_or_lane_hold_courier_delivers_to_hero"});
end;
function M.Think(bot)
    local s=B.State(bot);local own=s and s.delivery_guard;if not own then return end;
    local goal=eligible(bot,s,true);
    if U.Call(bot,"GetActiveMode")~=BOT_MODE_ROAM or not goal or U.Now()>=own.deadline then M.Leave(bot,"preempted_unsafe_or_timeout");return end;
    if not B.Free(s) then return end;
    local action=U.Call(bot,"GetCurrentActionType");
    if action~=BOT_ACTION_TYPE_IDLE and action~=BOT_ACTION_TYPE_NONE and action~=BOT_ACTION_TYPE_MOVE_TO then return end;
    local creeps=U.Call(bot,"GetNearbyLaneCreeps",900,true);if type(creeps)~="table" then return end;
    local range=U.Call(bot,"GetAttackRange");local target;
    for _,c in ipairs(creeps) do if U.Visible(c) and U.Call(c,"IsAttackImmune")==false and U.Call(c,"IsInvulnerable")==false
        and U.Number(range) and U.Distance(U.Pos(bot),U.Pos(c))<=range then
        if not target or (U.Call(c,"GetHealth") or math.huge)<(U.Call(target,"GetHealth") or math.huge) then target=c end;
    end end;
    if target then
        B.Fire(bot,s,"delivery_lane_attack",nil,"nearby_creep_before_courier",function() return bot:Action_AttackUnit(target,true) end,false);return;
    end;
    local p=U.Pos(bot);local distance=U.Distance(p,goal);
    if distance<=C.arrival_radius then return end; -- hold the lane; do not chase the courier again
    if U.Now()<(own.next_move or -math.huge) then return end;
    local step=math.min(C.step,distance);local q={x=p.x+(goal.x-p.x)*step/distance,y=p.y+(goal.y-p.y)*step/distance,z=p.z};
    if U.Global("IsLocationPassable",U.Vector(q))~=true then M.Leave(bot,"path_unknown");return end;
    own.next_move=U.Now()+C.move_interval_s;
    B.Fire(bot,s,"delivery_lane_return",nil,"bounded_lane_anchor_not_courier",function() return bot:Action_MoveToLocation(U.Vector(q)) end,false);
end;
return M;
