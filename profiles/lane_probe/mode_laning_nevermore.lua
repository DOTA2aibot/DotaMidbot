-- T007: диагностический entrypoint. В корень bots попадает только в профиле lane_probe.
local C = require( GetScriptDirectory() .. "/laning/config" );
local Policy = require( GetScriptDirectory() .. "/laning/policy" );
local Trace = require( GetScriptDirectory() .. "/laning/trace" );
local Options = require( GetScriptDirectory() .. "/laning/advanced/bridge" );
local Runtime = require( GetScriptDirectory() .. "/laning/runtime/entry" );
local nextDecision, nextAttack = -math.huge, -math.huge;
local nextTrace, seq, targetSerial = -math.huge, 0, 0;
local ids = setmetatable( {}, { __mode = "k" } ); -- идентификаторы только в этой Lua-сессии
local lastLH, lastDeny, lastReason = nil, nil, nil;
local cached, cachedAt = nil, -math.huge;

local function targetID( unit )
    if not ids[unit] then targetSerial = targetSerial + 1; ids[unit] = "u" .. targetSerial end;
    return ids[unit];
end
local function validTarget( unit )
    return unit ~= nil and not unit:IsNull() and unit:CanBeSeen() and unit:IsAlive()
        and not unit:IsInvulnerable() and not unit:IsAttackImmune();
end
local function towerDanger( bot, location )
    -- GetNearbyTowers ограничен текущей видимостью: это не гарантия отсутствия угрозы в fog.
    for _, tower in ipairs( bot:GetNearbyTowers( C.tower_scan_radius, true ) ) do
        if tower:CanBeSeen() and tower:IsAlive()
            and GetUnitToLocationDistance( tower, location ) <= tower:GetAttackRange() + C.tower_margin then return true end;
    end
    return false;
end
local function targetSnapshot( bot, unit )
    if not validTarget( unit ) then return nil end;
    local distance = GetUnitToUnitDistance( bot, unit );
    local speed = bot:GetAttackProjectileSpeed();
    local windup = bot:GetAttackPoint(); -- API wind-up; единицы проверить в игровом probe
    local travel = speed > 0 and distance / speed or 0;
    local damage = unit:GetActualIncomingDamage( math.max( 0, bot:GetAttackDamage() - bot:GetBaseDamageVariance() ), DAMAGE_TYPE_PHYSICAL );
    return { handle = unit, id = targetID( unit ), name = unit:GetUnitName(), visible = true, alive = true,
        invulnerable = false, attack_immune = false, distance = distance,
        in_range = distance <= bot:GetAttackRange(), hp = unit:GetHealth(), max_hp = unit:GetMaxHealth(),
        regen = unit:GetHealthRegen(), damage = damage, eta_s = windup + travel,
        tower_danger = towerDanger( bot, unit:GetLocation() ) };
