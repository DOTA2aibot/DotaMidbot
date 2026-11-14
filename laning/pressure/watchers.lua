local U=require(GetScriptDirectory().."/laning/tactical/util");
local B=require(GetScriptDirectory().."/laning/tactical/broker");
local Profile=require(GetScriptDirectory().."/laning/profile");
local M={};
function M.Tick(bot,s)
    if Profile.ignore_watchers~=true or not U.Actor(bot) or not B.Free(s) then return false end;
    local ability=U.Call(bot,"GetCurrentActiveAbility");local target=U.Call(bot,"GetTarget");
    local mode=U.Call(bot,"GetActiveMode");
    -- Names verified in the installed client's npc_abilities/npc_units, not guessed mode numbers.
    local capture=U.Call(ability,"GetName")=="ability_lamp_use";
    local movingToWatcher=U.Call(target,"GetUnitName")=="npc_dota_watch_tower"
        and (mode==BOT_MODE_SIDE_SHOP or mode==BOT_MODE_ROAM)
        and U.Call(bot,"GetCurrentActionType")==BOT_ACTION_TYPE_MOVE_TO
        and not s.pressure and not s.vision_phase and not s.ward_pending and not s.raze_cast
        and U.Call(bot,"IsUsingAbility")==false and U.Call(bot,"IsChanneling")==false;
    if not capture and not movingToWatcher then return false end;
    if U.Now()<(s.watcher_retry or -math.huge) then return false end;
    s.watcher_retry=U.Now()+1;
    return B.Fire(bot,s,"ignore_watcher",ability,capture and "cancel_exact_watcher_capture" or "cancel_exact_watcher_target",function()
        return bot:Action_ClearActions(true);
    end,false);
end;
return M;
