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
    if not s.pt_plan or s.pt_plan.key~=key then s.pt_plan={at=U.Now(),attempts=0,key=key,last=stat} end;
    local plan=s.pt_plan;
    if plan.last~=stat then B.Emit(s,"treads_state_observed",{stat=stat,wanted=wanted});plan.last=stat end;
    if plan.attempts>=C.treads_max_toggles or U.Now()-plan.at>C.treads_timeout then
        B.Emit(s,"treads_plan_unknown",{reason="bounded_transition_timeout",stat=stat,wanted=wanted});
        s.pt_plan=nil;s.pt_pause_until=U.Now()+2;return true,false;
    end;
    local done=B.Self(bot,s,item,reason,false);
    if done then plan.attempts=plan.attempts+1 end;
    return false,done;
end;
function M.Before(bot,s,ability)
    if not C.treads then return true end;
    local wanted=danger(bot,s) and attribute("STRENGTH") or attribute("INTELLECT");
    if wanted==nil then return true end;
    local ready,issued=switch(bot,s,wanted,"before_spell_stat",ability);
    if ready then s.pt_spell={ability=ability,selected_at=U.Now(),cd=U.Call(ability,"GetCooldownTimeRemaining")} end;
    return ready,issued;
end;
function M.NoteCast(s,a)
    if s.pt_spell and s.pt_spell.ability==a then s.pt_spell.submitted_at=U.Now() end;
end;
function M.Tick(bot,s)
    if not C.treads then return false end;
    local low=danger(bot,s);
    if low and U.CanUse(bot) then
        local _,issued=switch(bot,s,attribute("STRENGTH"),"low_hp_survival","survival");
        if issued then return true end;
    end;
    local q=s.pt_spell;
    if q then
        local phase=U.Call(q.ability,"IsInAbilityPhase");local cd=U.Call(q.ability,"GetCooldownTimeRemaining");
        if phase==true then q.phase_seen=true;return false end;
        if q.submitted_at and ((q.phase_seen and phase==false) or (U.Number(cd) and U.Number(q.cd) and cd>q.cd+.05)) then
            s.pt_spell=nil;s.pt_restore=true;
        elseif U.Now()-q.selected_at>2 then s.pt_spell=nil;s.pt_restore=true
        else return false end;
    end;
    local attack=U.Call(bot,"GetAttackTarget");
    local wanted=low and attribute("STRENGTH") or attribute("AGILITY");
    if not low and not s.pt_restore and not U.Visible(attack) then return false end;
    local ready,issued=switch(bot,s,wanted,low and "low_hp_survival" or "attack_or_after_spell","restore");
    if ready then s.pt_restore=nil end;
    return issued;
end;
return M;