end
local function collect( bot, list )
    local result = {};
    for _, unit in ipairs( list ) do
        local t = targetSnapshot( bot, unit );
        if t then result[#result + 1] = t end;
    end
    return result;
end
local function visibleHeroes( list )
    local count = 0;
    for _, unit in ipairs( list ) do if validTarget( unit ) and not unit:IsIllusion() then count = count + 1 end end;
    return count;
end
local function safety( bot )
    local maxHP = bot:GetMaxHealth();
    return { alive = bot:IsAlive(), disabled = bot:IsStunned() or bot:IsHexed() or bot:IsDisarmed(),
        casting = bot:IsUsingAbility() or bot:IsCastingAbility() or bot:IsChanneling(),
        retreating = bot:GetActiveMode() == BOT_MODE_RETREAT,
        time = DotaTime(), hp_fraction = maxHP > 0 and bot:GetHealth() / maxHP or 0,
        tower_danger = towerDanger( bot, bot:GetLocation() ),
        enemy_count = visibleHeroes( bot:GetNearbyHeroes( C.enemy_count_radius, true, BOT_MODE_NONE ) ),
        ally_count = visibleHeroes( bot:GetNearbyHeroes( C.enemy_count_radius, false, BOT_MODE_NONE ) ) };
end
local function ensureSelfCount( bot, s )
    -- Некоторые клиенты включают самого героя в GetNearbyHeroes(false), некоторые fixtures нет.
    local found = false;
    for _, ally in ipairs( bot:GetNearbyHeroes( C.enemy_count_radius, false, BOT_MODE_NONE ) ) do
        if ally == bot then found = true end;
    end
    if not found then s.ally_count = s.ally_count + 1 end;
end
local function observe( bot, s )
    if cached and s.time - cachedAt < C.decision_interval_s then
        -- Safety всегда свежая; массивы целей обновляем с ограниченной частотой.
        s.enemy_creeps, s.allied_creeps, s.enemy_heroes = cached.enemy_creeps, cached.allied_creeps, cached.enemy_heroes;
        s.anchor, s.anchor_safe, s.anchor_distance = cached.anchor, cached.anchor_safe, GetUnitToLocationDistance( bot, cached.anchor );
    else
        s.enemy_creeps = collect( bot, bot:GetNearbyLaneCreeps( C.creep_scan_radius, true ) );
        s.allied_creeps = collect( bot, bot:GetNearbyLaneCreeps( C.creep_scan_radius, false ) );
        s.enemy_heroes = collect( bot, bot:GetNearbyHeroes( C.enemy_count_radius, true, BOT_MODE_NONE ) );
        s.anchor = GetLaneFrontLocation( bot:GetTeam(), LANE_MID, C.lane_front_offset );
        s.anchor_safe = not towerDanger( bot, s.anchor );
        s.anchor_distance = GetUnitToLocationDistance( bot, s.anchor );
        cached, cachedAt = s, s.time;
    end
    s.attack_busy = s.time < nextAttack;
    return s;
end
local function emit( bot, s, a, status, force )
    local lh, deny = bot:GetLastHits(), bot:GetDenies();
    local dl = lastLH ~= nil and math.max( 0, lh - lastLH ) or 0;
    local dd = lastDeny ~= nil and math.max( 0, deny - lastDeny ) or 0;
    local key = a.reason .. ":" .. status;
    if not force and dl == 0 and dd == 0 and key == lastReason and s.time < nextTrace then return end;
    seq = seq + 1;
    local t = a.target;
    Trace.Emit( { schema = "lane-diagnostic-0.1", policy = C.policy_version, seq = seq,
        actor_id = bot:GetPlayerID(), game_time_s = s.time, reason = a.reason, kind = a.kind, status = status,
        hp_fraction = s.hp_fraction, enemy_count = s.enemy_count, ally_count = s.ally_count,
        last_hits = lh, denies = deny, last_hits_delta = dl, denies_delta = dd,
        outcome_attribution = "interval_only",
        target_id = t and t.id or nil, target_hp = t and t.hp or nil,
        target_damage_estimate = t and t.damage or nil, hit_eta_s = t and t.eta_s or nil } );
    lastLH, lastDeny, lastReason, nextTrace = lh, deny, key, s.time + C.trace_interval_s;
end

function GetDesire()
    local bot = GetBot();
    if bot == nil or bot:IsNull() or bot:GetUnitName() ~= "npc_dota_hero_nevermore" then return 0 end;
    if C.execution_mode == "joint_options" then
        if C.runtime_adapter then return Runtime.Desire( bot ) end;
        return Options.Desire( bot );
    end;
    local s = safety( bot ); ensureSelfCount( bot, s );
    local reason = Policy.YieldReason( s, C );
    if reason then emit( bot, s, { kind = "yield", reason = reason }, "yielded", false ); return 0 end;
    s = observe( bot, s );
    local a = Policy.Decide( s, C );
    if a.kind == "attack" then return BOT_MODE_DESIRE_MODERATE end;
    return BOT_MODE_DESIRE_LOW;
end

function Think()
    local bot = GetBot();
    if bot == nil or bot:IsNull() or bot:GetUnitName() ~= "npc_dota_hero_nevermore" then return end;
    if C.execution_mode == "joint_options" then
        if C.runtime_adapter then return Runtime.Think( bot ) end;
        return Options.Think( bot );
    end;
    local s = safety( bot ); ensureSelfCount( bot, s );
    local reason = Policy.YieldReason( s, C );
    if reason then emit( bot, s, { kind = "yield", reason = reason }, "yielded", false ); return end;
    if s.time < nextDecision then return end;
    nextDecision = s.time + C.decision_interval_s;
    -- GetDesire может использовать короткий cache, исполнение всегда решает по свежим целям.
    cached = nil;
    s = observe( bot, s );
    local a = Policy.Decide( s, C );
    if a.kind == "attack" then
        local unit = a.target.handle;
        -- Повторная проверка непосредственно перед API; не гонимся за ушедшей целью.
        if not validTarget( unit ) or GetUnitToUnitDistance( bot, unit ) > bot:GetAttackRange()
            or towerDanger( bot, unit:GetLocation() ) then
            emit( bot, s, a, "rejected_stale_target", true ); cached = nil; return;
        end
        bot:Action_AttackUnit( unit, true ); -- один удар, не постоянная погоня/пуш
        nextAttack = s.time + math.max( bot:GetSecondsPerAttack(), bot:GetAttackPoint() );
        emit( bot, s, a, "submitted", true );
    elseif a.kind == "move" then
        if not towerDanger( bot, s.anchor ) then bot:Action_MoveToLocation( s.anchor ); emit( bot, s, a, "submitted", false ) end;
    else
        -- Wait не отменяет ранее выданные приказы. Отдельного stop/clear очереди здесь нет.
        emit( bot, s, a, "no_new_order", false );
    end
end

function OnEnd()
    local bot = GetBot();
    if bot and C.execution_mode == "joint_options" and C.runtime_adapter then Runtime.Leave( bot ) end;
end
