-- Conservative visible-data estimate, never a promise of a kill or a zero-damage dive.
local U=require(GetScriptDirectory().."/laning/tactical/util");
local C=require(GetScriptDirectory().."/laning/pressure/config");
local M={};
local function passable(p)
    local v=U.Vector(p);return v and U.Global("IsLocationPassable",v)==true;
end;
local function pointAlong(a,b,length)
    local d=U.Distance(a,b);if d<1 then return nil end;
    return {x=a.x+(b.x-a.x)*length/d,y=a.y+(b.y-a.y)*length/d,z=a.z or 0};
end;
function M.Tower(bot)
    local team=U.Call(bot,"GetTeam");
    if TEAM_RADIANT==nil or TEAM_DIRE==nil or TOWER_MID_1==nil then return nil end;
    local enemy=team==TEAM_RADIANT and TEAM_DIRE or (team==TEAM_DIRE and TEAM_RADIANT or nil);
    if not enemy then return nil end;
    local tower=U.Global("GetTower",enemy,TOWER_MID_1);
    if U.Visible(tower) then return tower end;
end;
function M.Exit(bot,tower)
    local p,t=U.Pos(bot),U.Pos(tower);local range=U.Call(tower,"GetAttackRange");
    local own=U.Global("GetTower",U.Call(bot,"GetTeam"),TOWER_MID_1);local home=U.Pos(own);
    if not home and TEAM_RADIANT~=nil then home=U.Point(U.Global("GetLocationAlongLane",LANE_MID,U.Call(bot,"GetTeam")==TEAM_RADIANT and .25 or .75)) end;
    if not p or not t or not home or not U.Number(range) then return nil end;
    local goal=pointAlong(t,home,range+C.exit_margin);if not goal or not passable(goal) then return nil end;
    for _,f in ipairs({.25,.5,.75}) do
        if not passable({x=p.x+(goal.x-p.x)*f,y=p.y+(goal.y-p.y)*f,z=p.z}) then return nil end;
    end;
    return goal;
end;
function M.Cover(bot,tower)
    local target=U.Call(tower,"GetAttackTarget");local tp=U.Pos(tower);local p=U.Pos(bot);
    local raw=U.Call(tower,"GetAttackDamage");
    if not U.Visible(target) or U.Call(target,"GetTeam")~=U.Call(bot,"GetTeam") or U.Call(target,"IsHero")~=false
        or not U.Call(target,"GetUnitName") or not U.Call(target,"GetUnitName"):find("creep",1,true) then return nil end;
    local hp=U.Call(target,"GetHealth");local damage=U.Number(raw) and U.Call(target,"GetActualIncomingDamage",raw,DAMAGE_TYPE_PHYSICAL);
    local range=U.Call(tower,"GetAttackRange");
    if not tp or not p or not U.Pos(target) or not U.Number(hp) or not U.Number(damage) or damage<=0
        or not U.Number(range) or U.Distance(U.Pos(target),tp)>range or hp<damage*1.5 then return nil end;
    return target;
end;
function M.DeaggroTarget(bot,tower)
    local list=U.Call(bot,"GetNearbyLaneCreeps",1200,false);local p,t=U.Pos(bot),U.Pos(tower);
    if type(list)~="table" or not p or not t then return nil end;
    local best,d;
    for _,c in ipairs(list) do if U.Visible(c) and U.Call(c,"GetTeam")==U.Call(bot,"GetTeam") then
        local distance=U.Distance(U.Pos(c),t);
        if distance+50<U.Distance(p,t) and (not d or distance<d) then best,d=c,distance end;
    end end;
    return best;
