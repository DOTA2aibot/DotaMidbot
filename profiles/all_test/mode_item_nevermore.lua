-- Whole SF ITEM-mode replacement in all_test; no implicit native fallback.
local ok,Mode=pcall(require,GetScriptDirectory().."/laning/items/delivery_mode");
local function invoke(name,...)
    if not ok then return nil end;
    local success,value=pcall(Mode[name],...);
    if not success then pcall(Mode.Leave,GetBot(),"callback_error");return nil end;
    return value;
end;
function GetDesire() local d=invoke("GetDesire",GetBot());return type(d)=="number" and d or 0 end;
function OnStart() invoke("Start",GetBot()) end;
function Think() invoke("Think",GetBot()) end;
function OnEnd() invoke("Leave",GetBot(),"mode_ended") end;
