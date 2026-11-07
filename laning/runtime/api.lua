local M = {};
function M.Number( n ) return type( n ) == "number" and n == n and math.abs( n ) < math.huge end;
function M.Call( object, name, ... )
    local args = { ... };
    local ok, value = pcall( function() return object[name]( object, unpack( args ) ) end );
    if ok then return value end;
    return nil;
end
function M.Time()
    if type( DotaTime ) ~= "function" then return nil end;
    local ok, now = pcall( DotaTime ); if ok and M.Number( now ) then return now end;
end
function M.Position( unit )
    local v = M.Call( unit, "GetLocation" );
    local ok, p = pcall( function()
        if v and M.Number( v.x ) and M.Number( v.y ) then return { x = v.x, y = v.y, z = v.z or 0 } end;
    end );
    if ok then return p end;
end
function M.Visible( unit )
    return unit ~= nil and M.Call( unit, "IsNull" ) ~= true and M.Call( unit, "CanBeSeen" ) == true
        and M.Call( unit, "IsAlive" ) == true;
end
function M.Distance( a, b ) return math.sqrt( ( a.x - b.x ) ^ 2 + ( a.y - b.y ) ^ 2 ) end;
function M.Vector( p ) if type( Vector ) == "function" then return Vector( p.x, p.y, p.z or 0 ) end end;
function M.HasBit( flags, flag )
    return M.Number( flags ) and M.Number( flag ) and flag > 0 and math.floor( flags / flag ) % 2 == 1;
end
function M.Modifiers( unit )
    local out, n = {}, M.Call( unit, "NumModifiers" );
    if not M.Number( n ) then return out end;
    for i = 0, math.min( n - 1, 63 ) do
        local name = M.Call( unit, "GetModifierName", i );
        if type( name ) == "string" then out[#out + 1] = { name = name,
            stacks = M.Call( unit, "GetModifierStackCount", i ),
            remaining_s = M.Call( unit, "GetModifierRemainingDuration", i ) } end;
    end
    return out;
end
function M.Stacks( unit, name, verified )
    if not verified then return nil end;
    local index = M.Call( unit, "GetModifierByName", name );
    if not M.Number( index ) then return nil end;
    if index < 0 then return 0 end;
    local stacks, duration = M.Call( unit, "GetModifierStackCount", index ), M.Call( unit, "GetModifierRemainingDuration", index );
    if not M.Number( stacks ) or stacks < 0 then return nil end;
    return stacks, M.Number( duration ) and duration >= 0 and duration or nil;
end
return M;
