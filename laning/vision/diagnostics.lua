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
    if not s or not Site.Participant(bot) or Profile.wards_enabled~=true or Profile.runtime_enabled==true then return end;
    local now=U.Now();if not now or now<(s.vision_diag_at or -math.huge) then return end;
    s.vision_diag_at=now+C.diagnostic_interval_s;
    if not s.vision_point_reported then
        local dire=TEAM_DIRE~=nil and U.Call(bot,"GetTeam")==TEAM_DIRE;
        local p=U.Point(dire and C.dire_fixed_location or C.fixed_location);
        if dire and not C.dire_fixed_location then p=nil end;
        if p then
            local data=geometry(p);data.location=p;data.calibration_only=C.calibration_only==true;
            data.calibration_source=not dire and C.calibration_source or nil;data.sf_team=U.Call(bot,"GetTeam");
            data.coordinate_status=data.calibration_source and "human_ward_coordinate_pinned" or "unverified_user_test_point";
            data.photo_match=data.calibration_source and "human_selected_point_not_image_projection" or "not_verified";
            data.plant_validity=data.calibration_source and "manual_placement_in_source_match" or "not_tested";
            data.sf_automatic_placement="requires_current_match_readback";
            B.Emit(s,"ward_test_point_geometry",data);s.vision_point_reported=true;
        end;
    end;
    local raw=UNIT_LIST_ALLIED_WARDS~=nil and U.Global("GetUnitList",UNIT_LIST_ALLIED_WARDS);local list;
    if type(raw)=="table" then list={};for _,w in ipairs(raw) do local name=U.Call(w,"GetUnitName");
        if (name=="npc_dota_observer_wards" or name=="npc_dota_sentry_wards") and U.Call(w,"IsAlive")==true then
            local p=U.Pos(w);if p then list[#list+1]={handle=w,location=p,kind=name=="npc_dota_observer_wards" and "observer" or "sentry"} end;
        end;
    end end;
    if not list then
        if not s.vision_diag_unknown then B.Emit(s,"ward_calibration_unavailable",{reason="allied_ward_api_unknown"});s.vision_diag_unknown=true end;
        return;
    end;
    local seen=s.vision_ward_entities or {};local alive={};s.vision_diag_unknown=nil;
    for _,w in ipairs(list) do
        alive[w.handle]=true;
        if not seen[w.handle] then
            local owner=U.Call(w.handle,"GetPlayerID");local own=U.Call(bot,"GetPlayerID");
            local data=geometry(w.location);data.location=w.location;data.kind=w.kind;data.team=U.Call(w.handle,"GetTeam");data.sf_team=U.Call(bot,"GetTeam");data.owner_id=owner;data.sf_owner_id=own;
            data.owner_matches_sf=U.Number(owner) and U.Number(own) and owner==own or false;
            local isBot;
            if U.Number(owner) then isBot=U.Global("IsPlayerBot",owner) end;
            data.owner_is_bot=isBot;
            if type(isBot)=="boolean" then data.human_owned=not isBot end;
            data.vision_radius=U.Call(w.handle,"GetCurrentVisionRange");
            data.distance_from_test_point=U.Distance(w.location,U.Point(C.fixed_location));
            data.evidence="live_allied_ward_entity";
            data.coverage_attribution="range_and_team_visibility_not_exclusive_ward_los";
            data.auto_adopted=false;
            B.Emit(s,"ward_entity_observed",data);
        end;
    end;
    s.vision_ward_entities=alive;
end;
return M;
