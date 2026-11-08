-- Local T023 integration guards. Never issue movement or attack orders here.
local M, orders = {}, setmetatable( {}, { __mode = "k" } );
local levels = setmetatable( {}, { __mode = "k" } );
local function call( bot, method )
    local ok, value = pcall( function() return bot[method]( bot ) end );
    if ok then return value end;
end;
function M.Real( bot )
    return bot ~= nil and call( bot, "IsHero" ) == true
        and call( bot, "IsIllusion" ) == false
        and call( bot, "GetUnitName" ) == "npc_dota_hero_nevermore";
end;
local function time()
    local ok, now = pcall( GameTime );
    if ok and type( now ) == "number" and now == now then return now end;
end;
function M.Blocked( bot )
    local now = time();
    return not M.Real( bot ) or now == nil or orders[bot] == now;
end;
function M.Mark( bot ) orders[bot] = time() end;
function M.LevelBlocked( bot ) local now = time(); return now == nil or levels[bot] == now end;
function M.MarkLevel( bot ) levels[bot] = time() end;
return M;
