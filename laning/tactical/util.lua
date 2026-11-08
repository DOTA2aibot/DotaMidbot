local M = {};
function M.Number( v ) return type( v ) == "number" and v == v and math.abs( v ) < math.huge end;
function M.Call( obj, method, ... )
    local args = { ... };
    local ok, result = pcall( function() return obj[method]( obj, unpack( args ) ) end );
    if ok then return result end;
end;
function M.Global( name, ... )
    if type( _G[name] ) ~= "function" then return nil end;
    local ok, result = pcall( _G[name], ... ); if ok then return result end;
end;
function M.Now() local t = M.Global( "DotaTime" ); if M.Number( t ) then return t end end;
function M.Pos( obj )
    local p = M.Call( obj, "GetLocation" );
    local ok, out = pcall( function()
        if M.Number( p.x ) and M.Number( p.y ) then return { x = p.x, y = p.y, z = p.z or 0 } end;
    end ); if ok then return out end;
end;
function M.Point( p )
    local ok, out = pcall( function()
        if M.Number( p.x ) and M.Number( p.y ) then return { x = p.x, y = p.y, z = p.z or 0 } end;
    end ); if ok then return out end;
end;
function M.Vector( p ) if p then return M.Global( "Vector", p.x, p.y, p.z or 0 ) end end;
function M.Distance( p, q ) if not p or not q then return math.huge end; return math.sqrt( ( p.x-q.x )^2 + ( p.y-q.y )^2 ) end;
function M.Visible( unit ) return unit ~= nil and M.Call( unit, "IsNull" ) ~= true
    and M.Call( unit, "IsAlive" ) == true and M.Call( unit, "CanBeSeen" ) == true end;
function M.RealHero( unit )
    local id = M.Call( unit, "GetPlayerID" );
    return M.Visible( unit ) and M.Call( unit, "IsHero" ) == true
        and M.Call( unit, "IsIllusion" ) == false and M.Number( id ) and id >= 0
        and M.Call( unit, "IsTempestDouble" ) ~= true
        and M.Call( unit, "HasModifier", "modifier_illusion" ) ~= true
        and M.Call( unit, "HasModifier", "modifier_arc_warden_tempest_double" ) ~= true;
end;
function M.Actor( bot )
    return bot ~= nil and M.Call( bot, "IsHero" ) == true and M.Call( bot, "IsIllusion" ) == false
        and M.Call( bot, "GetUnitName" ) == "npc_dota_hero_nevermore"
        and M.Call( bot, "HasModifier", "modifier_illusion" ) ~= true;
end;
function M.Enemy( bot, unit )
    local a, b = M.Call( bot, "GetTeam" ), M.Call( unit, "GetTeam" );
    return M.RealHero( unit ) and M.Number( a ) and M.Number( b ) and a ~= b;
end;
function M.HP( bot ) local h, m = M.Call( bot, "GetHealth" ), M.Call( bot, "GetMaxHealth" ); if M.Number(h) and M.Number(m) and m > 0 then return h/m end end;
function M.Special( ability, keys )
    for _, key in ipairs( keys ) do
        local v = M.Call( ability, "GetSpecialValueFloat", key );
        if not M.Number(v) or v <= 0 then v = M.Call( ability, "GetSpecialValueInt", key ) end;
        if M.Number(v) and v > 0 then return v end;
    end;
end;
function M.Cost( ability ) local v = M.Call( ability, "GetManaCost" ); if M.Number(v) and v >= 0 then return v end end;
function M.Item( bot, name )
    for slot = 0, 5 do local item = M.Call( bot, "GetItemInSlot", slot );
        if M.Call( item, "GetName" ) == name then return item, slot end;
    end;
end;
function M.Has( flags, flag ) return M.Number(flags) and M.Number(flag) and flag > 0 and math.floor(flags/flag)%2 == 1 end;
function M.CanUse( bot )
    if not M.Actor(bot) or M.Call(bot,"IsAlive") ~= true then return false end;
    for _, key in ipairs({"IsUsingAbility","IsChanneling","IsStunned","IsHexed","IsMuted"}) do
        if M.Call(bot,key) ~= false then return false end;
    end;
    return M.Call(bot,"NumQueuedActions") == 0;
end;
function M.Ready( a ) return M.Call(a,"IsFullyCastable") == true and M.Call(a,"IsHidden") ~= true end;
return M;
