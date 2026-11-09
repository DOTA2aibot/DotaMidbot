-- Due time opens an opportunity; it never forces an order during combat/farm.
local C=require(GetScriptDirectory().."/laning/vision/config");
local M={};
function M.Slot(now)
    if type(now)~="number" or now~=now or now<C.pregame_start_s or now>C.lane_end_s then return nil end;
    local slot=0;
    for i,t in ipairs(C.refresh_times) do if now>=t then slot=i end end;
    return slot;
end;
function M.RuneWindow(now)
    if type(now)~="number" or now<120-C.phase_rune_guard_s then return false end;
    local phase=now%120;
    return phase>=120-C.phase_rune_guard_s or phase<C.phase_rune_guard_s;
end;
return M;
