local U=require(GetScriptDirectory().."/laning/tactical/util");
local B=require(GetScriptDirectory().."/laning/tactical/broker");
local C=require(GetScriptDirectory().."/laning/vision/config");
local P=require(GetScriptDirectory().."/laning/profile");
local T=require(GetScriptDirectory().."/laning/tactical/config");
local Site=require(GetScriptDirectory().."/laning/vision/site");
local I=require(GetScriptDirectory().."/laning/vision/ward_items");
local Idle=require(GetScriptDirectory().."/laning/vision/idle");
local M={};
function M.Valid(bot,w)
    -- Never use hidden ward locations, cached HP or a bare "enemy ward exists" flag.
    if not U.Visible(w) or not I.Kind(U.Call(w,"GetUnitName")) then return false end;
    local a,b=U.Call(bot,"GetTeam"),U.Call(w,"GetTeam");
    return U.Number(a) and U.Number(b) and a~=b and U.Call(w,"IsAttackImmune")==false and U.Call(w,"IsInvulnerable")==false;
end;
function M.Scan(bot,b)
    local now=U.Now();if T.enabled~=true or T.wards~=true or not C.support_enabled or not C.deward_enabled or not Site.Participant(bot) or P.wards_enabled~=true
        or P.ward_phase_enabled~=true or P.runtime_enabled==true or not now or now<45 or now>=C.recovery_end_s then return end;
    local minute=math.floor(now/60);if now%60<45 or b.deward_checked==minute then return end;b.deward_checked=minute;
    local list=UNIT_LIST_ENEMIES~=nil and U.Global("GetUnitList",UNIT_LIST_ENEMIES);
    local mid=U.Point(U.Global("GetLocationAlongLane",LANE_MID,.5));local known=type(list)=="table" and mid~=nil;
    b.deward_candidates={};
    if known then for _,w in ipairs(list) do if M.Valid(bot,w) then
        local p=U.Pos(w);if p and U.Distance(p,mid)<=C.support_mid_radius then b.deward_candidates[#b.deward_candidates+1]=w end;
    end end end;
    local start=(minute+1)*60;b.deward_window=start<C.recovery_end_s and {key="deward:"..start,start=start,finish=start+30} or nil;
    B.Emit(b,"deward_check",{known=known,count=#b.deward_candidates,next_window=b.deward_window and b.deward_window.start});
end;
function M.Candidate(bot,b)
    M.Scan(bot,b);local now=U.Now();local w=b.deward_window;
    if T.enabled~=true or T.wards~=true or not C.support_enabled or not C.deward_enabled or not w or not now or now<w.start or now>w.finish or b.deward_deferred==w.key then return end;
    local best;
    for _,target in ipairs(b.deward_candidates or {}) do if M.Valid(bot,target) then
        local p=U.Pos(target);local range=U.Call(bot,"GetAttackRange");local distance=U.Distance(U.Pos(bot),p);
        if p and U.Number(range) and range>25 and distance<=range-25+C.support_max_approach and Idle.Check(bot,p) then
            local score=(I.Kind(U.Call(target,"GetUnitName"))=="sentry" and 0 or 10000)+distance;
            if not best or score<best.score then best={kind="deward",target=target,location=p,range=range,score=score,
                window=w,started=now,deadline=math.min(now+C.support_max_s,w.finish),attempts=0,health_drops=0};end;
        end;
    end end;return best;
end;
function M.Defer(bot,job)
    local b=B.State(bot);if b and job then b.deward_deferred=job.window.key end;
end;
function M.Execute(bot,b,job)
    if not M.Valid(bot,job.target) then return end;
    local hp=U.Call(job.target,"GetHealth");if not U.Number(hp) or hp<=0 then return end;
    if job.waiting then
        if hp<job.before_hp then
            job.health_drops=job.health_drops+1;job.waiting=nil;
            B.Emit(b,"deward_health_change",{before=job.before_hp,after=hp,own_hit_attribution="unknown"});
        elseif U.Now()-job.sent_at<C.deward_attack_timeout_s then return end;
        job.waiting=nil;
    end;
    if job.attempts>=C.deward_max_attempts then return end;
    local p=U.Pos(job.target);if not p then return end;job.location=p;
    if U.Distance(U.Pos(bot),p)>job.range-25 then Idle.Step(bot,b,p,job.range-25,"deward_window");return end;
    job.before_hp=hp;
    if B.Fire(bot,b,"deward_attack",nil,"visible_enemy_ward",function() return bot:Action_AttackUnit(job.target,true) end,false) then
        job.waiting=true;job.sent_at=U.Now();job.attempts=job.attempts+1;
        B.Emit(b,"deward_attack_submitted",{kind=I.Kind(U.Call(job.target,"GetUnitName")),attempt=job.attempts,
            expected_full_health_hits=C.deward_expected_hits,outcome="unverified"});
    end;
end;
function M.Destroyed(bot,b,job)
    -- Fog, IsNull and disappearing from a visible-unit list alone are UNKNOWN, not success.
    if U.Call(job.target,"IsNull")==false and U.Call(job.target,"CanBeSeen")==true
        and U.Call(job.target,"IsAlive")==false and U.Call(job.target,"GetHealth")==0 then
        B.Emit(b,"deward_destroyed_observed",{attempts=job.attempts,health_drops=job.health_drops,own_kill_credit="unknown"});return true;
    end;return false;
end;
return M;
