local scenario=assert(ECONOMY_REVIEW_SCENARIO);local n=0;
local function eq(a,b) assert(a==b,tostring(a)..' ~= '..tostring(b)) end;
local function setup()
 local s=scenario();s.time=200;s.hp=300;s.items[0]=s:item('item_bottle',0);
 s.health=s.env.require('bots/laning/economy/health_supply');return s;
end;
local function test(name,fn) fn();n=n+1;print('PASS HEALTH '..name) end;
test('one optional salve at low HP with an empty Bottle',function()
 local s=setup();eq(s.health.TryPurchase(s.bot),true);eq(s.calls[1],'item_flask');s.time=220;
 eq(s.health.TryPurchase(s.bot),false);eq(#s.calls,1);
end);
test('no salve without Bottle, with available healing, healthy, or after laning',function()
 for _,kind in ipairs({'no_bottle','charged_bottle','tango_stash','salve_backpack','healthy','late','regen'}) do
  local s=setup();
  if kind=='no_bottle' then s.items[0]=nil
  elseif kind=='charged_bottle' then s.items[0]=s:item('item_bottle',1)
  elseif kind=='tango_stash' then s.items[9]=s:item('item_tango',3)
  elseif kind=='salve_backpack' then s.items[6]=s:item('item_flask',1)
  elseif kind=='healthy' then s.hp=900
  elseif kind=='late' then s.time=601
  else s.regen=true end;
  eq(s.health.TryPurchase(s.bot),false);eq(#s.calls,0);
 end;
end);
test('unknown purchase is not repeated, explicit refusal retries after delay',function()
 local s=setup();s.result=nil;eq(s.health.TryPurchase(s.bot),true);s.time=250;eq(s.health.TryPurchase(s.bot),false);
 s=setup();s.result=4;eq(s.health.TryPurchase(s.bot),true);s.time=202;eq(s.health.TryPurchase(s.bot),false);
 s.time=206;eq(s.health.TryPurchase(s.bot),true);eq(#s.calls,2);
end);
print('HEALTH PASSED '..n..' tests');
