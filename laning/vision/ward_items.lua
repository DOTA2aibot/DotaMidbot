local U=require(GetScriptDirectory().."/laning/tactical/util");
local M={};
function M.Kind(name)
    if name=="npc_dota_observer_wards" or name=="item_ward_observer" then return "observer" end;
    if name=="npc_dota_sentry_wards" or name=="item_ward_sentry" then return "sentry" end;
end;
function M.Charges(item,kind)
    if item==nil then return 0 end;
    local name=U.Call(item,"GetName");if type(name)~="string" then return nil end;
    if name~="item_ward_dispenser" and M.Kind(name)~=kind then return 0 end;
    local n=U.Call(item,name=="item_ward_dispenser" and kind=="sentry" and "GetSecondaryCharges" or "GetCurrentCharges");
    if U.Number(n) and n>=0 and n==math.floor(n) then return n end;
end;
function M.Find(bot,kind,first,last)
    for slot=first or 0,last or 5 do local item=U.Call(bot,"GetItemInSlot",slot);local n=M.Charges(item,kind);
        if n and n>0 then return item,slot,n end;
    end;
end;
function M.Stock(bot,kind)
    local out={active=0,backpack=0,stash=0,courier=0,total=0};
    local function slots(unit,last,courier)
        for slot=0,last do
            local ok,item=pcall(function() return unit:GetItemInSlot(slot) end);if not ok then return false end;
            local n=M.Charges(item,kind);if n==nil then return false end;
            local key=courier and "courier" or (slot<=5 and "active" or (slot<=8 and "backpack" or "stash"));
            out[key]=out[key]+n;out.total=out.total+n;
        end;return true;
    end;
    if not slots(bot,14,false) then return nil end;
    local count=U.Global("GetNumCouriers");local id=U.Call(bot,"GetPlayerID");
    if not U.Number(count) or count<0 or not U.Number(id) then return nil end;
    for i=0,count-1 do local c=U.Global("GetCourier",i);local owner=U.Call(c,"GetPlayerID");
        if not U.Number(owner) or (owner==id and not slots(c,8,true)) then return nil end;
    end;return out;
end;
function M.Allied(kind,point,radius)
    local raw=UNIT_LIST_ALLIED_WARDS~=nil and U.Global("GetUnitList",UNIT_LIST_ALLIED_WARDS);
    if type(raw)~="table" then return nil,"allied_ward_api_unknown" end;
    local out={};for _,w in ipairs(raw) do
        if M.Kind(U.Call(w,"GetUnitName"))==kind and U.Call(w,"IsAlive")==true then
            local p=U.Pos(w);if not p then return nil,"ward_location_unknown" end;
            if not point or U.Distance(point,p)<=radius then out[#out+1]={handle=w,location=p} end;
        end;
    end;return out;
end;
return M;
