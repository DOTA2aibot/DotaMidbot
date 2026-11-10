-- Adds bounded idle work to the existing WARD mode; never replaces lane/attack/retreat.
local U=require(GetScriptDirectory().."/laning/tactical/util");
local B=require(GetScriptDirectory().."/laning/tactical/broker");
local C=require(GetScriptDirectory().."/laning/vision/config");
local Phase=require(GetScriptDirectory().."/laning/vision/phase");
local Sentry=require(GetScriptDirectory().."/laning/vision/sentry");
local Deward=require(GetScriptDirectory().."/laning/vision/deward");
local Idle=require(GetScriptDirectory().."/laning/vision/idle");
local Sequence=require(GetScriptDirectory().."/laning/vision/sequence");
local M={};
function M.Leave(bot,reason)
    local b=B.State(bot);local job=b and b.vision_support;
    if job then
        if job.kind=="sentry_followup" then Sequence.Finish(bot,b,reason);Phase.Leave(bot,reason);return end;
        local success=reason=="placement_confirmed" or reason=="ward_destroyed_observed";
        if not success then if job.kind=="sentry" then Sentry.Defer(bot,job) else Deward.Defer(bot,job) end end;
        B.Emit(b,"vision_support_end",{kind=job.kind,reason=reason,attempts=job.attempts});b.vision_support=nil;
    end;
    Phase.Leave(bot,reason);
end;
function M.Poll(bot,b)
    Phase.Poll(bot,b);Sentry.Check(bot);Deward.Scan(bot,b);
    local job=b.vision_support;
    if job and ((job.kind=="sentry" and Sentry.Poll(bot,b,job)) or (job.kind=="deward" and Deward.Destroyed(bot,b,job))) then
        M.Leave(bot,job.kind=="sentry" and "placement_confirmed" or "ward_destroyed_observed");
        if job.kind=="sentry" then Sequence.Begin(bot,b,job) end;
    end;
    Sequence.Poll(bot,b);
end;
function M.Holds(bot,b)
    if not b then return false end;
    local job=b.vision_support;if not job then return Phase.Holds(bot,b) end;
    M.Poll(bot,b);if b.vision_support~=job then return false end;
    if job.kind=="sentry_followup" then
        if U.Call(bot,"GetActiveMode")~=BOT_MODE_WARD then M.Leave(bot,"mode_preempted");return false end;
        return Sequence.Holds(bot,b,job);
    end;
    local why;
    if not Sentry.Enabled(bot) or U.Now()>=job.deadline or U.Now()>=C.recovery_end_s then why="timeout_or_disabled"
    elseif U.Call(bot,"GetActiveMode")~=BOT_MODE_WARD then why="mode_preempted"
    elseif job.kind=="deward" and not Deward.Valid(bot,job.target) then why="target_hidden_or_unavailable"
    else
        local awaiting=job.kind=="sentry" and ((job.pending and U.Now()-job.pending<3) or Sentry.WaitingToggle(bot,job));
        local ok,reason=Idle.Check(bot,job.location,job.kind=="deward" and job.target or nil,awaiting,job.kind);
        if not ok then why=reason end;
    end;
    if why then M.Leave(bot,why);return false end;return true;
end;
local function candidate(bot,b)
    local followup=Sequence.Candidate(bot,b);if followup then return followup end;
    if b.sentry_followup then return end;
    local sentry=Sentry.Candidate(bot);if sentry then return sentry end;
    local deward=Deward.Candidate(bot,b);if deward then return deward end;
end;
function M.GetDesire(bot)
    local b=B.State(bot);if not b then return 0 end;M.Poll(bot,b);
    if b.vision_support then return M.Holds(bot,b) and C.support_desire or 0 end;
    if b.vision_phase then return Phase.GetDesire(bot) end;
    local job=candidate(bot,b);if job then return C.support_desire end;
    return Phase.GetDesire(bot);
end;
function M.Start(bot)
    local b=B.State(bot);if not b then return end;
    local job=candidate(bot,b);
    if job then
        if job.kind=="sentry" then Sentry.Started(bot,job) end;
        b.vision_support=job;B.Emit(b,"vision_support_start",{kind=job.kind,location=job.location,deadline=job.deadline});return;
    end;
    Phase.Start(bot);
end;
function M.Think(bot)
    local b=B.State(bot);if not b then return end;
    if not b.vision_support then return Phase.Think(bot) end;
    if not M.Holds(bot,b) or not B.Free(b) then return end;
    local job=b.vision_support;
    if job.kind=="sentry" then Sentry.Execute(bot,b,job)
    elseif job.kind=="sentry_followup" then Sequence.Execute(bot,b,job)
    else Deward.Execute(bot,b,job) end;
end;
return M;
