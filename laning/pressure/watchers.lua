local U=require(GetScriptDirectory().."/laning/tactical/util");
local B=require(GetScriptDirectory().."/laning/tactical/broker");
local Profile=require(GetScriptDirectory().."/laning/profile");
local M={};
function M.Tick(bot,s)
    if Profile.ignore_watchers~=true or not U.Actor(bot) or not s then return false end;
    local ability=U.Call(bot,"GetCurrentActiveAbility");
    if U.Call(ability,"GetName")=="ability_lamp_use" and U.Call(bot,"IsChanneling")==true then
        local now=U.Now();
        if now and now>=(s.next_watcher_diagnostic or -math.huge) then
            s.next_watcher_diagnostic=now+10;
            B.Emit(s,"watcher_unexpected_capture",{mode=U.Call(bot,"GetActiveMode"),
                reason="watcher_mode_override_not_observed",orders_issued=false});
        end;
    end;
    -- Never ClearActions here: native WATCHER desire immediately restarts capture.
    -- Selection is disabled in mode_watcher_nevermore; this hook is diagnostic only.
    return false;
end;
return M;
