-- One own order per game tick. No engine API or unit method is replaced.
local U = require(GetScriptDirectory().."/laning/tactical/util");
local C = require(GetScriptDirectory().."/laning/tactical/config");
local Trace = require(GetScriptDirectory().."/laning/advanced/trace");
local M, states = {}, setmetatable({}, {__mode="k"});
function M.State(bot)
    local now=U.Now(); if not now or bot==nil then return nil end;
    local s=states[bot]; if not s or now < s.time then s={seq=0,retries={},pending={}};states[bot]=s end;
    s.time=now;s.actor_id=U.Call(bot,"GetPlayerID");return s;
end;
function M.Emit(s,kind,data)
    if not s then return end; s.seq=s.seq+1;
    pcall(function() print("[MIDBOT tactical] "..Trace.Encode({schema="midbot-tactical-1",version=C.version,
        seq=s.seq,time=U.Now(),actor_id=s.actor_id,kind=kind,data=data or {},reward_status="not_defined"})) end);
end;
function M.Free(s) return s and U.Now() ~= nil and s.order_at ~= U.Now() end;
function M.Mark(s) s.order_at=U.Now() end;
function M.Fire(bot,s,kind,ability,reason,fn,track)
    if not M.Free(s) or not U.Actor(bot) then return false end;
    M.Mark(s); local name=U.Call(ability,"GetName");
    local before={charges=U.Call(ability,"GetCurrentCharges"),cd=U.Call(ability,"GetCooldownTimeRemaining")};
    local ok,returned=pcall(fn);
    M.Emit(s,"order_attempt",{action=kind,ability=name,reason=reason,api_returned=ok,api_rejected=returned==false,outcome="unverified"});
    if track and ability and ok and returned~=false then
        s.pending[name]={handle=ability,before=before,at=U.Now()};
    end;
    if name then s.retries[name]=(U.Now() or 0)+C.item_retry_s end;
    return true;
end;
function M.RetryReady(s,name) return U.Now() >= (s.retries[name] or -math.huge) and not s.pending[name] end;
function M.Self(bot,s,item,reason,track)
    local behavior=U.Call(item,"GetBehavior");
    local unit=ABILITY_BEHAVIOR_UNIT_TARGET or DOTA_ABILITY_BEHAVIOR_UNIT_TARGET;
    local none=ABILITY_BEHAVIOR_NO_TARGET or DOTA_ABILITY_BEHAVIOR_NO_TARGET;
    if U.Has(behavior,unit) then
        return M.Fire(bot,s,"item",item,reason,function() return bot:Action_UseAbilityOnEntity(item,bot) end,track);
    elseif U.Has(behavior,none) then
        return M.Fire(bot,s,"item",item,reason,function() return bot:Action_UseAbility(item) end,track);
    end;
    if s.last_behavior_name~=U.Call(item,"GetName") then M.Emit(s,"item_skip",{ability=U.Call(item,"GetName"),reason="behavior_unknown"});s.last_behavior_name=U.Call(item,"GetName") end;
    return false;
end;
function M.Poll(bot,s)
    local now=U.Now();
    for name,p in pairs(s.pending) do
        local charges,cd=U.Call(p.handle,"GetCurrentCharges"),U.Call(p.handle,"GetCooldownTimeRemaining");
        local spent=U.Number(charges) and U.Number(p.before.charges) and charges<p.before.charges;
        local cooldown=U.Number(cd) and U.Number(p.before.cd) and cd>p.before.cd+.05;
        if spent or cooldown then
            M.Emit(s,"resource_change_observed",{ability=name,evidence=spent and "charges_decreased" or "cooldown_increased",hit="unknown"});s.pending[name]=nil;
        elseif now-p.at>C.item_confirmation_s then
            M.Emit(s,"outcome_unknown",{ability=name,reason="no_resource_confirmation"});s.pending[name]=nil;
        end;
    end;
end;
return M;
