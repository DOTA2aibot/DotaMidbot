-- Диагностические JSON-строки, не dataset/reward и не подтверждение исхода attack.
local M = {};
local function encode( v )
    if v == nil then return "null" end;
    if type( v ) == "number" then
        if v ~= v or math.abs( v ) == math.huge then return "null" end;
        return tostring( v );
    end
    if type( v ) == "boolean" then return tostring( v ) end;
    local s = tostring( v ):gsub( "\\", "\\\\" ):gsub( '"', '\\"' ):gsub( "\n", "\\n" ):gsub( "\r", "\\r" ):gsub( "\t", "\\t" );
    return '"' .. s .. '"';
end
function M.Emit( fields )
    local keys, out = {}, {};
    for key in pairs( fields ) do keys[#keys + 1] = key end;
    table.sort( keys );
    for _, key in ipairs( keys ) do out[#out + 1] = encode( key ) .. ":" .. encode( fields[key] ) end;
    local line = "[MIDBOT lane] {" .. table.concat( out, "," ) .. "}";
    print( line );
    return line;
end
return M;
