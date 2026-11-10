-- Primary windows and bounded recovery windows share one per-bot schedule.
local C=require(GetScriptDirectory().."/laning/vision/config");
local M={};
function M.Key(w) return w and (w.key or ("primary:"..tostring(w.slot))) end;
function M.Stopped(now,s) return not now or now>=C.recovery_end_s or (s and s.vision_final_ward==true) end;
function M.Completed(s,w)
    return s and w and ((s.vision_completed and s.vision_completed[M.Key(w)]) or s.vision_done_slot==w.slot) or false;
end;
function M.Primary(now)
    if type(now)~="number" or now~=now then return nil end;
    for i,w in ipairs(C.windows) do if now>=w.start and now<=w.finish then
        return {slot=i-1,key="primary:"..(i-1),kind="primary",start=w.start,finish=w.finish};
    end end;
end;
function M.Window(now,s)
    if M.Stopped(now,s) then return nil end;
    local primary=M.Primary(now);if primary then return primary end;
    local w=s and s.vision_recovery;
    if w and now>=w.start and now<=w.finish then return w end;
end;
function M.Slot(now,s) local w=M.Window(now,s);return w and w.slot end;
function M.NextCheck(now)
    local t=math.floor(now/60)*60+45;if t<=now then t=t+60 end;return t;
end;
function M.NextWindow(now)
    local start=(math.floor(now/60)+1)*60;if start>=C.recovery_end_s then return nil end;
    local primary=M.Primary(start);if primary then return primary end;
    return {slot=100+start/60,key="recovery:"..start,kind="recovery",start=start,finish=start+30};
end;
function M.Request(now,s)
    if type(now)~="number" or now~=now or M.Stopped(now,s) then return nil end;
    for i,w in ipairs(C.windows) do
        if now>=w.start-C.prefetch_s and now<=w.finish then
            local out={slot=i-1,key="primary:"..(i-1),kind="primary",start=w.start,finish=w.finish};
            if not M.Completed(s,out) then return out end;
        end;
    end;
    local w=s and s.vision_recovery;
    if w and now<=w.finish and not M.Completed(s,w) then return w end;
    local request=s and s.vision_recovery_purchase;
    if request and request.authorized and now<request.expires then return request.window end;
end;
function M.Confirmed(s,w,now)
    if not s or not w then return end;
    s.vision_done_slot=w.slot;s.vision_completed=s.vision_completed or {};s.vision_completed[M.Key(w)]=true;
    s.vision_recovery=nil;s.vision_recovery_purchase=nil;
    if now>=C.final_window_start_s then s.vision_final_ward=true end;
end;
function M.Windows(s)
    local all={};for i,w in ipairs(C.windows) do all[#all+1]={slot=i-1,key="primary:"..(i-1),kind="primary",start=w.start,finish=w.finish} end;
    for _,w in ipairs(s and s.vision_recovery_history or {}) do all[#all+1]=w end;return all;
end;
return M;
