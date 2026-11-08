-- Локальные шаги, не глобальный nav/path planner. Не ослабляет проверки угроз.
local A = require( GetScriptDirectory() .. "/laning/runtime/api" );
local M = {};
-- Фиксированный бюджет: максимум 15 вариантов и 5 проб на обычный шаг 250.
local ANGLES = { 0, 30, -30, 60, -60 };
local LENGTHS = { 1, 0.5, 0.25 };
local SAMPLE_DISTANCE, MIN_PROGRESS = 50, 1;
local function position( p )
    return type( p ) == "table" and A.Number( p.x ) and A.Number( p.y )
        and ( p.z == nil or A.Number( p.z ) );
end
local function passable( point )
    if type( IsLocationPassable ) ~= "function" then return false, "move_passability_unavailable" end;
    local ok, vector = pcall( A.Vector, point );
    if not ok or vector == nil then return false, "move_vector_unavailable" end;
    local called, value = pcall( IsLocationPassable, vector );
    if not called or type( value ) ~= "boolean" then return false, "move_passability_failed" end;
    return value;
end
function M.Check( s, point, cfg )
    local detail = { origin = s and s.hero and { x = s.hero.x, y = s.hero.y }, destination = point };
    local function reject( reason ) detail.reason = reason; return false, reason, detail end;
    if not s or not position( s.hero ) or not position( point ) then return reject( "move_position_invalid" ) end;
    if not A.Number( cfg.move_step ) or cfg.move_step <= 0 then return reject( "move_step_invalid" ) end;
    local distance = A.Distance( s.hero, point ); detail.distance = distance;
    if distance > cfg.move_step + 1 then return reject( "move_step_too_long" ) end;
    local ok, reason = passable( point );
    if not ok then return reject( reason or "move_point_impassable" ) end;
    if type( s.towers ) ~= "table" then return reject( "move_tower_data_unavailable" ) end;
    -- Проверяем и отрезок: проходимая конечная точка может лежать за препятствием
    -- или по другую сторону радиуса вышки. Семплы не доказывают полный nav-маршрут.
    local count = math.max( 1, math.ceil( distance / SAMPLE_DISTANCE ) );
    for i = 1, count do
        local fraction = i / count;
        local sample = { x = s.hero.x + ( point.x - s.hero.x ) * fraction,
            y = s.hero.y + ( point.y - s.hero.y ) * fraction, z = point.z };
        if i < count then
            local valid, why = passable( sample );
            if not valid then detail.failed_sample = sample; return reject( why or "move_path_impassable" ) end;
        end;
        for _, tower in ipairs( s.towers ) do
            if tower.enemy then
                detail.tower_id = tower.id;
                if not tower.range_verified or not position( tower ) or not A.Number( tower.attack_range )
                    or not A.Number( tower.range_margin ) then return reject( "move_tower_range_unknown" ) end;
                if A.Distance( tower, sample ) <= tower.attack_range + tower.range_margin then
                    detail.failed_sample = sample; return reject( "move_enters_tower_range" );
                end;
            end;
        end;
    end;
    detail.reason = "move_checked"; return true, nil, detail;
end
function M.Plan( s, destination, cfg )
    if not s or not position( s.hero ) or not position( destination ) then
        return nil, "move_position_invalid", { reason = "move_position_invalid" };
    end;
    local distance = A.Distance( s.hero, destination );
    if not A.Number( cfg.move_step ) or cfg.move_step <= 0 then return nil, "move_step_invalid", { reason = "move_step_invalid" } end;
    if distance <= MIN_PROGRESS then return nil, "move_already_at_destination", { reason = "move_already_at_destination" } end;
    local ux, uy = ( destination.x - s.hero.x ) / distance, ( destination.y - s.hero.y ) / distance;
    local first, attempts, blocked = nil, 0, {};
    for _, fraction in ipairs( LENGTHS ) do
        for _, degrees in ipairs( ANGLES ) do
            local radians = degrees * math.pi / 180;
            local length = math.min( cfg.move_step, distance ) * fraction;
            local point = { x = s.hero.x + ( ux * math.cos( radians ) - uy * math.sin( radians ) ) * length,
                y = s.hero.y + ( ux * math.sin( radians ) + uy * math.cos( radians ) ) * length };
            -- Альтернатива обязана приближать к исходной цели, не уводить назад.
            if A.Distance( point, destination ) < distance - MIN_PROGRESS then
                attempts = attempts + 1;
                local valid, reason, detail = M.Check( s, point, cfg );
                if valid then
                    detail.attempts, detail.alternative, detail.blocked = attempts, degrees ~= 0 or fraction ~= 1, blocked;
                    return point, nil, detail;
                end;
                first = first or detail; blocked[reason] = ( blocked[reason] or 0 ) + 1;
                -- Нет смысла проверять геометрию при недоступном API/профиле.
                if reason == "move_passability_unavailable" or reason == "move_passability_failed"
                    or reason == "move_vector_unavailable" or reason == "move_tower_range_unknown"
                    or reason == "move_tower_data_unavailable" then
                    detail.attempts, detail.blocked = attempts, blocked; return nil, reason, detail;
                end;
            end;
        end;
    end;
    first = first or { reason = "move_no_progress" };
    first.attempts, first.blocked, first.no_safe_step = attempts, blocked, true;
    return nil, first.reason, first;
end
return M;
