-- Installed only for the test team containing the controlled SF.
-- This replaces native non-SF shopping; it is not a selective Valve filter.
local ok,Shop=pcall(require,GetScriptDirectory().."/laning/testing/ally_shop");
local nextError=-math.huge;
function ItemPurchaseThink()
    if ok then
        local success,err=pcall(Shop.Tick,GetBot());
        if not success and GameTime()>=nextError then print("[MIDBOT ally_shop] ERROR "..tostring(err));nextError=GameTime()+10 end;
    end;
end;
