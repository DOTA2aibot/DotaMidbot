-- Valuable visible mid wards: two bounded attacks, allowing at most two endangered LH.
local U=require(GetScriptDirectory().."/laning/tactical/util");
local B=require(GetScriptDirectory().."/laning/tactical/broker");
local C=require(GetScriptDirectory().."/laning/vision/config");
local P=require(GetScriptDirectory().."/laning/profile");
local D=require(GetScriptDirectory().."/laning/vision/deward");
local I=require(GetScriptDirectory().."/laning/vision/ward_items");
local Sequence=require(GetScriptDirectory().."/laning/vision/sequence");
local Sentry=require(GetScriptDirectory().."/laning/vision/sentry");
local Raze=require(GetScriptDirectory().."/laning/tactical/raze");
local O=require(GetScriptDirectory().."/laning/observer/core");
local M={};
function M.Enabled(bot) return P.tower_pressure_enabled==true and Sentry.Enabled(bot) end;
local function farmRisk(bot)
    local range=U.Call(bot,"GetAttackRange");local damage=U.Call(bot,"GetAttackDamage");local p=U.Pos(bot);
    if not p or not U.Number(range) or not U.Number(damage) then return nil end;
    local list=U.Call(bot,"GetNearbyLaneCreeps",range+100,true);if type(list)~="table" then return nil end;
    local imminent=0;
    for _,c in ipairs(list) do if U.Visible(c) and U.Distance(p,U.Pos(c))<=range+100 then
        local hp=U.Call(c,"GetHealth");local actual=U.Call(c,"GetActualIncomingDamage",damage,DAMAGE_TYPE_PHYSICAL);
        if not U.Number(hp) or not U.Number(actual) then return nil end;
        if hp<=actual*1.5 then imminent=imminent+1 end;
    end end;return imminent;
end;
local function lethalHero(bot)
    local enemies=U.Call(bot,"GetNearbyHeroes",1200,true,BOT_MODE_NONE);if type(enemies)~="table" then return true end;
    for _,e in ipairs(enemies) do if U.Enemy(bot,e) and U.Call(e,"IsInvulnerable")==false and U.Call(e,"IsMagicImmune")==false then
        local hp,regen=U.Call(e,"GetHealth"),U.Call(e,"GetHealthRegen");
        local raw=U.Call(bot,"GetAttackDamage");local range=U.Call(bot,"GetAttackRange");local point=U.Call(bot,"GetAttackPoint");
        local attack=U.Number(raw) and U.Call(e,"GetActualIncomingDamage",raw,DAMAGE_TYPE_PHYSICAL);
        if U.Call(e,"IsAttackImmune")==false and U.Number(range) and U.Number(point) and U.Number(attack) and U.Number(hp) and U.Number(regen)
            and U.Distance(U.Pos(bot),U.Pos(e))<=range and attack>=hp+math.max(0,regen)*point+10 then return true end;
        for i=1,3 do local a=U.Call(bot,"GetAbilityByName","nevermore_shadowraze"..i);
            local range,radius,cast=U.Special(a,{"shadowraze_range"}),U.Special(a,{"shadowraze_radius"}),U.Call(a,"GetCastPoint");
            local raw=U.Special(a,{"shadowraze_damage"}) or U.Call(a,"GetAbilityDamage");
            local aim=U.Number(cast) and U.Point(U.Call(e,"GetExtrapolatedLocation",cast));
            local actual=U.Number(raw) and U.Call(e,"GetActualIncomingDamage",raw,DAMAGE_TYPE_MAGICAL);
            if U.Ready(a) and range and radius and aim and U.Number(actual) and U.Number(hp) and U.Number(regen)
                and math.abs(U.Distance(U.Pos(bot),aim)-range)<=radius-40 and actual>=hp+math.max(0,regen)*cast+10 then return true end;
        end;
    end end;return false;
end;
function M.Safe(bot,job)
    if not M.Enabled(bot) then return false,"local_deward_disabled" end;
    local b=B.State(bot);if not b or b.pressure then return false,"pressure_owns_actions" end;
    if Raze.Pending(bot) or (b.raze_facing and U.Now()-b.raze_facing.at<.2) then return false,"raze_first" end;
    local o=O.State(bot);if o and o.ability_order_at and U.Now()-o.ability_order_at<.25 then return false,"cast_first" end;
    if not B.Free(b) and b.vision_support~=job then return false,"own_order_first" end;
    local ok,why=Sequence.Safe(bot,job);if not ok then return false,why end;
    local farm=farmRisk(bot);if not farm then return false,"farm_unknown" end;
    if farm>C.local_deward_max_missed_lh then return false,"whole_wave_at_risk" end;
    if lethalHero(bot) then return false,"hero_kill_first" end;
    return true;
end;
function M.Candidate(bot,b)
    if not M.Enabled(bot) or U.Now()<(b.local_deward_retry or -math.huge) then return end;
    local mid=U.Point(U.Global("GetLocationAlongLane",LANE_MID,.5));
    local range=U.Call(bot,"GetAttackRange");
    if not mid or not U.Number(range) or U.Distance(U.Pos(bot),mid)>C.support_mid_radius+C.local_deward_approach then return end;
    if U.Now()>=(b.local_deward_scan_at or -math.huge) then
        local list=UNIT_LIST_ENEMIES~=nil and U.Global("GetUnitList",UNIT_LIST_ENEMIES);
        b.local_deward_handles={};b.local_deward_scan_at=U.Now()+C.local_deward_scan_s;
        for _,w in ipairs(type(list)=="table" and list or {}) do
            if D.Valid(bot,w) then b.local_deward_handles[#b.local_deward_handles+1]=w end;
        end;
    end;
    -- Cache handles only: current visibility, health and location are re-read before every decision.
    local list=b.local_deward_handles or {};
    local best;local why;
    for _,w in ipairs(list) do if D.Valid(bot,w) and U.Distance(U.Pos(w),mid)<=C.support_mid_radius then
        local distance=U.Distance(U.Pos(bot),U.Pos(w));local kind=I.Kind(U.Call(w,"GetUnitName"));
        if distance<=range-25+C.local_deward_approach then
            local job={kind="local_deward",target=w,location=U.Pos(w),range=range,local_observer=true,
                ward_kind=kind,deadline=U.Now()+C.local_deward_max_s,attempts=0,health_drops=0,max_attempts=2,
                desire=C.local_deward_desire};
            local safe,reason=M.Safe(bot,job);why=reason;
            if safe then
                local score=(kind=="sentry" and 0 or 10000)+distance;
                if not best or score<best.score then job.score=score;best=job end;
            end;
        else why="outside_bounded_local_approach" end;
    end end;
    if why and (b.local_deward_reason~=why or U.Now()>=(b.local_deward_report or -math.huge)) then
        b.local_deward_reason=why;b.local_deward_report=U.Now()+3;
        B.Emit(b,"local_deward_skip",{reason=why});
    end;
    return best;
end;
function M.Leave(b) b.local_deward_retry=U.Now()+C.local_deward_retry_s end;
return M;
