-- Nominal own resources; unknown restoration is not invented mana.
local U=require(GetScriptDirectory().."/laning/tactical/util");
local B=require(GetScriptDirectory().."/laning/tactical/broker");
local C=require(GetScriptDirectory().."/laning/tactical/config");
local M={};
function M.Read(bot,s)
    local hp,maxhp,mana,maxmana=U.Call(bot,"GetHealth"),U.Call(bot,"GetMaxHealth"),U.Call(bot,"GetMana"),U.Call(bot,"GetMaxMana");
    if not U.Number(hp) or not U.Number(maxhp) or not U.Number(mana) or not U.Number(maxmana) or maxhp<=0 or maxmana<=0 then return nil end;
    local out={hp=hp,max_hp=maxhp,mana=mana,max_mana=maxmana,health_gain=0,mana_gain=0};
    for _,name in ipairs({"item_magic_wand","item_magic_stick"}) do
        local item=U.Item(bot,name);local charges=U.Call(item,"GetCurrentCharges");
        if U.Ready(item) and U.Number(charges) and charges>0 and charges==math.floor(charges) and B.RetryReady(s,name) then
            local per=U.Special(item,{"restore_per_charge"});
            local gain=per and charges*per;
            local mg=gain and math.min(gain,math.max(0,maxmana-mana));local hg=gain and math.min(gain,math.max(0,maxhp-hp));
            if not out.item or (mg or 0)>out.mana_gain then
                out.item=item;out.charges=charges;out.per_charge=per;out.known=gain~=nil;
                out.mana_gain=mg or 0;out.health_gain=hg or 0;
            end;
        end;
    end;
    out.potential_mana=mana+out.mana_gain;out.potential_hp=hp+out.health_gain;return out;
end;
function M.Combat(bot)
    local enemies=U.Call(bot,"GetNearbyHeroes",1100,true,BOT_MODE_NONE);
    if type(enemies)~="table" then return false end;
    for _,e in ipairs(enemies) do if U.Enemy(bot,e) then return true end end;
    return U.Call(bot,"WasRecentlyDamagedByAnyHero",2)==true;
end;
function M.Use(bot,s,p,reason)
    if not p or not p.item or not U.CanUse(bot) or not B.Free(s) then return false end;
    local charges=U.Call(p.item,"GetCurrentCharges");
    if not U.Number(charges) or charges<=0 or not U.Ready(p.item) or not B.RetryReady(s,U.Call(p.item,"GetName")) then return false end;
    B.Emit(s,"combat_resource_decision",{reason=reason,charges=charges,restore_per_charge=p.per_charge,
        nominal_hp_gain=p.health_gain,nominal_mana_gain=p.mana_gain,potential_mana=p.potential_mana,potential_hp=p.potential_hp,
        prediction="nominal_capped_not_guaranteed_after_modifiers"});
    return B.Self(bot,s,p.item,reason,true);
end;
function M.Emergency(bot,s)
    local p=M.Read(bot,s);
    if p and p.item and p.hp/p.max_hp<=C.wand_emergency_hp and M.Combat(bot) then return M.Use(bot,s,p,"combat_hp_15_percent") end;
    return false;
end;
return M;
