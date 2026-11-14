local U=require(GetScriptDirectory().."/laning/tactical/util");
local C=require(GetScriptDirectory().."/laning/vision/config");
local Profile=require(GetScriptDirectory().."/laning/profile");
local M={};local fixed={};
local function height(p)
    local h=p and U.Global("GetHeightLevel",U.Vector(p));
    if U.Number(h) and h>=0 and h<=5 then return h end;
end;
function M.Radiant(bot)
    return C.enabled and TEAM_RADIANT~=nil and U.Actor(bot) and U.Call(bot,"GetTeam")==TEAM_RADIANT;
end;
function M.Participant(bot)
    local team=U.Call(bot,"GetTeam");
    return C.enabled and U.Actor(bot) and ((TEAM_RADIANT~=nil and team==TEAM_RADIANT) or (TEAM_DIRE~=nil and team==TEAM_DIRE));
end;
function M.ObserverSupported(bot)
    return M.Radiant(bot) or (M.Participant(bot) and TEAM_DIRE~=nil and U.Call(bot,"GetTeam")==TEAM_DIRE and U.Point(C.dire_fixed_location)~=nil);
end;
function M.Context(bot)
    if not M.ObserverSupported(bot) then return nil,"observer_team_or_coordinate_unavailable" end;
    if Profile.wards_enabled~=true or Profile.runtime_enabled==true then return nil,"vision_profile_disabled" end;
    local now=U.Now();if not now or now>C.lane_end_s then return nil,"outside_laning_window" end;
    if U.Call(bot,"IsAlive")~=true then return nil,"not_alive" end;
    local p=U.Pos(bot);local center=U.Point(U.Global("GetLocationAlongLane",LANE_MID,.5));
    if not p or not center then return nil,"mid_location_unknown" end;
    if U.Distance(p,center)>C.mid_radius then return nil,"not_mid" end;
    return {now=now,position=p,center=center};
end;
function M.Geometry(bot)
    local dire=bot and TEAM_DIRE~=nil and U.Call(bot,"GetTeam")==TEAM_DIRE;
    local key=dire and "dire" or "radiant";if fixed[key] then return fixed[key] end;
    local calibration=C.calibration_source;if dire then calibration=C.dire_calibration_source end;
    -- No grid fallback: the human supplied this exact XY for the current map.
    local q=U.Point(dire and C.dire_fixed_location or C.fixed_location);
    if dire and not U.Point(C.dire_fixed_location) then return nil,"dire_coordinate_not_calibrated" end;
    local mid=U.Point(U.Global("GetLocationAlongLane",LANE_MID,C.mid_fraction));
    local h=height(q);
    if not q or not mid or h==nil then return nil,"fixed_coordinate_terrain_unknown" end;
    local ground=U.Global("GetGroundHeight",U.Vector(q));
    if U.Number(ground) then q.z=ground end;
    if RUNE_POWERUP_1==nil or RUNE_POWERUP_2==nil then return nil,"rune_landmark_unknown" end;
    local runes={U.Point(U.Global("GetRuneSpawnLocation",RUNE_POWERUP_1)),U.Point(U.Global("GetRuneSpawnLocation",RUNE_POWERUP_2))};
    if not runes[1] or not runes[2] then return nil,"rune_landmark_unknown" end;
    local i=U.Distance(q,runes[1])<=U.Distance(q,runes[2]) and 1 or 2;
    fixed[key]={location=q,height=h,rune_location=runes[i],rune=i==1 and RUNE_POWERUP_1 or RUNE_POWERUP_2,
        lane={mid,U.Point(U.Global("GetLocationAlongLane",LANE_MID,.5))},expected_coverage=calibration and "human_calibrated_point_sf_placement_unverified" or "user_coordinate_visibility_unverified",fixed=true,
        rune_distance=U.Distance(q,runes[i]),rune_in_nominal_range=U.Distance(q,runes[i])<=C.vision_radius};
    return fixed[key];
end;
function M.Get(bot)
    local ctx,why=M.Context(bot);if not ctx then return nil,why end;return M.Geometry(bot);
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
