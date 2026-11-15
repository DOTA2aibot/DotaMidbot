-- Low-priority discard, 15:00 <= time < 18:00. Never walk, sell or attack an item.
local U=require(GetScriptDirectory().."/laning/tactical/util");
local B=require(GetScriptDirectory().."/laning/tactical/broker");
local P=require(GetScriptDirectory().."/laning/profile");
local M={};
local consumables={item_tango=true,item_tango_single=true,item_flask=true,item_clarity=true,
 item_enchanted_mango=true,item_faerie_fire=true,item_ward_observer=true,item_ward_sentry=true,
 item_ward_dispenser=true,item_smoke_of_deceit=true,item_dust=true,item_blood_grenade=true};
function M.Tick(bot,s)
 local now=U.Now();
 if not s or not U.Number(now) or now<900 or now>=1080 or P.economy_enabled~=true
  or not U.Actor(bot) or not U.CanUse(bot) or not B.Free(s) or now<(s.cleanup_after or -math.huge) then return false end;
 s.cleanup_after=now+1;
 if s.pressure or s.vision_phase or s.vision_support or s.ward_pending or s.raze_cast or s.pt_spell or s.delivery_pickup then return false end;
 local mode=U.Call(bot,"GetActiveMode");local action=U.Call(bot,"GetCurrentActionType");
 local idleMode=(BOT_MODE_NONE~=nil and mode==BOT_MODE_NONE) or (BOT_MODE_LANING~=nil and mode==BOT_MODE_LANING)
  or (BOT_MODE_FARM~=nil and mode==BOT_MODE_FARM);
 local idleAction=(BOT_ACTION_TYPE_IDLE~=nil and action==BOT_ACTION_TYPE_IDLE)
  or (BOT_ACTION_TYPE_NONE~=nil and action==BOT_ACTION_TYPE_NONE);
 if not idleMode or not idleAction or U.Call(bot,"NumQueuedActions")~=0 then return false end;
 local hp=U.HP(bot);local recent=U.Call(bot,"TimeSinceDamagedByAnyHero");
 if not hp or hp<.6 or not U.Number(recent) or recent<4 then return false end;
 local groups={U.Call(bot,"GetNearbyHeroes",1200,true,BOT_MODE_NONE),U.Call(bot,"GetNearbyTowers",1000,true),
  U.Call(bot,"GetNearbyLaneCreeps",900,true),U.Call(bot,"GetNearbyNeutralCreeps",700)};
 -- Explicit indexed checks: nil query results must not truncate ipairs and imply safety.
 for i=1,4 do
  if type(groups[i])~="table" then return false end;
  for _,unit in pairs(groups[i]) do if U.Visible(unit) then return false end end;
 end;
 local pos=U.Pos(bot);if not pos or type(bot.Action_DropItem)~="function" then return false end;
 for _,method in ipairs({"GetTarget","GetAttackTarget"}) do
  local target=U.Call(bot,method);
  if U.Visible(target) then
   local tp=U.Pos(target);if not tp or U.Distance(pos,tp)<=1200 then return false end;
  end;
 end;
 for slot=0,8 do
  local item=U.Call(bot,"GetItemInSlot",slot);local name=U.Call(item,"GetName");
  if item and consumables[name] then
   local cost=U.Global("GetItemCost",name);
   if U.Number(cost) and cost>=0 and cost<150 then
    s.discarded_items=s.discarded_items or {};s.discarded_items[item]=true;
    return B.Fire(bot,s,"inventory_discard",item,"idle_consumable_under150_15to18",function()
     return bot:Action_DropItem(item,U.Vector(pos));
    end,false);
   end;
  end;
 end;
 return false;
end;
return M;
