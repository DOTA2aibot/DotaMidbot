----------------------------------------------------------------------------------------------------
-- MIDBOT: логика Shadow Fiend (мид)
--
-- Что умеет база:
--   1. Харасс вражеского героя рейзами — выбор рейза по дистанции до цели
--      (ближний ~200, средний ~450, дальний ~700) с упреждением на скорость цели.
--   2. Добивание/фарм крипов рейзом, если попадают 2+ крипа или крип умирает от рейза.
--   3. Реквием: добить героя с низким HP рядом или отчаянная отпорка, когда нас бьют.
--
-- Всё остальное (лаининг, отступление, перемещения) пока делает стандартный ИИ Valve —
-- у нас нет mode_*.lua файлов, значит работают дефолтные режимы.
----------------------------------------------------------------------------------------------------

-- Пороги, которые потом будем крутить (а ещё позже — обучать)
local RAZE_MANA_PCT_HARASS = 0.45;   -- не харассить рейзами, если маны меньше 45%
local REQUIEM_ENEMY_HP_PCT = 0.40;   -- добивать ультой, если у врага меньше 40% HP
local REQUIEM_SELF_HP_PCT  = 0.30;   -- или если нас почти убили

-- Дистанции рейзов от точки каста (центр области)
local RAZE_DIST = { 200, 450, 700 };
local RAZE_RADIUS = 250;             -- радиус области рейза
local RAZE_CAST_POINT = 0.55;        -- задержка каста для упреждения

local abilityRaze = { nil, nil, nil };
local abilityRequiem = nil;
local bAbilitiesInit = false;

----------------------------------------------------------------------------------------------------
-- T018: явная прокачка. Дефолтный ИИ в 1v1 mid очки может не тратить вообще,
-- поэтому раскладываем первые 10 уровней сами: рейзы равномерно, ульта на 6.
-- Дальше 10-го уровня список молчит — прокачку подхватывает стандартный ИИ.
----------------------------------------------------------------------------------------------------
local SKILL_ORDER = {
	"nevermore_shadowraze1",  -- 1
	"nevermore_shadowraze2",  -- 2
	"nevermore_shadowraze3",  -- 3
	"nevermore_shadowraze1",  -- 4
	"nevermore_shadowraze2",  -- 5
	"nevermore_requiem",      -- 6
	"nevermore_shadowraze3",  -- 7
	"nevermore_shadowraze1",  -- 8
	"nevermore_shadowraze2",  -- 9
	"nevermore_shadowraze3",  -- 10
};

function LevelUpThink( npcBot )

	if ( npcBot:GetAbilityPoints() < 1 ) then return end;

	local seen = {};
	for _, sName in ipairs( SKILL_ORDER )
	do
		seen[sName] = ( seen[sName] or 0 ) + 1;
		local ability = npcBot:GetAbilityByName( sName );
		if ( ability ~= nil and ability:CanAbilityBeUpgraded() and ability:GetLevel() < seen[sName] )
		then
			npcBot:ActionImmediate_LevelAbility( sName );
			print( "[MIDBOT levelup] " .. sName );
			return;
		end
	end

end

----------------------------------------------------------------------------------------------------

function InitAbilities( npcBot )
	abilityRaze[1] = npcBot:GetAbilityByName( "nevermore_shadowraze1" );
	abilityRaze[2] = npcBot:GetAbilityByName( "nevermore_shadowraze2" );
	abilityRaze[3] = npcBot:GetAbilityByName( "nevermore_shadowraze3" );
	abilityRequiem = npcBot:GetAbilityByName( "nevermore_requiem" );
	bAbilitiesInit = true;
end

----------------------------------------------------------------------------------------------------
-- Выбор рейза по дистанции: возвращает способность или nil
----------------------------------------------------------------------------------------------------
function GetRazeForDistance( nDist )
	-- Полоса поражения рейза: центр +/- радиус
	for i = 1, 3
	do
		if ( math.abs( nDist - RAZE_DIST[i] ) <= RAZE_RADIUS )
		then
			if ( abilityRaze[i] ~= nil and abilityRaze[i]:IsFullyCastable() )
			then
				return abilityRaze[i];
			end
		end
	end
	return nil;
end

----------------------------------------------------------------------------------------------------

function AbilityUsageThink()

	local npcBot = GetBot();

	if ( not bAbilitiesInit ) then InitAbilities( npcBot ); end

	-- Прокачка — всегда в первую очередь, даже во время каста
	LevelUpThink( npcBot );

	-- Не мешаем текущему касту/каналу
	if ( npcBot:IsUsingAbility() or npcBot:IsChanneling() or npcBot:IsSilenced() ) then return end;

	-- 1. Реквием
	local desireReq, targetReq = ConsiderRequiem( npcBot );
	if ( desireReq > 0 )
	then
		npcBot:Action_UseAbility( abilityRequiem );
		return;
	end

	-- 2. Рейз по вражескому герою (харасс / добивание)
	local desireRaze, locRaze, razeAbility = ConsiderRazeOnHero( npcBot );
	if ( desireRaze > 0 )
	then
		npcBot:Action_UseAbilityOnLocation( razeAbility, locRaze );
		return;
	end

	-- 3. Рейз по крипам (фарм)
	local desireFarm, locFarm, farmAbility = ConsiderRazeOnCreeps( npcBot );
	if ( desireFarm > 0 )
	then
		npcBot:Action_UseAbilityOnLocation( farmAbility, locFarm );
		return;
	end

end

