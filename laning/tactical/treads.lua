-- One PT intent survives callbacks; observed state, not a per-frame toggle race.
local U=require(GetScriptDirectory().."/laning/tactical/util");
local C=require(GetScriptDirectory().."/laning/tactical/config");
local B=require(GetScriptDirectory().."/laning/tactical/broker");
local M={};
local function attribute(name) return C.treads_raw_states and C.treads_raw_states[name] end;
local function switch(bot,s,wanted,reason,key,item)
    if not C.treads or not U.CanUse(bot) or not U.Number(wanted) then return false,false end;
    item=item or U.Item(bot,"item_power_treads");if not U.Ready(item) then return true,false end;
    local stat=U.Call(item,"GetPowerTreadsStat");if not U.Number(stat) then return true,false end;
    if stat==wanted then s.pt_plan=nil;return true,false end;
    if U.Now()<(s.pt_pause_until or -math.huge) then return true,false end;
    if not s.pt_plan or s.pt_plan.key~=key or s.pt_plan.wanted~=wanted then
        s.pt_plan={at=U.Now(),attempts=0,key=key,last=stat,wanted=wanted};
    end;
    local plan=s.pt_plan;
    if plan.last~=stat then B.Emit(s,"treads_state_observed",{stat=stat,wanted=wanted});plan.last=stat;plan.waiting=false end;
    if plan.attempts>=C.treads_max_toggles or U.Now()-plan.at>C.treads_timeout then
        B.Emit(s,"treads_plan_unknown",{reason="bounded_transition_timeout",stat=stat,wanted=wanted});
        s.pt_plan=nil;s.pt_pause_until=U.Now()+2;return true,false;
    end;
    if U.Now()<(s.pt_next_toggle or -math.huge) or plan.waiting then return false,false end;
    local done=B.Self(bot,s,item,reason,false);
    if done then plan.attempts=plan.attempts+1;plan.waiting=true;s.pt_next_toggle=U.Now()+C.treads_toggle_interval end;
    return false,done;
end;
-- Ordinary casts NEVER wait for PT. A hint is usable only after abilities had their turn.
function M.Before(bot,s,ability)
    if not C.treads then return true end;
    if not U.CanUse(bot) then return false end;
    if not U.Item(bot,"item_power_treads") then s.pt_spell=nil;s.pt_plan=nil;s.pt_hint=nil;return true,false end;
    s.pt_hint={ability=ability,at=U.Now(),cd=U.Call(ability,"GetCooldownTimeRemaining")};
    return true,false;
end;
-- Explicit resource recovery only: the spell cannot currently be paid for.
function M.PrepareMana(bot,s,ability)
    if not C.treads then return true end;
    if not U.CanUse(bot) then return false end;
    local item=U.Item(bot,"item_power_treads");
    -- No PT means no preparation lease: never hold the next Raze for absent boots.
    if not item then s.pt_spell=nil;s.pt_plan=nil;return true,false end;
    -- Reserve BEFORE the first toggle. Idle AGI/STR must not undo this transition.
    local q=s.pt_spell;
    if not q or q.ability~=ability then
        if q and not q.submitted_at and U.Now()-q.selected_at<C.treads_intent_s then return false end;
        q={ability=ability,selected_at=U.Now(),cd=U.Call(ability,"GetCooldownTimeRemaining")};s.pt_spell=q;
    end;
    local wanted=attribute("INTELLECT");if wanted==nil then return true end;
    local ready,issued=switch(bot,s,wanted,"before_spell_stat",ability,item);
    if ready then q.ready=true end;return ready,issued;
end;
function M.NoteCast(s,a)
    local hint=s.pt_hint;
    if hint and hint.ability==a then
        s.pt_spell={ability=a,selected_at=hint.at,cd=hint.cd,submitted_at=U.Now()};
    elseif s.pt_spell and s.pt_spell.ability==a then s.pt_spell.submitted_at=U.Now() end;
    s.pt_hint=nil;s.pt_plan=nil;
end;
function M.ForRegen(bot,s)
    -- Bottle must not wait for attribute optimisation either. Idle maintenance uses AGI.
    return true,false;
end;
function M.CanPrepareMana(bot)
    local item=U.Item(bot,"item_power_treads");local stat=U.Call(item,"GetPowerTreadsStat");
    return C.treads and U.Ready(item) and U.Number(stat) and stat~=attribute("INTELLECT");
end;
function M.Release(s) s.pt_spell=nil;s.pt_hint=nil;s.pt_restore=true end;
function M.Tick(bot,s)
    if not C.treads then return false end;
    local item=U.Item(bot,"item_power_treads");
    if not item then s.pt_spell=nil;s.pt_plan=nil;s.pt_hint=nil;return false end;
    local q=s.pt_spell;
    if q then
        local phase=U.Call(q.ability,"IsInAbilityPhase");local cd=U.Call(q.ability,"GetCooldownTimeRemaining");
        if phase==true then q.phase_seen=true;return false end;
        if q.submitted_at and ((q.phase_seen and phase==false) or (U.Number(cd) and U.Number(q.cd) and cd>q.cd+.05)) then M.Release(s)
        elseif U.Now()-q.selected_at>C.treads_intent_s then M.Release(s)
        else return false end;
    end;
    local hint=s.pt_hint;
    local prepare=hint and U.Now()-hint.at<=C.treads_hint_s and U.Ready(hint.ability)
        and (U.Cost(hint.ability) or 0)>0;
    local wanted=attribute(prepare and "INTELLECT" or "AGILITY");
    local ready,issued=switch(bot,s,wanted,prepare and "idle_spell_hint" or "farm_agility",prepare and hint.ability or "idle",item);
    if ready then s.pt_restore=nil end;return issued;
end;
return M;
