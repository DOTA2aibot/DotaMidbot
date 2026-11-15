local scenario=assert(PURCHASE_BUILD_SCENARIO);local n=0;
local function eq(a,b) assert(a==b,tostring(a)..' ~= '..tostring(b)) end;
local function test(name,fn) fn();n=n+1;print('PASS BUILD04 '..name) end;

test('full build reuses starter branch and Boots and survives immediate YashaKaya assembly',function()
 local slots={};local bag={};
 local recipes={item_magic_wand={'item_magic_stick','item_branches','item_branches','item_recipe_magic_wand'},
  item_power_treads={'item_boots','item_gloves','item_belt_of_strength'},
  item_yasha={'item_blade_of_alacrity','item_boots_of_elves','item_recipe_yasha'},
  item_kaya={'item_staff_of_wizardry','item_robe','item_recipe_kaya'},
  item_yasha_and_kaya={'item_yasha','item_kaya'},
  item_black_king_bar={'item_ogre_axe','item_mithril_hammer','item_recipe_black_king_bar'},
  item_lesser_crit={'item_broadsword','item_blades_of_attack','item_recipe_lesser_crit'},
  item_greater_crit={'item_lesser_crit','item_demon_edge','item_recipe_greater_crit'}};
 local function assemble()
  local changed=true;
  while changed do changed=false;
   for target,parts in pairs(recipes) do
    local needs={};for _,part in ipairs(parts) do needs[part]=(needs[part] or 0)+1 end;
    local ready=true;for name,count in pairs(needs) do if (bag[name] or 0)<count then ready=false end end;
    if ready then
     for name,count in pairs(needs) do bag[name]=bag[name]-count end;
     bag[target]=(bag[target] or 0)+1;changed=true;
    end;
   end;
  end;
  for i=0,14 do slots[i]=nil end;
  local i=0;for name,count in pairs(bag) do for _=1,count do slots[i]=name;i=i+1 end end;assert(i<=15);
 end;
 local s=scenario({slots=slots,recipe=function(name) return recipes[name] and {recipes[name]} or {} end,
  purchase=function(_,name) bag[name]=(bag[name] or 0)+1;assemble();return 0 end});
 for _=1,100 do s:tick() end;
 local counts={};for _,name in ipairs(s.calls) do counts[name]=(counts[name] or 0)+1 end;
 eq(counts.item_boots,1);eq(counts.item_branches,2);eq(counts.item_recipe_yasha,1);eq(counts.item_recipe_kaya,1);
 eq(counts.item_recipe_magic_wand,1);eq(bag.item_yasha_and_kaya,1);eq(bag.item_power_treads,1);
 eq(bag.item_greater_crit,1);eq(bag.item_lesser_crit,0);eq(counts.item_recipe_lesser_crit,1);eq(bag.item_black_king_bar,1);eq(bag.item_blink,1);eq(s.nextCost,0);
 eq(table.concat(s.calls,','),'item_tango,item_ward_observer,item_branches,item_bottle,item_boots,item_magic_stick,item_branches,item_recipe_magic_wand,item_gloves,item_belt_of_strength,item_blade_of_alacrity,item_boots_of_elves,item_recipe_yasha,item_staff_of_wizardry,item_robe,item_recipe_kaya,item_blink,item_ogre_axe,item_mithril_hammer,item_recipe_black_king_bar,item_broadsword,item_blades_of_attack,item_recipe_lesser_crit,item_demon_edge,item_recipe_greater_crit');
 for _,line in ipairs(s.logs) do assert(not line:find('ERROR',1,true)) end;
end);

test('supplemental mana and HP callbacks wait for Bottle while ward startup remains independent',function()
 local calls={mana=0,health=0,sentry=0,ward=0};local seenBottle=false;local sent=false;
 local s=scenario({modules={
  ['laning/economy/mana']={TryPurchase=function() assert(seenBottle);calls.mana=calls.mana+1;return false end},
  ['laning/economy/health_supply']={TryPurchase=function() assert(seenBottle);calls.health=calls.health+1;return false end},
  ['laning/vision/sentry']={TryStartup=function()
   if not sent then sent=true;calls.sentry=calls.sentry+1;return true end;return false end,
   TryPurchase=function() return false end},
  ['laning/vision/supply']={TryPurchase=function() calls.ward=calls.ward+1;return false end},
 },purchase=function(_,name) if name=='item_bottle' then seenBottle=true end;return 0 end});
 for _=1,6 do s:tick() end;eq(calls.mana,0);eq(calls.health,0);eq(calls.sentry,1);
 for _=1,35 do s:tick() end;assert(calls.mana>0 and calls.health>0 and calls.ward>0);
end);
print('BUILD04 PASSED '..n..' tests; synthetic recipes, not live client assembly');