end;
function M.Combo(bot,target,goal,travel)
    local mana=U.Call(bot,"GetMana");local rawAttack=U.Call(bot,"GetAttackDamage");
    local point=U.Call(bot,"GetAttackPoint");local regen=U.Call(target,"GetHealthRegen");
    if not U.Number(mana) or not U.Number(rawAttack) or not U.Number(point) or not U.Number(regen) then return nil end;
    -- Use current total damage (items/souls/attributes already included), with a 10-damage PT buffer.
    local attack=U.Call(target,"GetActualIncomingDamage",math.max(0,rawAttack-10),DAMAGE_TYPE_PHYSICAL);
    if not U.Number(attack) then return nil end;
    -- A right-click is useful pressure but not a guaranteed kill (evasion/high-ground misses).
    local damage,seconds,spells=0,travel+point+.25,0;
    local startDistance=U.Distance(U.Pos(bot),U.Pos(target));local endDistance=U.Distance(goal,U.Pos(target));
    for i=3,1,-1 do
        local a=U.Call(bot,"GetAbilityByName","nevermore_shadowraze"..i);
        local cost,cast=U.Cost(a),U.Call(a,"GetCastPoint");
        local raw=U.Special(a,{"shadowraze_damage"}) or U.Call(a,"GetAbilityDamage");
        local range=U.Special(a,{"shadowraze_range"});local radius=U.Special(a,{"shadowraze_radius"});
        local reachable=range and radius and math.max(startDistance,endDistance)>=range-radius+40
            and math.min(startDistance,endDistance)<=range+radius-40;
        -- A lower bound: do not count unobserved future stack hits, amplification or unspent Wand charges.
        if reachable and U.Call(bot,"IsSilenced")==false and U.Ready(a) and cost and mana>=cost and U.Number(cast) and U.Number(raw) and raw>0 then
            local actual=U.Call(target,"GetActualIncomingDamage",raw,DAMAGE_TYPE_MAGICAL);
            if U.Number(actual) and actual>0 then
                damage=damage+actual;seconds=seconds+cast+.15;mana=mana-cost;spells=spells+1;
            end;
        end;
    end;
    -- Near/medium Razes require closing to the goal, not just a stationary triple-cast.
    local hp=U.Call(target,"GetHealth");
    if not U.Number(hp) then return nil end;
    return {damage=damage,seconds=seconds,spells=spells,
        lethal=seconds<=C.max_kill_horizon and damage>=hp+math.max(0,regen)*seconds+C.kill_margin};
