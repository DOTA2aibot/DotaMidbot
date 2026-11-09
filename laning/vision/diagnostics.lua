-- Read only: capture real allied Observer entities, including wards planted by a human.
-- Never infer world coordinates from a photograph and never auto-adopt another player's ward.
local U=require(GetScriptDirectory().."/laning/tactical/util");
local B=require(GetScriptDirectory().."/laning/tactical/broker");
local Site=require(GetScriptDirectory().."/laning/vision/site");
local C=require(GetScriptDirectory().."/laning/vision/config");
local Profile=require(GetScriptDirectory().."/laning/profile");
local M={};
local function geometry(p)
    local data={height_level_raw=U.Global("GetHeightLevel",U.Vector(p)),
        passable=U.Global("IsLocationPassable",U.Vector(p)),ground_z=U.Global("GetGroundHeight",U.Vector(p))};
    local mid=U.Point(U.Global("GetLocationAlongLane",LANE_MID,.5));data.mid_distance=U.Distance(p,mid);
    data.runes={};
    for _,id in ipairs({RUNE_POWERUP_1,RUNE_POWERUP_2}) do
        local q=U.Point(U.Global("GetRuneSpawnLocation",id));
        if q then data.runes[#data.runes+1]={id=id,position=q,distance=U.Distance(p,q),
            within_nominal_vision=U.Distance(p,q)<=C.vision_radius,
            team_visible=U.Global("IsLocationVisible",U.Vector(q))} end;
    end;
    return data;
end;
function M.Tick(bot,s)
    if not s or not Site.Radiant(bot) or Profile.wards_enabled~=true or Profile.runtime_enabled==true then return end;
    local now=U.Now();if not now or now<(s.vision_diag_at or -math.huge) then return end;
    s.vision_diag_at=now+C.diagnostic_interval_s;
    if not s.vision_point_reported then
        local p=U.Point(C.fixed_location);
        if p then
            local data=geometry(p);data.location=p;data.coordinate_status="unverified_user_test_point";
            data.photo_match="not_verified";data.plant_validity="not_tested";data.calibration_only=C.calibration_only==true;
            B.Emit(s,"ward_test_point_geometry",data);s.vision_point_reported=true;
        end;
    end;
    local list=Site.Wards();if not list then
        if not s.vision_diag_unknown then B.Emit(s,"ward_calibration_unavailable",{reason="allied_ward_api_unknown"});s.vision_diag_unknown=true end;
        return;
    end;
    local seen=s.vision_ward_entities or {};local alive={};s.vision_diag_unknown=nil;
    for _,w in ipairs(list) do
        alive[w.handle]=true;
        if not seen[w.handle] then
            local owner=U.Call(w.handle,"GetPlayerID");local own=U.Call(bot,"GetPlayerID");
            local data=geometry(w.location);data.location=w.location;data.owner_id=owner;data.sf_owner_id=own;
            data.owner_matches_sf=U.Number(owner) and U.Number(own) and owner==own or false;
            local isBot;
            if U.Number(owner) then isBot=U.Global("IsPlayerBot",owner) end;
            data.owner_is_bot=isBot;
            if type(isBot)=="boolean" then data.human_owned=not isBot end;
            data.vision_radius=U.Call(w.handle,"GetCurrentVisionRange");
            data.distance_from_test_point=U.Distance(w.location,U.Point(C.fixed_location));
            data.evidence="live_allied_observer_entity";
            data.coverage_attribution="range_and_team_visibility_not_exclusive_ward_los";
            data.auto_adopted=false;
            B.Emit(s,"ward_entity_observed",data);
        end;
    end;
    s.vision_ward_entities=alive;
end;
return M;
