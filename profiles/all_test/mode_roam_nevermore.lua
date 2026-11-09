-- Explicit personal ROAM replacement only in the courier-guard test profile.
local ok,Guard=pcall(require,GetScriptDirectory().."/laning/items/delivery_guard");
local function invoke(name,...)
    if not ok then return nil end;
    local success,value=pcall(Guard[name],...);
    if not success then pcall(Guard.Leave,GetBot(),"callback_error");return nil end;
    return value;
end;
function GetDesire() local d=invoke("GetDesire",GetBot());return type(d)=="number" and d or 0 end;
function OnStart() invoke("Start",GetBot()) end;
function Think() invoke("Think",GetBot()) end;
function OnEnd() invoke("Leave",GetBot(),"mode_ended") end;
