-- Полный option-record для будущей оценки. Predicted features не являются labels/reward.
local M = {};
local function encode( value, seen )
    local t = type( value );
    if t == "nil" then return "null" end;
    if t == "number" then return value == value and math.abs( value ) < math.huge and tostring( value ) or "null" end;
    if t == "boolean" then return tostring( value ) end;
    if t == "string" then
        return '"' .. value:gsub( '[%z\1-\31\\"]', function( ch )
            if ch == '"' then return '\\"' end;
            if ch == "\\" then return "\\\\" end;
            return string.format( "\\u%04x", string.byte( ch ) );
        end ) .. '"';
    end
    assert( t == "table", "snapshot must contain serializable data, not handles/functions" );
    seen = seen or {}; assert( not seen[value], "cyclic snapshot" ); seen[value] = true;
    local count, max, array = 0, 0, true;
    for k in pairs( value ) do
        count = count + 1;
        if type( k ) ~= "number" or k < 1 or k % 1 ~= 0 then array = false;
        else max = math.max( max, k ) end;
    end
    local out = {};
    if array and max == count and count > 0 then
        for i = 1, count do out[#out + 1] = encode( value[i], seen ) end;
    else
        local keys = {}; for k in pairs( value ) do keys[#keys + 1] = k end;
        table.sort( keys, function( a, b ) return tostring( a ) < tostring( b ) end );
        for _, k in ipairs( keys ) do out[#out + 1] = encode( tostring( k ), seen ) .. ":" .. encode( value[k], seen ) end;
    end
    seen[value] = nil;
    return ( array and max == count and count > 0 and "[" or "{" ) .. table.concat( out, "," )
        .. ( array and max == count and count > 0 and "]" or "}" );
end
M.Encode = encode;
function M.Record( snapshot, planning, event )
    return { schema = planning.schema, policy_version = planning.policy_version,
        run_id = snapshot.run_id, build = snapshot.build, observation_id = snapshot.observation_id,
        observed_at = snapshot.time, observation = snapshot, action_masks = planning.option_masks,
        candidate_plans = planning.candidates, selected_plan = planning.selected,
        context = { experience = planning.experience, tower_farm = planning.tower_farm, wave = planning.wave },
        engine_event = event, reward_status = "not_defined", attribution = "requires_combat_events" };
end
return M;
