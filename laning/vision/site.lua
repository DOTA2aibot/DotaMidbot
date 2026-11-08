local U=require(GetScriptDirectory().."/laning/tactical/util");
local C=require(GetScriptDirectory().."/laning/vision/config");
local Profile=require(GetScriptDirectory().."/laning/profile");
local M={};local fixed,nextSearch,lastReason;
local function height(p)
    local h=p and U.Global("GetHeightLevel",U.Vector(p));
    if U.Number(h) and h>=0 and h<=5 then return h end;
end;
function M.Radiant(bot)
    return C.enabled and TEAM_RADIANT~=nil and U.Actor(bot) and U.Call(bot,"GetTeam")==TEAM_RADIANT;
end;
function M.Context(bot)
    if not M.Radiant(bot) then return nil,"not_radiant_sf" end;
    if Profile.wards_enabled~=true or Profile.runtime_enabled==true then return nil,"vision_profile_disabled" end;
    local now=U.Now();if not now or now>C.lane_end_s then return nil,"outside_laning_window" end;
    if U.Call(bot,"IsAlive")~=true then return nil,"not_alive" end;
    local p=U.Pos(bot);local center=U.Point(U.Global("GetLocationAlongLane",LANE_MID,.5));
    if not p or not center then return nil,"mid_location_unknown" end;
    if U.Distance(p,center)>C.mid_radius then return nil,"not_mid" end;
    return {now=now,position=p,center=center};
end;
local function clear(a,b,h,trees)
    for i=0,16 do
        local p={x=a.x+(b.x-a.x)*i/16,y=a.y+(b.y-a.y)*i/16};
        local v=height(p);if v==nil or v>h then return false end;
    end;
    local dx,dy=b.x-a.x,b.y-a.y;local len=dx*dx+dy*dy;
    if len<=1 then return true end;
    for _,p in ipairs(trees) do
        local t=((p.x-a.x)*dx+(p.y-a.y)*dy)/len;
        if t>=0 and t<=1 and U.Distance(p,{x=a.x+t*dx,y=a.y+t*dy})<C.tree_corridor then return false end;
    end;
    return true;
end;
function M.Get(bot)
    local ctx,why=M.Context(bot);if not ctx then return nil,why end;
    if fixed then return fixed end;
    if nextSearch and ctx.now<nextSearch then return nil,lastReason end;
    nextSearch=ctx.now+C.geometry_retry_s;
    local bank=U.Point(U.Global("GetLocationAlongLane",LANE_MID,C.bank_fraction));
    local mid=U.Point(U.Global("GetLocationAlongLane",LANE_MID,C.mid_fraction));
    local bankHeight=height(bank);
    if not bank or not mid then
        lastReason="radiant_bank_geometry_unknown";return nil,lastReason;
    end;
    if RUNE_POWERUP_1==nil or RUNE_POWERUP_2==nil then lastReason="rune_landmark_unknown";return nil,lastReason end;
    local runes={U.Point(U.Global("GetRuneSpawnLocation",RUNE_POWERUP_1)),U.Point(U.Global("GetRuneSpawnLocation",RUNE_POWERUP_2))};
    if not runes[1] or not runes[2] then lastReason="rune_landmark_unknown";return nil,lastReason end;
    -- Lane fractions are anchors, not terrain classes: .45 may still be water
    -- and .50 can already be a bank. River spawn terrain is the actual reference.
    local r1,r2=height(runes[1]),height(runes[2]);
    if r1==nil or r2==nil then lastReason="rune_water_geometry_unknown";return nil,lastReason end;
    local river=math.min(r1,r2);
    local ids=U.Global("GetAllTrees");local trees={};
    if type(ids)~="table" or #ids>C.max_tree_ids then lastReason="tree_geometry_unknown";return nil,lastReason end;
    for _,id in ipairs(ids) do
        local p=U.Point(id); -- API bindings may expose points or numeric tree IDs.
        if not p and U.Number(id) then p=U.Point(U.Global("GetTreeLocation",id)) end;
        if not p then lastReason="tree_geometry_unknown";return nil,lastReason end;
        if U.Distance(p,bank)<=C.vision_radius+C.search_radius then trees[#trees+1]=p end;
    end;
    local best,score;
    for dx=-C.search_radius,C.search_radius,C.search_step do
        for dy=-C.search_radius,C.search_radius,C.search_step do
            local q={x=bank.x+dx,y=bank.y+dy};local h=height(q);
            if h and h>river and (not bankHeight or h>=bankHeight) and U.Distance(q,bank)<=C.search_radius
                and U.Distance(q,mid)<=C.vision_radius-C.vision_margin and clear(q,mid,h,trees) then
                for i,rune in ipairs(runes) do
                    if U.Distance(q,rune)<=C.vision_radius-C.vision_margin and clear(q,rune,h,trees) then
                        local value=U.Distance(q,bank)+.1*U.Distance(q,mid)+.01*U.Distance(q,rune);
                        if not score or value<score then
                            best={location=q,height=h,rune_location=rune,rune=i==1 and RUNE_POWERUP_1 or RUNE_POWERUP_2,
                                lane={mid,ctx.center},expected_coverage="radiant_bank_rune_geometry_model",fixed=true};score=value;
                        end;
                    end;
                end;
            end;
        end;
    end;
    fixed=best;lastReason=best and nil or "no_radiant_bank_rune_view_candidate";
    return fixed,lastReason;
end;
function M.Wards()
    if UNIT_LIST_ALLIED_WARDS==nil then return nil end;
    local list=U.Global("GetUnitList",UNIT_LIST_ALLIED_WARDS);if type(list)~="table" then return nil end;
    local out={};for _,w in ipairs(list) do
        if U.Call(w,"GetUnitName")=="npc_dota_observer_wards" and U.Call(w,"IsAlive")==true then
            local p=U.Pos(w);if not p then return nil end;
            out[#out+1]={handle=w,location=p};
        end;
    end;return out;
end;
function M.Existing(spot)
    local list=M.Wards();if not list then return nil,"ward_data_unknown" end;
    for _,w in ipairs(list) do if U.Distance(w.location,spot.location)<=C.dedup_radius then return w end end;
    return false;
end;
return M;
