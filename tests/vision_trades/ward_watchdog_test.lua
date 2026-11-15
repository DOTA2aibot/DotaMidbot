local n=0;
local function eq(a,b) assert(a==b,tostring(a)..' ~= '..tostring(b)) end;
local function scenario()
 local s={t=0,x=0,y=0,leaves={},logs={},calls=0};local env=setmetatable({},{__index=_G});
 local bot={GetLocation=function() return {x=s.x,y=s.y} end,GetActiveMode=function() return 22 end};
 env.GetBot=function() return bot end;env.GetScriptDirectory=function() return 'bots' end;
 env.DotaTime=function() return s.t end;env.BOT_MODE_WARD=22;
 env.print=function(line) s.logs[#s.logs+1]=line end;
 env.require=function() return {GetDesire=function() if s.error then error('synthetic ward error') end;return .99 end,
  Start=function() end,Think=function() s.calls=s.calls+1 end,
  Leave=function(_,reason) s.leaves[#s.leaves+1]=reason end} end;
 local f=assert(loadfile('profiles/vision/mode_ward_nevermore.lua'));setfenv(f,env);f();s.env=env;return s;
end;
local function test(name,fn) fn();n=n+1;print('PASS WARD_WATCHDOG '..name) end;
test('stationary startup releases at two seconds and cannot reclaim the first wave window',function()
 local s=scenario();eq(s.env.GetDesire(),.99);s.env.OnStart();s.env.Think();s.t=2;
 eq(s.env.GetDesire(),0);eq(s.leaves[1],'mode_no_progress');s.env.OnEnd();
 for t=3,30 do s.t=t;eq(s.env.GetDesire(),0);s.env.Think() end;eq(s.calls,1);
 s.t=31;eq(s.env.GetDesire(),.99);
end);
test('movement refreshes progress but never exceeds the total eight second budget',function()
 local s=scenario();s.env.OnStart();
 for t=1,7 do s.t=t;s.x=t*100;eq(s.env.GetDesire(),.99);s.env.Think() end;
 s.t=8;s.x=800;eq(s.env.GetDesire(),0);eq(s.leaves[1],'mode_total_budget');
end);
test('helper errors are visible and relinquish desire without any hero commands',function()
 local s=scenario();s.error=true;eq(s.env.GetDesire(),0);
 assert(table.concat(s.logs,'\n'):find('synthetic ward error',1,true));eq(s.calls,0);
end);
print('WARD_WATCHDOG PASSED '..n..' cases; native arbitration remains unverified');
