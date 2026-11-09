-- One PT intent survives callbacks; observed state, not a per-frame toggle race.
local U=require(GetScriptDirectory().."/laning/tactical/util");
local C=require(GetScriptDirectory().."/laning/tactical/config");
local B=require(GetScriptDirectory().."/laning/tactical/broker");
local M={};
local function attribute(name) return _G["ATTRIBUTE_"..name] or _G["DOTA_ATTRIBUTE_"..name] end;
local function danger(bot,s)
    local hp=U.HP(bot);if not hp then return false end;
    local recent=U.Call(bot,"WasRecentlyDamagedByAnyHero",2)==true;
    if hp<=C.treads_low_hp and recent then s.strength=true end;
    if hp>=C.treads_recover_hp or not recent then s.strength=false end;
    return s.strength==true;
end;
local function switch(bot,s,wanted,reason,key)
    if not C.treads or not U.CanUse(bot) or not U.Number(wanted) then return false,false end;
    local item=U.Item(bot,"item_power_treads");if not U.Ready(item) then return true,false end;
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
function M.Before(bot,s,ability)
    if not C.treads then return true end;
    if not U.CanUse(bot) then return false end;
    -- Reserve BEFORE the first toggle. Idle AGI/STR must not undo this transition.
    local q=s.pt_spell;
    if not q or q.ability~=ability then
        if q and not q.submitted_at and U.Now()-q.selected_at<C.treads_intent_s then return false end;
        q={ability=ability,selected_at=U.Now(),cd=U.Call(ability,"GetCooldownTimeRemaining")};s.pt_spell=q;
    end;
    local wanted=attribute("INTELLECT");if wanted==nil then return true end;
    local ready,issued=switch(bot,s,wanted,"before_spell_stat",ability);
    if ready then q.ready=true end;return ready,issued;
end;
function M.NoteCast(s,a)
    if s.pt_spell and s.pt_spell.ability==a then s.pt_spell.submitted_at=U.Now() end;
end;
function M.ForRegen(bot,s)
    if not C.treads or attribute("AGILITY")==nil then return true,false end;
    return switch(bot,s,attribute("AGILITY"),"before_regeneration","regen");
end;
function M.CanPrepareMana(bot)
    local item=U.Item(bot,"item_power_treads");local stat=U.Call(item,"GetPowerTreadsStat");
    return C.treads and U.Ready(item) and U.Number(stat) and stat~=attribute("INTELLECT");
end;
function M.Release(s) s.pt_spell=nil;s.pt_restore=true end;
function M.Tick(bot,s)
    if not C.treads then return false end;
    local q=s.pt_spell;
    if q then
        local phase=U.Call(q.ability,"IsInAbilityPhase");local cd=U.Call(q.ability,"GetCooldownTimeRemaining");
        if phase==true then q.phase_seen=true;return false end;
        if q.submitted_at and ((q.phase_seen and phase==false) or (U.Number(cd) and U.Number(q.cd) and cd>q.cd+.05)) then M.Release(s)
        elseif U.Now()-q.selected_at>C.treads_intent_s then M.Release(s)
        else return false end;
    end;
    local regen=U.Call(bot,"HasModifier","modifier_bottle_regeneration")==true
        or U.Call(bot,"HasModifier","modifier_fountain_aura_buff")==true;
    local low=not regen and danger(bot,s);
    local wanted=low and attribute("STRENGTH") or attribute("AGILITY");
    local ready,issued=switch(bot,s,wanted,regen and "regeneration_agility" or (low and "low_hp_survival" or "farm_agility"),"idle");
    if ready then s.pt_restore=nil end;return issued;
end;
return M;
