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
-- Интеграция T007 x T016 (план следующего этапа, п.4).
-- Если общий исполнитель GPT (laning/advanced/bridge) активен — он ЕДИНСТВЕННЫЙ
-- владелец приказов атак/способностей, и этот модуль ему уступает.
-- Прокачка (LevelUpThink) НЕ уступает: ActionImmediate_LevelAbility не является
-- боевым приказом и с планировщиком не конфликтует.
-- Интерфейс зафиксирован в docs/T016_BACKEND_API.md.
----------------------------------------------------------------------------------------------------
local JointBridge = nil;
do
	local ok, mod = pcall( require, GetScriptDirectory() .. "/laning/advanced/bridge" );
	if ( ok ) then JointBridge = mod; end
end

-- Уступаем ли управление общему исполнителю в этом тике
function JointExecutorOwnsBot( npcBot )
	if ( JointBridge == nil or npcBot == nil ) then return false; end
	local ok, ready = pcall( JointBridge.IsReady, npcBot:GetPlayerID() );
	return ok and ready == true;
end

----------------------------------------------------------------------------------------------------
-- T018: явная прокачка. Дефолтный ИИ в 1v1 mid очки может не тратить вообще,
-- поэтому ключевые уровни раскладываем сами.
-- Патч 7.4x: Necromastery — врождённая (качать НЕ нужно), все три рейза делят
-- ОДИН уровень (качаем shadowraze1), на D — активка Feast of Souls.
-- Порядок — приоритетный, не привязан к конкретному уровню: CanAbilityBeUpgraded
-- сам решит, что доступно. Если способности из списка нет в текущем патче,
-- GetAbilityByName вернёт nil и она просто пропустится.
----------------------------------------------------------------------------------------------------
local SKILL_ORDER = {
	"nevermore_shadowraze1",      -- рейзы максимум в первую очередь
	"nevermore_shadowraze1",
	"nevermore_shadowraze1",
	"nevermore_shadowraze1",
	"nevermore_requiem",          -- 6
	"nevermore_feast_of_souls",   -- активка на D (7.4x)
	"nevermore_feast_of_souls",
	"nevermore_requiem",          -- 12
	"nevermore_feast_of_souls",
	"nevermore_dark_lord",        -- аура
	"nevermore_feast_of_souls",
	"nevermore_dark_lord",
	"nevermore_requiem",          -- 18
	"nevermore_dark_lord",
	"nevermore_dark_lord",
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

	-- Fallback (фикс аудита GPT): если всё из списка выкачано или недоступно,
	-- тратим очко на первую доступную способность — включая таланты.
	-- Раньше очки после 6-го уровня могли копиться непотраченными.
	for nSlot = 0, 23
	do
		local ability = npcBot:GetAbilityInSlot( nSlot );
		if ( ability ~= nil
			and ability:CanAbilityBeUpgraded()
			and ability:GetLevel() < ability:GetMaxLevel() )
		then
			npcBot:ActionImmediate_LevelAbility( ability:GetName() );
			print( "[MIDBOT levelup fallback] " .. ability:GetName() );
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

	-- Диагностика душ/стаков (п.3 плана интеграции); по умолчанию выключена
	DebugPrintModifiers( npcBot );

	-- П.4 плана интеграции: если общий исполнитель T007 зарегистрирован и ведёт
	-- план — не выдаём свои приказы, он единственный владелец атак/способностей
	if ( JointExecutorOwnsBot( npcBot ) ) then return end;

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
		CastRaze( npcBot, razeAbility, locRaze );
		return;
	end

	-- 3. Рейз по крипам (фарм)
	local desireFarm, locFarm, farmAbility = ConsiderRazeOnCreeps( npcBot );
	if ( desireFarm > 0 )
	then
		CastRaze( npcBot, farmAbility, locFarm );
		return;
	end

end

----------------------------------------------------------------------------------------------------
-- Каст рейза. Рейзы — NO_TARGET способности: бьют на фикс. дистанции
-- в направлении, КУДА СМОТРИТ герой. Action_UseAbilityOnLocation тут не работает
-- (фикс аудита GPT). Делаем как эталонный bot_nevermore от Valve:
-- сначала AttackMove в сторону цели (разворачивает героя), затем каст.
----------------------------------------------------------------------------------------------------
function CastRaze( npcBot, razeAbility, vLoc )
	npcBot:Action_AttackMove( vLoc );
	npcBot:Action_UseAbility( razeAbility );
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
-- Хелперы геометрии рейзов.
-- ВАЖНО про механику: рейз бьёт на ФИКСИРОВАННОЙ дистанции от героя
-- (200/450/700) в направлении точки каста. Поэтому целимся не "в точку",
-- а выбираем направление так, чтобы в зону удара попало максимум целей.
----------------------------------------------------------------------------------------------------
function Dist2D( vA, vB )
	local dx = vA.x - vB.x;
	local dy = vA.y - vB.y;
	return math.sqrt( dx * dx + dy * dy );
end

-- Итоговый урон рейза по конкретной цели (фикс аудита GPT: сырой
-- GetAbilityDamage — это урон ДО сопротивлений). У героев базовое маг.
-- сопротивление 25%, у катапульт ~80%, у обычных крипов 0.
function EffectiveRazeDamage( nDamage, npcTarget )
	if ( npcTarget:IsHero() )
	then
		return nDamage * 0.75;
	end
	local sName = npcTarget:GetUnitName();
	if ( sName ~= nil and string.find( sName, "siege" ) ~= nil )
	then
		return nDamage * 0.20;
	end
	return nDamage;
end

function IsSiegeCreep( npcCreep )
	local sName = npcCreep:GetUnitName();
	return sName ~= nil and string.find( sName, "siege" ) ~= nil;
end

-- Центр удара i-го рейза, если кастовать в направлении vTarget
function GetRazeImpactPoint( npcBot, vTarget, i )
	local vBot = npcBot:GetLocation();
	local dx = vTarget.x - vBot.x;
	local dy = vTarget.y - vBot.y;
	local len = math.sqrt( dx * dx + dy * dy );
	if ( len < 1 ) then len = 1 end;
	return vBot + Vector( dx / len * RAZE_DIST[i], dy / len * RAZE_DIST[i], 0 );
end

----------------------------------------------------------------------------------------------------
-- Рейз по герою (гайд Олега, п.1): ищем каст, который заденет И врага, И крипов.
-- Скорим все три рейза: попадание по герою + крипы в зоне удара (бонус за добиваемых).
----------------------------------------------------------------------------------------------------
function ConsiderRazeOnHero( npcBot )

	local manaPct = npcBot:GetMana() / npcBot:GetMaxMana();
	local tableEnemyHeroes = npcBot:GetNearbyHeroes( RAZE_DIST[3] + RAZE_RADIUS, true, BOT_MODE_NONE );
	local tableEnemyCreeps = npcBot:GetNearbyLaneCreeps( RAZE_DIST[3] + RAZE_RADIUS, true );

	local bestScore = 0;
	local bestLoc = nil;
	local bestRaze = nil;
	local bestKill = false;

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

			for i = 1, 3
			do
				if ( abilityRaze[i] ~= nil and abilityRaze[i]:IsFullyCastable() )
				then
					local vImpact = GetRazeImpactPoint( npcBot, vLoc, i );

					-- Герой должен попасть в зону удара
					if ( Dist2D( vLoc, vImpact ) <= RAZE_RADIUS )
					then
						local nDamage = abilityRaze[i]:GetAbilityDamage();
						local score = 10; -- база за попадание по герою

						-- П.1 гайда: тот же рейз должен по возможности бить и крипов
						for _, npcCreep in pairs( tableEnemyCreeps )
						do
							if ( Dist2D( npcCreep:GetLocation(), vImpact ) <= RAZE_RADIUS )
							then
								if ( npcCreep:GetHealth() <= EffectiveRazeDamage( nDamage, npcCreep ) )
								then
									score = score + 2; -- крип ещё и умрёт
								else
									score = score + 1;
								end
							end
						end

						if ( score > bestScore )
						then
							bestScore = score;
							bestLoc = vLoc;
							bestRaze = abilityRaze[i];
							bestKill = ( npcEnemy:GetHealth() / npcEnemy:GetMaxHealth() ) <= 0.25;
						end
					end
				end
			end
		end
	end

	if ( bestRaze == nil ) then return BOT_ACTION_DESIRE_NONE, nil, nil end;

	-- Добивание — всегда; харасс — только если маны хватает
	if ( bestKill and manaPct > 0.15 ) then return BOT_ACTION_DESIRE_HIGH, bestLoc, bestRaze end;
	if ( manaPct >= RAZE_MANA_PCT_HARASS ) then return BOT_ACTION_DESIRE_MODERATE, bestLoc, bestRaze end;

	return BOT_ACTION_DESIRE_NONE, nil, nil;
end

----------------------------------------------------------------------------------------------------
-- Рейз по крипам. Приоритеты (гайд Олега, п.3-4):
--   1. Добить ДАЛЬНЕГО крипа (мага) дальним рейзом — безопасно и выгодно
--   2. Добить крипа под НАШЕЙ вышкой, если с руки не достать
--   3. Любое гарантированное добивание
--   4. Задеть пачку из 3+ одним рейзом
----------------------------------------------------------------------------------------------------
function ConsiderRazeOnCreeps( npcBot )

	-- Не палим ману на крипов только когда убегаем/разъезжаемся.
	-- Раньше был белый список (LANING/FARM) — из-за него рейзы глушились
	-- во всех остальных режимах (DEFEND_TOWER_MID под своей вышкой и т.п.),
	-- репорт Олега: "бот не хочет давать скиллы в крипов".
	local mode = npcBot:GetActiveMode();
	if ( mode == BOT_MODE_RETREAT
		or mode == BOT_MODE_EVASIVE_MANEUVERS
		or mode == BOT_MODE_ROAM
		or mode == BOT_MODE_GANK
		or mode == BOT_MODE_TEAM_ROAM )
	then
		return BOT_ACTION_DESIRE_NONE, nil, nil;
	end

	local manaPct = npcBot:GetMana() / npcBot:GetMaxMana();
	if ( manaPct < 0.25 ) -- жёсткий минимум: под вышкой добиваем и на малой мане
	then
		return BOT_ACTION_DESIRE_NONE, nil, nil;
	end

	local nSearchRadius = RAZE_DIST[3] + RAZE_RADIUS;
	local tableEnemyCreeps = npcBot:GetNearbyLaneCreeps( nSearchRadius, true );
	local tableAlliedTowers = npcBot:GetNearbyTowers( 1400, false );

	-- Собираем статистику по полосам каждого рейза
	local rangedSecure = nil;  -- {loc, raze} дальний крип
	local towerSecure = nil;   -- {loc, raze} крип под нашей вышкой
	local killSecure = nil;    -- {loc, raze} любое добивание
	local packBest = nil;      -- {loc, raze, count} пачка

	for i = 1, 3
	do
		if ( abilityRaze[i] ~= nil and abilityRaze[i]:IsFullyCastable() )
		then
			local nDamage = abilityRaze[i]:GetAbilityDamage();

			for _, npcCreep in pairs( tableEnemyCreeps )
			do
				local vCreepLoc = npcCreep:GetLocation();
				local nDist = GetUnitToLocationDistance( npcBot, vCreepLoc );
				local vImpact = GetRazeImpactPoint( npcBot, vCreepLoc, i );

				-- Крип реально попадает в зону удара этого рейза
				if ( nDist <= RAZE_DIST[3] + RAZE_RADIUS and Dist2D( vCreepLoc, vImpact ) <= RAZE_RADIUS )
				then
					if ( npcCreep:GetHealth() <= EffectiveRazeDamage( nDamage, npcCreep ) )
					then
						-- П.3: дальний крип (маг) — приоритет. Катапульты отдельно:
						-- у них ~80% маг. сопротивления, рейз их почти не добивает
						if ( npcCreep:GetAttackRange() > 200 and not IsSiegeCreep( npcCreep ) and rangedSecure == nil )
						then
							rangedSecure = { loc = vCreepLoc, raze = abilityRaze[i] };
						end

						-- П.4: крип рядом с НАШЕЙ вышкой — добиваем скиллом
						if ( towerSecure == nil )
						then
							for _, npcTower in pairs( tableAlliedTowers )
							do
								if ( GetUnitToLocationDistance( npcTower, vCreepLoc ) <= 800 )
								then
									towerSecure = { loc = vCreepLoc, raze = abilityRaze[i] };
									break;
								end
							end
						end

						if ( killSecure == nil )
						then
							killSecure = { loc = vCreepLoc, raze = abilityRaze[i] };
						end
					end
				end
			end
		end
	end

	-- Пачка (фикс аудита GPT): фиксируем ОДИН центр — целимся в конкретного
	-- крипа — и считаем, сколько крипов реально попадёт в ЭТУ область.
	-- Раньше счётчик суммировал крипов из разных направлений.
	if ( manaPct >= RAZE_MANA_PCT_HARASS )
	then
		for i = 1, 3
		do
			if ( abilityRaze[i] ~= nil and abilityRaze[i]:IsFullyCastable() )
			then
				for _, npcAim in pairs( tableEnemyCreeps )
				do
					local vAimLoc = npcAim:GetLocation();
					local vImpact = GetRazeImpactPoint( npcBot, vAimLoc, i );
					local count = 0;
					for _, npcCreep in pairs( tableEnemyCreeps )
					do
						if ( Dist2D( npcCreep:GetLocation(), vImpact ) <= RAZE_RADIUS )
						then
							count = count + 1;
						end
					end
					if ( count >= 3 and ( packBest == nil or count > packBest.count ) )
					then
						packBest = { loc = vAimLoc, raze = abilityRaze[i], count = count };
					end
				end
			end
		end
	end

	-- Выдаём по приоритету
	if ( rangedSecure ~= nil )
	then
		return BOT_ACTION_DESIRE_MODERATE, rangedSecure.loc, rangedSecure.raze;
	end
	if ( towerSecure ~= nil )
	then
		return BOT_ACTION_DESIRE_MODERATE, towerSecure.loc, towerSecure.raze;
	end
	if ( killSecure ~= nil and manaPct >= RAZE_MANA_PCT_HARASS )
	then
		return BOT_ACTION_DESIRE_LOW, killSecure.loc, killSecure.raze;
	end
	if ( packBest ~= nil )
	then
		return BOT_ACTION_DESIRE_LOW, packBest.loc, packBest.raze;
	end

	return BOT_ACTION_DESIRE_NONE, nil, nil;
end

----------------------------------------------------------------------------------------------------
----------------------------------------------------------------------------------------------------
-- Диагностика для п.3 плана интеграции: доступность данных о душах (Necromastery)
-- и стаках дебаффа рейзов на враге. Включить MIDBOT_DEBUG_MODIFIERS = true на время
-- теста и смотреть консоль — в лог попадут РЕАЛЬНЫЕ имена модификаторов текущего
-- патча (они меняются между патчами, поэтому угадывать не стали).
----------------------------------------------------------------------------------------------------
local MIDBOT_DEBUG_MODIFIERS = false; -- true = печатать все модификаторы раз в 3 сек
local nextDiagTime = -math.huge;

-- Число душ SF: стаки модификатора врождённой Necromastery.
-- Возвращает nil, если имя модификатора в текущем патче другое (тогда смотрим diag-лог).
function GetSoulsCount( npcBot )
	for i = 0, npcBot:GetModifierCount() - 1
	do
		if ( npcBot:GetModifierName( i ) == "modifier_nevermore_necromastery" )
		then
			return npcBot:GetModifierStackCount( i );
		end
	end
	return nil;
end

-- Стаки дебаффа рейзов на враге (каждый попавший рейз усиливает следующие)
function GetRazeDebuffStacks( npcEnemy )
	for i = 0, npcEnemy:GetModifierCount() - 1
	do
		local sName = npcEnemy:GetModifierName( i );
		if ( sName == "modifier_nevermore_shadowraze_debuff"
			or sName == "modifier_nevermore_shadowraze1_debuff" )
		then
			return npcEnemy:GetModifierStackCount( i ), sName;
		end
	end
	return nil, nil;
end

function DebugPrintModifiers( npcBot )
	if ( not MIDBOT_DEBUG_MODIFIERS ) then return end;
	if ( GameTime() < nextDiagTime ) then return end;
	nextDiagTime = GameTime() + 3.0;
	for i = 0, npcBot:GetModifierCount() - 1
	do
		print( "[MIDBOT diag] self: " .. npcBot:GetModifierName( i )
			.. " stacks=" .. tostring( npcBot:GetModifierStackCount( i ) ) );
	end
	local tableEnemyHeroes = npcBot:GetNearbyHeroes( 1200, true, BOT_MODE_NONE );
	for _, npcEnemy in pairs( tableEnemyHeroes )
	do
		if ( npcEnemy:CanBeSeen() )
		then
			for i = 0, npcEnemy:GetModifierCount() - 1
			do
				print( "[MIDBOT diag] enemy: " .. npcEnemy:GetModifierName( i )
					.. " stacks=" .. tostring( npcEnemy:GetModifierStackCount( i ) ) );
			end
		end
	end
end
