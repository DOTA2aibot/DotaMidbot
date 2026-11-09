-- Priority ward windows. No catch-up trip outside the configured interval.
local C=require(GetScriptDirectory().."/laning/vision/config");
local M={};
function M.Window(now)
    if type(now)~="number" or now~=now then return nil end;
    for i,w in ipairs(C.windows) do if now>=w.start and now<=w.finish then return {slot=i-1,start=w.start,finish=w.finish} end end;
end;
function M.Slot(now) local w=M.Window(now);return w and w.slot end;
function M.Request(now)
    if type(now)~="number" or now~=now then return nil end;
    for i,w in ipairs(C.windows) do
        if now>=w.start-C.prefetch_s and now<=w.finish then return {slot=i-1,start=w.start,finish=w.finish} end;
    end;
end;
return M;
