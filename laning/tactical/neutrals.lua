local U=require(GetScriptDirectory().."/laning/tactical/util");
local C=require(GetScriptDirectory().."/laning/tactical/config");
local B=require(GetScriptDirectory().."/laning/tactical/broker");
local M={};
local function neutral(bot,u)
    local team=TEAM_NEUTRAL or DOTA_TEAM_NEUTRALS;
    return team~=nil and U.Visible(u) and U.Call(u,"GetTeam")==team and U.Call(u,"IsHero")==false
        and U.Call(u,"IsInvulnerable")==false;
end;
local function stacks(unit,name)
    local i=U.Call(unit,"GetModifierByName",name);
    if not U.Number(i) or i<0 then return 0 end;
    local n=U.Call(unit,"GetModifierStackCount",i);return U.Number(n) and n>=0 and n or 0;
end;
local function damage(bot,a,target)
    local raw=U.Call(a,"GetAbilityDamage");if not U.Number(raw) or raw<=0 or DAMAGE_TYPE_MAGICAL==nil then return nil end;
    raw=raw+stacks(bot,"modifier_nevermore_necromastery")*(U.Special(a,{"damage_per_soul","bonus_damage_per_soul"}) or 0);
    raw=raw+stacks(target,"modifier_nevermore_shadowraze_debuff")*(U.Special(a,{"stack_bonus_damage","shadowraze_stack_bonus_damage"}) or 0);
    local actual=U.Call(target,"GetActualIncomingDamage",raw,DAMAGE_TYPE_MAGICAL);
    if U.Number(actual) and actual>=0 then return actual end;
end;
function M.Consider(bot)
    if not C.neutral_farm or not U.CanUse(bot) or U.Call(bot,"IsSilenced")~=false then return nil end;
    local enemies=U.Call(bot,"GetNearbyHeroes",1200,true,BOT_MODE_NONE);
    local lane=U.Call(bot,"GetNearbyLaneCreeps",950,true);
    if type(enemies)~="table" or type(lane)~="table" then return nil end;
    for _,e in ipairs(enemies) do if U.Visible(e) then return nil end end;
    for _,e in ipairs(lane) do if U.Visible(e) then return nil end end;
    local nearby=U.Call(bot,"GetNearbyNeutralCreeps",C.neutral_radius);
    if type(nearby)~="table" then return nil end;
    local units={};for _,u in ipairs(nearby) do if neutral(bot,u) then units[#units+1]=u end end;
    if #units==0 then return nil end;
    local attack=U.Call(bot,"GetAttackTarget");local engaged=false;
    for _,u in ipairs(units) do if u==attack then engaged=true end end;
    if not engaged and (BOT_MODE_FARM==nil or U.Call(bot,"GetActiveMode")~=BOT_MODE_FARM) then return nil end;
    local p=U.Pos(bot);local mana=U.Call(bot,"GetMana");if not p or not U.Number(mana) then return nil end;
    local first=U.Call(bot,"GetAbilityByName","nevermore_shadowraze1");local cost=U.Cost(first);
    if not cost then return nil end;
    local reserve=cost*C.neutral_reserve_razes;local best;
    for i=1,3 do local a=U.Call(bot,"GetAbilityByName","nevermore_shadowraze"..i);
        local range=U.Special(a,{"shadowraze_range"});local radius=U.Special(a,{"shadowraze_radius"});local spend=U.Cost(a);
        if U.Ready(a) and range and radius and spend and mana-spend>=reserve then
            for _,aim in ipairs(units) do
                local q=U.Pos(aim);local distance=U.Distance(q,p);
                if q and distance>1 and distance<=range+radius then
                    local impact={x=p.x+(q.x-p.x)*range/distance,y=p.y+(q.y-p.y)*range/distance};
                    local count,kills,value=0,0,0;
                    for _,u in ipairs(units) do
                        if U.Distance(U.Pos(u),impact)<=radius-30 then
                            local dmg=damage(bot,a,u);local hp=U.Call(u,"GetHealth");
                            if dmg and U.Number(hp) and hp>0 then count=count+1;value=value+math.min(dmg,hp);if dmg>=hp then kills=kills+1 end end;
                        end;
                    end;
                    local score=value/math.max(spend,1)+kills*4;
                    if (count>=2 or kills>0 or value>=spend*2) and (not best or score>best.score) then
                        best={ability=a,location=q,count=count,kills=kills,score=score,reserve=reserve,reason="neutral_raze_resource_efficient"};
                    end;
                end;
            end;
        end;
    end;
    local feast=U.Call(bot,"GetAbilityByName","nevermore_frenzy");local feastCost=U.Cost(feast);
    local hpTotal=0;local inFeast=0;
    local feastRange=U.Special(feast,{"soul_collection_radius","radius"}) or 600;
    for _,u in ipairs(units) do if U.Distance(p,U.Pos(u))<=feastRange then
        local hp=U.Call(u,"GetHealth");if U.Number(hp) then hpTotal=hpTotal+hp;inFeast=inFeast+1 end;
    end end;
    local attackDamage=U.Call(bot,"GetAttackDamage");
    if best and U.Ready(feast) and feastCost and U.Number(attackDamage) and inFeast>=2 and hpTotal>=attackDamage*4
        and mana-feastCost-(U.Cost(best.ability) or math.huge)>=reserve
        and U.Call(bot,"HasModifier","modifier_nevermore_frenzy")==false then
        return {ability=feast,reason="neutral_feast_before_efficient_clear",count=inFeast,reserve=reserve};
    end;
    return best;
end;
function M.Execute(bot,s,plan)
    if not plan or not U.CanUse(bot) or not B.Free(s) then return false end;
    if not plan.location then
        return B.Fire(bot,s,"cast",plan.ability,plan.reason,function() return bot:Action_UseAbility(plan.ability) end,true);
    end;
    local range=U.Special(plan.ability,{"shadowraze_range"});local radius=U.Special(plan.ability,{"shadowraze_radius"});
    local p=U.Pos(bot);local facing=U.Call(bot,"GetFacing");
    if not p or not range or not radius or not U.Number(facing) then return false end;
    local angle=math.rad(facing);local impact={x=p.x+math.cos(angle)*range,y=p.y+math.sin(angle)*range};
    if U.Distance(impact,plan.location)<=radius-40 then
        return B.Fire(bot,s,"cast",plan.ability,plan.reason,function() return bot:Action_UseAbility(plan.ability) end,true);
    end;
    -- Only a bounded facing step at an already reached camp; no jungle pathing.
    if U.Now()<(s.next_neutral_face or -math.huge) then return false end;
    local distance=U.Distance(p,plan.location);if distance<=1 then return false end;
    local step={x=p.x+(plan.location.x-p.x)*C.neutral_face_step/distance,
        y=p.y+(plan.location.y-p.y)*C.neutral_face_step/distance};
    if U.Global("IsLocationPassable",U.Vector(step))~=true then return false end;
    local towers=U.Call(bot,"GetNearbyTowers",1599,true);if type(towers)~="table" then return false end;
    for _,t in ipairs(towers) do if U.Visible(t) then local r=U.Call(t,"GetAttackRange");
        if not U.Number(r) or U.Distance(step,U.Pos(t))<=r+150 then return false end;
    end end;
    s.next_neutral_face=U.Now()+C.neutral_face_interval;
    return B.Fire(bot,s,"face",plan.ability,"neutral_bounded_facing_step",function() return bot:Action_MoveDirectly(U.Vector(step)) end,false);
end;
return M;
