-- Полная замена только rune mode SF в явном тестовом профиле.
-- Не рассчитываем на неподтверждённый nil -> C++ fallback.
local ok, Rune = pcall( require, GetScriptDirectory() .. "/laning/economy/runes" );
function GetDesire()
    if not ok then return 0 end;
    local success, desire = pcall( Rune.GetDesire, GetBot() );
    return success and type( desire ) == "number" and desire or 0;
end;
function Think()
    if ok then pcall( Rune.Think, GetBot() ) end;
end;
function OnStart() end;
function OnEnd()
    if ok then pcall( Rune.Leave, GetBot(), "mode_ended" ) end;
end;
