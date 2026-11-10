local U=require(GetScriptDirectory().."/laning/tactical/util");
local C=require(GetScriptDirectory().."/laning/vision/config");
local Site=require(GetScriptDirectory().."/laning/vision/site");
local M={};
function M.Check(bot,goal,ownTarget,awaitingOwnWard,taskKind)
    if not Site.Participant(bot) or U.Call(bot,"IsAlive")~=true or (not awaitingOwnWard and not U.CanUse(bot)) then return false,"busy" end;
    local p=U.Pos(bot);local mid=U.Point(U.Global("GetLocationAlongLane",LANE_MID,.5));
    if not p or not mid or U.Distance(p,mid)>C.support_mid_radius or not goal then return false,"not_mid" end;
    local hp=U.HP(bot);local recent=U.Call(bot,"TimeSinceDamagedByAnyHero");
    if not hp or hp<.7 or not U.Number(recent) or recent<C.recent_damage_s then return false,"health_or_damage" end;
    local mode=U.Call(bot,"GetActiveMode");
    if mode==nil or mode==BOT_MODE_RETREAT or mode==BOT_MODE_ATTACK or (BOT_MODE_RUNE~=nil and mode==BOT_MODE_RUNE)
        or (BOT_MODE_EVASIVE_MANEUVERS~=nil and mode==BOT_MODE_EVASIVE_MANEUVERS) then return false,"priority_mode" end;
    local action=U.Call(bot,"GetCurrentActionType");
    if awaitingOwnWard then -- readback only, no second command while our ward cast is pending
    elseif action==BOT_ACTION_TYPE_ATTACK then
        if not ownTarget or U.Call(bot,"GetAttackTarget")~=ownTarget then return false,"native_attack" end;
    elseif action~=BOT_ACTION_TYPE_IDLE and action~=BOT_ACTION_TYPE_NONE and action~=BOT_ACTION_TYPE_MOVE_TO then return false,"native_action" end;
    local enemies=U.Call(bot,"GetNearbyHeroes",1599,true,BOT_MODE_NONE);
    local towers=U.Call(bot,"GetNearbyTowers",1599,true);
    if type(enemies)~="table" or type(towers)~="table" then return false,"safety_unknown" end;
    for _,e in ipairs(enemies) do if U.Visible(e) and math.min(U.Distance(p,U.Pos(e)),U.Distance(goal,U.Pos(e)))<=C.support_enemy_radius then return false,"hero_priority" end end;
    local farmRadius=taskKind=="sentry" and C.sentry_farm_radius or C.support_creep_radius;
    for _,enemy in ipairs({true,false}) do
        local creeps=U.Call(bot,"GetNearbyLaneCreeps",farmRadius,enemy);
        if type(creeps)~="table" then return false,"creeps_unknown" end;
        for _,c in ipairs(creeps) do if U.Visible(c) then
            if taskKind~="sentry" then return false,"lane_farm_priority" end;
            local distance=U.Distance(p,U.Pos(c));
            if enemy and distance<=farmRadius then return false,"lane_farm_priority" end;
            if not enemy then
                local range=U.Call(bot,"GetAttackRange");local hp=U.Call(c,"GetHealth");local maxhp=U.Call(c,"GetMaxHealth");
                if not U.Number(range) or not U.Number(hp) or not U.Number(maxhp) or maxhp<=0 then return false,"deny_safety_unknown" end;
                if distance<=range+75 and hp<=maxhp*.5 then return false,"lane_deny_priority" end;
            end;
        end end;
    end;
    local neutrals=U.Call(bot,"GetNearbyNeutralCreeps",farmRadius);
    if type(neutrals)~="table" then return false,"neutrals_unknown" end;
    for _,creep in ipairs(neutrals) do if U.Visible(creep) and (taskKind~="sentry" or U.Distance(p,U.Pos(creep))<=farmRadius) then return false,"neutral_farm_priority" end end;
    for _,t in ipairs(towers) do if U.Visible(t) then
        local range=U.Call(t,"GetAttackRange");local q=U.Pos(t);
        if not U.Number(range) or not q then return false,"tower_unknown" end;
        local dx,dy=goal.x-p.x,goal.y-p.y;local length=dx*dx+dy*dy;
        local fraction=length>0 and math.max(0,math.min(1,((q.x-p.x)*dx+(q.y-p.y)*dy)/length)) or 0;
        if U.Distance(q,{x=p.x+dx*fraction,y=p.y+dy*fraction})<=range+150 then return false,"tower" end;
    end end;
    return true;
end;
function M.Step(bot,s,goal,range,reason)
    local B=require(GetScriptDirectory().."/laning/tactical/broker");
    if not B.Free(s) or U.Now()<(s.support_move_at or -math.huge) then return false end;
    local p=U.Pos(bot);local distance=U.Distance(p,goal);if not p or distance<=range then return false end;
    local step=math.min(300,distance-range+10);local q={x=p.x+(goal.x-p.x)*step/distance,y=p.y+(goal.y-p.y)*step/distance,z=p.z};
    if U.Global("IsLocationPassable",U.Vector(q))~=true then return false end;
    s.support_move_at=U.Now()+C.support_move_interval_s;
    return B.Fire(bot,s,"vision_support_move",nil,reason,function() return bot:Action_MoveToLocation(U.Vector(q)) end,false);
end;
return M;
