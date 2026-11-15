-- Independent bounded ownership; no stop or movement commands.
local ok,Phase=pcall(require,GetScriptDirectory().."/laning/vision/service");
local watch,blockedUntil,nextError=nil,-math.huge,-math.huge;
local function now() local ok,t=pcall(DotaTime);return ok and type(t)=="number" and t or nil end;
local function report(name,err)
 local t=now();if t and t<nextError then return end;nextError=(t or 0)+5;
 print('[MIDBOT ward_mode] callback='..name..' error='..tostring(err):sub(1,240));
end;
local function leave(reason)
 watch=nil;
 if ok then local success,err=pcall(Phase.Leave,GetBot(),reason);if not success then report('Leave',err) end end;
end;
local function invoke(name,...)
 if not ok then report('load',Phase);return nil end;
 local success,value=pcall(Phase[name],...);
 if not success then report(name,value);return nil end;
 return value;
end;
local function retire(reason,t)
 blockedUntil=t<=30 and 30.1 or t+15;
 print('[MIDBOT ward_mode] release='..reason..' time='..t..' retry_after='..blockedUntil);
 leave(reason);return false;
end;
local function bounded(bot)
 local t=now();if not t or t<blockedUntil then return false end;
 local success,p=pcall(function() return bot:GetLocation() end);
 if not success or not p then return retire('position_unavailable',t) end;
 if not watch then watch={start=t,progress=t,x=p.x,y=p.y} end;
 if (p.x-watch.x)^2+(p.y-watch.y)^2>=40^2 then watch.x,watch.y,watch.progress=p.x,p.y,t end;
 if t-watch.start>=8 then return retire('mode_total_budget',t) end;
 if t-watch.progress>=2 then return retire('mode_no_progress',t) end;
 return true;
end;
function GetDesire()
 local t=now();if not t or t<blockedUntil then return 0 end;
 local bot=GetBot();
 if bot:GetActiveMode()==BOT_MODE_WARD and not bounded(bot) then return 0 end;
 local d=invoke('GetDesire',bot);
 if type(d)~='number' then retire('desire_unavailable',t);return 0 end;
 return d;
end;
function OnStart()
 local t=now();if not t or t<blockedUntil then return end;
 if bounded(GetBot()) then invoke('Start',GetBot()) end;
end;
function Think() local bot=GetBot();if bounded(bot) then invoke('Think',bot) end end;
function OnEnd() leave('mode_ended') end;
