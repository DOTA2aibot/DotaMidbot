-- Explicit SF ward-mode replacement, only shipped with ward-phase profiles.
local ok,Phase=pcall(require,GetScriptDirectory().."/laning/vision/phase");
local function invoke(name,...)
    if not ok then return nil end;
    local success,value=pcall(Phase[name],...);
    if not success then pcall(Phase.Leave,GetBot(),"callback_error");return nil end;
    return value;
end;
function GetDesire() local d=invoke("GetDesire",GetBot());return type(d)=="number" and d or 0 end;
function OnStart() invoke("Start",GetBot()) end;
function Think() invoke("Think",GetBot()) end;
function OnEnd() invoke("Leave",GetBot(),"mode_ended") end;
