local n=0;
local function eq(a,b) assert(a==b,tostring(a)..' ~= '..tostring(b)) end;
local function test(name,fn) fn();n=n+1;print('PASS CLEANUP '..name) end;
local function setup()
 local s=SCENARIO();s.time=900;s.profile=s.env.require('bots/laning/profile');
 s.profile.economy_enabled=true;s.profile.stationary_delivery_enabled=true;s.env.BOT_MODE_ITEM=6;s.env.BOT_MODE_ROAM=3;
 s.env.GetItemCost=function() return 100 end;s.drops={};
 s.env.GetDroppedItemList=function() return s.drops end;
 s.bot.Action_DropItem=function(_,item,pos)
  s.orders[#s.orders+1]={kind='drop',item=item,pos=pos};
  for slot=0,8 do if s.items[slot]==item then s.items[slot]=nil end end;
  item.IsItem=function() return true end;item.IsNull=function() return false end;
  s.drops[#s.drops+1]={item=item,owner=s.bot,location=pos};
 end;
 s.cleanup=s.env.require('bots/laning/items/cleanup');return s;
end;
test('window is 15:00 inclusive and 18:00 exclusive, one order per second',function()
 local s=setup();s:item('item_tango',0);s:item('item_ward_sentry',7);
 s.time=899.9;eq(s.cleanup.Tick(s.bot,s.state),false);s.time=900;
 eq(s.cleanup.Tick(s.bot,s.state),true);eq(#s.orders,1);eq(s.cleanup.Tick(s.bot,s.state),false);
 s.time=901;eq(s.cleanup.Tick(s.bot,s.state),true);eq(#s.orders,2);
 s:item('item_clarity',0);s.time=1080;eq(s.cleanup.Tick(s.bot,s.state),false);eq(#s.orders,2);
end);
test('only whitelisted consumables under150 are discarded, stash and core items survive',function()
 local s=setup();
 for i,name in ipairs({'item_branches','item_magic_stick','item_magic_wand','item_bottle','item_tpscroll','item_blink','item_lesser_crit','item_yasha'}) do s:item(name,i-1) end;
 s:item('item_clarity',9);eq(s.cleanup.Tick(s.bot,s.state),false);
 s.items[0]=nil;s:item('item_clarity',0);s.env.GetItemCost=function() return 150 end;s.time=901;eq(s.cleanup.Tick(s.bot,s.state),false);
 s.env.GetItemCost=function() return 149 end;s.time=902;eq(s.cleanup.Tick(s.bot,s.state),true);eq(#s.orders,1);
end);
test('farm combat movement cast rune retreat pressure and danger always win',function()
 for _,why in ipairs({'creep','neutral','enemy','tower','attack','rune','retreat','gank','cast','queue','pressure','ward','raze','lowhp','recent','target','unknown'}) do
  local s=setup();s:item('item_tango',0);
  if why=='creep' then s.creeps={s.unit('npc_dota_creep_lane',3)}
  elseif why=='neutral' then s.neutrals={s.unit('npc_dota_neutral',4)}
  elseif why=='enemy' then s.heroes={s.unit('npc_dota_hero_lina',3)}
  elseif why=='tower' then s.towers={s.unit('npc_dota_tower',3)}
  elseif why=='attack' then s.action=3 elseif why=='move' then s.action=1
  elseif why=='rune' then s.mode=7 elseif why=='retreat' then s.mode=4 elseif why=='gank' then s.mode=3
  elseif why=='cast' then s.using=true elseif why=='queue' then s.queued=1
  elseif why=='pressure' then s.state.pressure={} elseif why=='ward' then s.state.vision_phase={}
  elseif why=='raze' then s.state.raze_cast={} elseif why=='lowhp' then s.hp=300
  elseif why=='recent' then s.recent=1 elseif why=='target' then s.bot.target=s.unit('npc_dota_hero_lina',3)
  else s.bot.GetNearbyNeutralCreeps=nil end;
  eq(s.cleanup.Tick(s.bot,s.state),false);eq(#s.orders,0);
 end;
end);
test('discarded own item is not picked back up by ground-item mode',function()
 local s=setup();local item=s:item('item_ward_observer',0);
 eq(s.cleanup.Tick(s.bot,s.state),true);eq(s.items[0],nil);eq(s.state.discarded_items[item],true);
 s.time=902;local mode=s.env.require('bots/laning/items/delivery_mode');eq(mode.GetDesire(s.bot),0);eq(#s.orders,1);
end);
test('a stale far target cannot permanently prevent idle cleanup',function()
 local s=setup();s:item('item_tango',0);s.bot.target=s.unit('npc_dota_hero_lina',3,4000,0);
 eq(s.cleanup.Tick(s.bot,s.state),true);
end);
test('push and defense movement no longer starve the mandatory cleanup window',function()
 for _,mode in ipairs({8,10,12,13,17}) do
  local s=setup();s.mode=mode;s.action=s.env.BOT_ACTION_TYPE_MOVE_TO;s:item('item_tango',0);
  eq(s.cleanup.Tick(s.bot,s.state),true);eq(#s.orders,1);eq(s.orders[1].kind,'drop');
 end;
end);
print('CLEANUP PASSED '..n..' tests; no engine idle availability claim');