----------------------------------------------------------------------------------------------------
-- Реквием: враг рядом и почти мёртв, или нас почти убили и враг вплотную
----------------------------------------------------------------------------------------------------
function ConsiderRequiem( npcBot )

	if ( abilityRequiem == nil or not abilityRequiem:IsFullyCastable() )
	then
		return BOT_ACTION_DESIRE_NONE, nil;
	end

	local nRadius = 700;
	local tableEnemyHeroes = npcBot:GetNearbyHeroes( nRadius, true, BOT_MODE_NONE );

	for _, npcEnemy in pairs( tableEnemyHeroes )
	do
		if ( npcEnemy:CanBeSeen() and not npcEnemy:IsMagicImmune() and not npcEnemy:IsInvulnerable() )
		then
			local enemyPct = npcEnemy:GetHealth() / npcEnemy:GetMaxHealth();
			local selfPct  = npcBot:GetHealth() / npcBot:GetMaxHealth();

			if ( enemyPct <= REQUIEM_ENEMY_HP_PCT )
			then
				return BOT_ACTION_DESIRE_HIGH, npcEnemy;
			end

			if ( selfPct <= REQUIEM_SELF_HP_PCT and npcBot:WasRecentlyDamagedByHero( npcEnemy, 2.0 ) )
			then
				return BOT_ACTION_DESIRE_VERYHIGH, npcEnemy;
			end
		end
	end

	return BOT_ACTION_DESIRE_NONE, nil;
end

----------------------------------------------------------------------------------------------------
-- Рейз по герою: ближайший видимый враг в зоне досягаемости любого рейза
----------------------------------------------------------------------------------------------------
function ConsiderRazeOnHero( npcBot )

	-- Не жечь ману в ноль на харасс; на добивание (враг почти мёртв) ману не жалеем
	local manaPct = npcBot:GetMana() / npcBot:GetMaxMana();

	local tableEnemyHeroes = npcBot:GetNearbyHeroes( RAZE_DIST[3] + RAZE_RADIUS, true, BOT_MODE_NONE );

	for _, npcEnemy in pairs( tableEnemyHeroes )
	do
		if ( npcEnemy:CanBeSeen() and not npcEnemy:IsMagicImmune() and not npcEnemy:IsInvulnerable() )
		then
			-- Упреждение: куда цель доедет за время каста
			local vLoc = npcEnemy:GetLocation();
			if ( npcEnemy:IsMoving() )
			then
				vLoc = vLoc + npcEnemy:GetVelocity() * RAZE_CAST_POINT;
			end

			local nDist = GetUnitToLocationDistance( npcBot, vLoc );
			local raze = GetRazeForDistance( nDist );

			if ( raze ~= nil )
			then
				local enemyPct = npcEnemy:GetHealth() / npcEnemy:GetMaxHealth();
				-- Добивание — всегда; харасс — только если маны хватает
				if ( enemyPct <= 0.25 and manaPct > 0.15 )
				then
					return BOT_ACTION_DESIRE_HIGH, vLoc, raze;
				end
				if ( manaPct >= RAZE_MANA_PCT_HARASS )
				then
					return BOT_ACTION_DESIRE_MODERATE, vLoc, raze;
				end
			end
		end
	end

	return BOT_ACTION_DESIRE_NONE, nil, nil;
end

----------------------------------------------------------------------------------------------------
-- Рейз по крипам: 2+ крипа в полосе одного рейза или гарантированное добивание
----------------------------------------------------------------------------------------------------
function ConsiderRazeOnCreeps( npcBot )

	-- Только когда стоим на линии/фармим — не палим ману в драках и на бегстве
	local mode = npcBot:GetActiveMode();
	if ( mode ~= BOT_MODE_LANING and mode ~= BOT_MODE_FARM )
	then
		return BOT_ACTION_DESIRE_NONE, nil, nil;
	end

	local manaPct = npcBot:GetMana() / npcBot:GetMaxMana();
	if ( manaPct < RAZE_MANA_PCT_HARASS )
	then
		return BOT_ACTION_DESIRE_NONE, nil, nil;
	end

	local tableEnemyCreeps = npcBot:GetNearbyLaneCreeps( RAZE_DIST[3] + RAZE_RADIUS, true );

	-- Считаем крипов по полосам каждого рейза
	for i = 1, 3
	do
		if ( abilityRaze[i] ~= nil and abilityRaze[i]:IsFullyCastable() )
		then
			local nDamage = abilityRaze[i]:GetAbilityDamage();
			local count = 0;
			local killTarget = nil;

			for _, npcCreep in pairs( tableEnemyCreeps )
			do
				local nDist = GetUnitToUnitDistance( npcBot, npcCreep );
				if ( math.abs( nDist - RAZE_DIST[i] ) <= RAZE_RADIUS )
				then
					count = count + 1;
					if ( npcCreep:GetHealth() <= nDamage )
					then
						killTarget = npcCreep;
					end
				end
			end

			-- Добивание одного крипа
			if ( killTarget ~= nil )
			then
				return BOT_ACTION_DESIRE_MODERATE, killTarget:GetLocation(), abilityRaze[i];
			end

			-- Или задеть пачку из 3+
			if ( count >= 3 )
			then
				-- Кастуем в центр полосы перед собой
				local vForward = npcBot:GetFacing();
				local rad = math.rad( vForward );
				local vLoc = npcBot:GetLocation() + Vector( math.cos( rad ), math.sin( rad ), 0 ) * RAZE_DIST[i];
				return BOT_ACTION_DESIRE_LOW, vLoc, abilityRaze[i];
			end
		end
	end

	return BOT_ACTION_DESIRE_NONE, nil, nil;
end

----------------------------------------------------------------------------------------------------