end;
function M.Evaluate(bot,target,tower,allowDeaggro)
    if not U.Actor(bot) or U.Call(bot,"IsAlive")~=true or not U.Enemy(bot,target)
        or U.Call(target,"IsIllusion")~=false or U.Call(target,"IsInvulnerable")~=false
        or U.Call(target,"IsMagicImmune")~=false or U.Call(target,"IsAttackImmune")~=false then return nil,"invalid_target" end;
    local hp,maxhp,speed=U.Call(bot,"GetHealth"),U.Call(bot,"GetMaxHealth"),U.Call(bot,"GetCurrentMovementSpeed");
    local p,e,t=U.Pos(bot),U.Pos(target),U.Pos(tower);
    local range,raw,cycle=U.Call(tower,"GetAttackRange"),U.Call(tower,"GetAttackDamage"),U.Call(tower,"GetSecondsPerAttack");
    if not p or not e or not t or not U.Visible(tower) or not U.Number(hp) or not U.Number(maxhp) or maxhp<=0
        or hp/maxhp<C.min_hp or not U.Number(speed) or speed<=0 or not U.Number(range) or not U.Number(raw) or raw<=0
        or not U.Number(cycle) or cycle<=0 then return nil,"risk_data_unknown" end;
    if U.Call(tower,"HasModifier","modifier_fountain_glyph")==true or U.Call(tower,"HasModifier","modifier_fortification")==true then return nil,"fortified_tower" end;
    local enemyAbility=U.Call(target,"GetCurrentActiveAbility");
    if enemyAbility and U.Call(enemyAbility,"IsInAbilityPhase")==true then return nil,"visible_enemy_cast" end;
    if U.Distance(p,t)>range+C.max_entry_distance or U.Distance(e,t)>range+250 then return nil,"outside_mid_t1" end;
    local heroes=U.Call(bot,"GetNearbyHeroes",1599,true,BOT_MODE_NONE);
    if type(heroes)~="table" then return nil,"enemies_unknown" end;
    local count=0;for _,h in ipairs(heroes) do
        if U.Visible(h) and U.Call(h,"IsHero")==true and U.Call(h,"GetTeam")~=U.Call(bot,"GetTeam") then count=count+1 end;
    end;
    if count~=1 then return nil,"multiple_or_missing_enemies" end;
    local goal=U.Distance(p,e)<=C.target_distance and p or pointAlong(e,p,C.target_distance);
    local cover=M.Cover(bot,tower);
    local deaggro=allowDeaggro and U.Call(tower,"GetAttackTarget")==bot and M.DeaggroTarget(bot,tower);
    local combo=goal and M.Combo(bot,target,goal,U.Distance(p,goal)/speed);
    if not combo then return nil,"combo_unknown" end;
    if not cover and not combo.lethal and not deaggro then return nil,"no_creeps_no_lethal" end;
    local closeForRaze=combo.lethal;
    if cover and not closeForRaze then
        local attackRange=U.Call(bot,"GetAttackRange");if not U.Number(attackRange) then return nil,"attack_range_unknown" end;
        local distance=math.max(400,attackRange-C.poke_range_margin);
        goal=U.Distance(p,e)<=distance and p or pointAlong(e,p,distance);
    elseif deaggro and not closeForRaze then goal=p end;
    local exit=M.Exit(bot,tower);
    if not goal or not exit or not passable(goal) then return nil,"exit_or_goal_unknown" end;
    for _,f in ipairs({.25,.5,.75}) do
        if not passable({x=p.x+(goal.x-p.x)*f,y=p.y+(goal.y-p.y)*f,z=p.z}) then return nil,"blocked_approach" end;
    end;
    local otherTowers=U.Call(bot,"GetNearbyTowers",1599,true);
    if type(otherTowers)~="table" then return nil,"tower_scan_unknown" end;
    for _,other in ipairs(otherTowers) do if other~=tower and U.Visible(other) then
        local r=U.Call(other,"GetAttackRange");
        if not U.Number(r) or U.Distance(U.Pos(other),goal)<=r+150 or U.Distance(U.Pos(other),exit)<=r+150 then return nil,"second_tower" end;
    end end;
    local escape=(U.Distance(goal,exit)+100)/speed;local travel=U.Distance(p,goal)/speed;
    for _,f in ipairs({.25,.5,.75}) do
        if not passable({x=goal.x+(exit.x-goal.x)*f,y=goal.y+(exit.y-goal.y)*f,z=goal.z}) then return nil,"blocked_escape" end;
    end;
    if TOWER_MID_2~=nil then
        local team=U.Call(tower,"GetTeam");local second=U.Global("GetTower",team,TOWER_MID_2);
        local sp=U.Pos(second);local sr=U.Call(second,"GetAttackRange");
        if second and sp and (not U.Number(sr) or U.Distance(sp,goal)<=sr+150 or U.Distance(sp,exit)<=sr+150) then return nil,"second_mid_tower" end;
    end;
    combo=M.Combo(bot,target,goal,travel);if not combo then return nil,"combo_unknown" end;
    if not cover and not combo.lethal and not deaggro then return nil,"no_creeps_no_lethal" end;
    -- Covered pressure budgets the next hit plus an exit, then rechecks live HP each callback.
    local attackPoint=U.Call(bot,"GetAttackPoint");if not U.Number(attackPoint) then return nil,"attack_timing_unknown" end;
    local engage=deaggro and 1 or (closeForRaze and combo.seconds or travel+math.max(C.covered_hit_horizon_s,attackPoint+.3));
    local horizon=engage+escape+.5;
    local enemyDamage=U.Call(target,"GetEstimatedDamageToTarget",true,bot,horizon,DAMAGE_TYPE_ALL);
    local towerHit=U.Call(bot,"GetActualIncomingDamage",raw,DAMAGE_TYPE_PHYSICAL);
    if not U.Number(enemyDamage) or enemyDamage<0 or not U.Number(towerHit) or towerHit<=0 then return nil,"incoming_damage_unknown" end;
    -- Even with creeps, budget switching aggro and an already airborne projectile.
    local projectiles=U.Call(bot,"GetIncomingTrackingProjectiles");if type(projectiles)~="table" then return nil,"projectiles_unknown" end;
    local airborne=0;for _,p in ipairs(projectiles) do if p.is_attack==true and p.caster==tower then airborne=airborne+1 end end;
    local shots=math.max(2,math.ceil(((cover and not closeForRaze) and escape or horizon)/cycle)+math.max(1,airborne));
    local creeps=U.Call(bot,"GetNearbyLaneCreeps",1200,true);if type(creeps)~="table" then return nil,"creep_scan_unknown" end;
    local creepDamage=0;
    for _,c in ipairs(creeps) do if U.Visible(c) and U.Distance(U.Pos(c),goal)<=600 then
        local rawC,cycleC=U.Call(c,"GetAttackDamage"),U.Call(c,"GetSecondsPerAttack");
        if not U.Number(rawC) or rawC<0 or not U.Number(cycleC) or cycleC<=0 then return nil,"creep_damage_unknown" end;
        local actual=U.Call(bot,"GetActualIncomingDamage",rawC,DAMAGE_TYPE_PHYSICAL);
        if not U.Number(actual) or actual<0 then return nil,"creep_damage_unknown" end;
        creepDamage=creepDamage+actual*math.ceil(horizon/cycleC);
    end end;
    local incoming=towerHit*C.tower_damage_margin*shots+enemyDamage*C.enemy_damage_margin+creepDamage+C.unknown_control_margin;
    local reserve=math.max(C.reserve_min,maxhp*C.reserve_fraction);
    if hp-incoming<reserve then return nil,"survival_budget",{hp=hp,incoming=incoming,reserve=reserve,
        tower_shots=shots,covered=cover~=nil,escape_seconds=escape,enemy_damage=enemyDamage,creep_damage=creepDamage} end;
    return {target=target,tower=tower,goal=goal,exit=exit,cover=cover,lethal=combo.lethal,close_for_raze=closeForRaze,
        damage=combo.damage,combo_seconds=combo.seconds,tower_shots=shots,airborne_tower_shots=airborne,incoming=incoming,
        reserve=reserve,escape_seconds=escape,hp_after_estimate=hp-incoming},"risk_budget_ok";
end;
return M;
