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
local RAZE_MANA_PCT_HARASS = 0.30;   -- T021: харасс-порог снижен 0.45 -> 0.30 (матч 9081721395: бот почти не харасил при возможности)
local REQUIEM_ENEMY_HP_PCT = 0.40;   -- добивать ультой, если у врага меньше 40% HP
local REQUIEM_SELF_HP_PCT  = 0.30;   -- или если нас почти убили

-- T021: мана-дисциплина (репорт Олега: "100 маны = 1 койл, а ботл полный").
local RAZE_MANA_COST = 75;           -- цена одного рейза, патч 7.4x
local RAZE_MANA_RESERVE = 150;       -- запас на 2 рейза для героя/отпора, не сливать в крипов
local BOTTLE_MANA_PER_CHARGE = 60;   -- мана с одного глотка ботла (консервативно)

-- Заряды ботла: 0 если ботла нет. Вынесено сюда — используют и рейзы, и ItemUsageThink.
function GetBottleCharges( npcBot )
	local nSlot = npcBot:FindItemSlot( "item_bottle" );
	if ( nSlot < 0 ) then return 0; end
	local item = npcBot:GetItemInSlot( nSlot );
	if ( item == nil ) then return 0; end
	return item:GetCurrentCharges();
end

-- Эффективная мана = текущая + то, что можно выпить из ботла прямо сейчас.
function GetEffectiveMana( npcBot )
	return npcBot:GetMana() + GetBottleCharges( npcBot ) * BOTTLE_MANA_PER_CHARGE;
end

-- Дистанции рейзов от точки каста (центр области)
local RAZE_DIST = { 200, 450, 700 };
local RAZE_RADIUS = 250;             -- радиус области рейза
local RAZE_CAST_POINT = 0.55;        -- задержка каста для упреждения

local abilityRaze = { nil, nil, nil };
local abilityRequiem = nil;
local abilityFeast = nil; -- Feast of Souls (7.4x): самобафф, скорость атаки/передвижения
local bAbilitiesInit = false;
local Observer, nextObserverWarning = nil, -math.huge;
do
    local ok, helper = pcall( require, GetScriptDirectory() .. "/laning/observer/entry" );
    if ok then Observer = helper
    else pcall( print, "[MIDBOT observer WARN] observer module unavailable; gameplay continues" ) end;
end
local function Observe( method, ... )
    if Observer and type( Observer[method] ) == "function" then
        local ok = pcall( Observer[method], ... );
        if not ok then
            local valid, now = pcall( function() return GameTime() end );
            if valid and type( now ) == "number" and now >= nextObserverWarning then
                pcall( print, "[MIDBOT observer WARN] " .. method .. " failed; gameplay continues" );
                nextObserverWarning = now + 10;
            end;
        end;
    end;
end
local function TrackedCast( bot, ability, reason )
    Observe( "BeforeAction", bot, ability );
    bot:Action_UseAbility( ability );
    Observe( "Action", bot, "cast", ability, nil, reason );
end

----------------------------------------------------------------------------------------------------
-- Интеграция T007 x T016 (план следующего этапа, п.4; ревью GPT по PR #23).
-- Передача управления идёт через AbilityGate из laning/runtime/guard.lua:
-- handshake по nonce (общий heartbeat lane<->ability callbacks) + lease+ACK
-- на конкретный план. AbilityGate вызывается КАЖДЫЙ callback (он же наш
-- heartbeat), ДО раннего return по IsUsingAbility.
-- Возвращает true только пока план реально владеет приказами — между планами
-- автономная логика способностей продолжает работать.
-- Прокачка (LevelUpThink) НЕ уступает: не боевой приказ, конфликта нет.
-- Интерфейс зафиксирован в docs/T016_BACKEND_API.md.
----------------------------------------------------------------------------------------------------
local LaneGuard = nil;
do
	-- pcall: без runtime/guard.lua (старая сборка) модуль работает автономно
	local ok, mod = pcall( require, GetScriptDirectory() .. "/laning/runtime/guard" );
	if ( ok ) then LaneGuard = mod; end
end

-- Уступаем ли управление общему исполнителю в этом тике (heartbeat + gate)
function JointExecutorOwnsBot( npcBot )
	if ( LaneGuard == nil or npcBot == nil ) then return false; end
	local ok, owns = pcall( LaneGuard.AbilityGate, npcBot );
	return ok and owns == true;
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
-- Порядок утверждён Олегом 08.11: сначала рейзы 4 и аура 4, Feast of Souls
-- ПЕРВЫЙ раз на 10-м уровне (после 4+4+ульт). Список приоритетный:
-- CanAbilityBeUpgraded сам отложит реквием до 6/12/18.
local SKILL_ORDER = {
	"nevermore_shadowraze1",      -- 1-4: рейзы максимум в первую очередь
	"nevermore_shadowraze1",
	"nevermore_shadowraze1",
	"nevermore_shadowraze1",
	"nevermore_dark_lord",        -- 5: аура
	"nevermore_requiem",          -- 6
	"nevermore_dark_lord",        -- 7-9: аура до 4
	"nevermore_dark_lord",
	"nevermore_dark_lord",
	"nevermore_frenzy",           -- 10: Feast of Souls, ПЕРВЫЙ поинт
	"nevermore_requiem",          -- 12
	"nevermore_frenzy",           -- 11,13,14
	"nevermore_frenzy",
	"nevermore_frenzy",
	"nevermore_requiem",          -- 18
};

-- T023: анти-спам прокачки. Матч 9082042282: учёт очков решил, что очко есть
-- (недосчитал dark_lord — by-name вернул nil), движок же всё потратил сам,
-- и попытка качнуть frenzy не удавалась — 15828 строк [MIDBOT levelup] за матч,
-- ActionImmediate_LevelAbility каждый фрейм. Запоминаем попытку: если за 5 сек
-- уровень способности НЕ изменился — очков реально нет, молчим.
local lastLvName, lastLvLevel, lastLvTime = nil, -1, -math.huge;
local function TryLevelAbility( npcBot, ability, sName )
	local lvl = ability:GetLevel();
	local now = GameTime();
	if ( sName == lastLvName and lvl == lastLvLevel and now - lastLvTime < 5.0 )
	then
		return; -- прошлая попытка не сработала — не спамим
	end
	lastLvName, lastLvLevel, lastLvTime = sName, lvl, now;
	npcBot:ActionImmediate_LevelAbility( sName );
	print( "[MIDBOT levelup] try " .. sName .. " from_lvl=" .. lvl );
end

function LevelUpThink( npcBot )

	-- T022: свой учёт очков. Матч 9081927137 (патч с бесплатными талантами
	-- 10/15/20/25): в логе НОЛЬ строк [MIDBOT levelup], при этом способности
	-- прокачивались — это движок автокачает по СТАРОМУ дефолтному билду
	-- (без frenzy), потому что GetAbilityPoints() у бота в этом окружении
	-- всегда 0 (все observer-снапшоты: ability_points=0). Считаем сами:
	-- очко за каждый уровень героя, таланты бесплатные (Олег, 08.11).
	-- T023: считаем по СЛОТАМ, а не по именам — матч 9082042282 показал, что
	-- GetAbilityByName("nevermore_dark_lord") возвращает nil, хотя в слоте 4
	-- аура есть, и by-name учёт недосчитывал потраченные движком очки.
	-- Исключения: рейзы 2/3 зеркалят первый (очков не тратят), Necromastery —
	-- врождённая (качается сама), таланты special_bonus_unique_* бесплатные.
	local nPoints = npcBot:GetAbilityPoints();
	if ( nPoints < 1 )
	then
		-- fail-closed для моков/старого окружения: без GetLevel не считаем
		if ( type( npcBot.GetLevel ) ~= "function" ) then return end;
		if ( type( npcBot.GetAbilityInSlot ) ~= "function" ) then return end;
		local nSpent = 0;
		for nSlot = 0, 23
		do
			local ab = npcBot:GetAbilityInSlot( nSlot );
			if ( ab ~= nil and type( ab.GetLevel ) == "function" and type( ab.GetName ) == "function" )
			then
				local name = ab:GetName();
				if ( name ~= "nevermore_shadowraze2" and name ~= "nevermore_shadowraze3"
					and name ~= "nevermore_necromastery"
					and not name:find( "special_bonus_unique", 1, true ) )
				then
					nSpent = nSpent + ab:GetLevel();
				end
			end
		end
		if ( npcBot:GetLevel() <= nSpent ) then return end; -- очков нет
		-- Движок мог уже автокачать что-то своё — nSpent это учитывает.
	end

	local seen = {};
	for _, sName in ipairs( SKILL_ORDER )
	do
		seen[sName] = ( seen[sName] or 0 ) + 1;
		local ability = npcBot:GetAbilityByName( sName );
		-- T022: fail-closed, если у объекта нет CanAbilityBeUpgraded (моки/старое
		-- окружение) — иначе падение здесь абортирует весь AbilityUsageThink.
		if ( ability ~= nil
			and type( ability.CanAbilityBeUpgraded ) == "function"
			and ability:CanAbilityBeUpgraded()
			and ability:GetLevel() < seen[sName] )
		then
			TryLevelAbility( npcBot, ability, sName );
			return;
		end
	end

	-- Fallback (фикс аудита GPT): если всё из списка выкачано или недоступно,
	-- тратим очко на первую доступную способность — включая таланты.
	-- Раньше очки после 6-го уровня могли копиться непотраченными.
	-- T022: fail-closed для моков/старого окружения без GetAbilityInSlot —
	-- иначе падение здесь абортирует весь Think до ConsiderRequiem.
	if ( type( npcBot.GetAbilityInSlot ) ~= "function" ) then return end;
	for nSlot = 0, 23
	do
		local ability = npcBot:GetAbilityInSlot( nSlot );
		if ( ability ~= nil
			and type( ability.CanAbilityBeUpgraded ) == "function"
			and ability:CanAbilityBeUpgraded()
			and ability:GetLevel() < ability:GetMaxLevel() )
		then
			TryLevelAbility( npcBot, ability, ability:GetName() );
			return;
		end
	end

end

----------------------------------------------------------------------------------------------------
-- T023: AbilityLevelUpThink — ОТДЕЛЬНЫЙ колбэк движка для прокачки. Интеграционная
-- сборка GPT (матч 9082079610, v0.3.5-all-test) показала: с этим колбэком движок
-- отдаёт очки НАМ, а не автокачает по старому билду — frenzy/dark_lord прокачаны
-- полностью по нашему SKILL_ORDER. Держим и вызов из AbilityUsageThink: если
-- колбэк в каком-то окружении не вызывается, сработает наш учёт по слотам;
-- backoff 5с в TryLevelAbility защищает от спама при гонке.
----------------------------------------------------------------------------------------------------
function AbilityLevelUpThink()
	local npcBot = GetBot();
	if ( npcBot == nil ) then return end;
	LevelUpThink( npcBot );
end

----------------------------------------------------------------------------------------------------

function InitAbilities( npcBot )
	abilityRaze[1] = npcBot:GetAbilityByName( "nevermore_shadowraze1" );
	abilityRaze[2] = npcBot:GetAbilityByName( "nevermore_shadowraze2" );
	abilityRaze[3] = npcBot:GetAbilityByName( "nevermore_shadowraze3" );
	abilityRequiem = npcBot:GetAbilityByName( "nevermore_requiem" );
	abilityFeast = npcBot:GetAbilityByName( "nevermore_frenzy" ); -- 7.4x, активка на D
	if ( abilityFeast == nil )
	then
		-- Имя ПОДТВЕРЖДЕНО игрой: матчи 9080995642/9081000035 (08.11), дамп
		-- слотов [MIDBOT diag] показал ability[3]=nevermore_frenzy. Если эта
		-- строка снова появилась в логе — имя сменилось в новом патче.
		print( "[MIDBOT diag] nevermore_frenzy НЕ НАЙДЕНА в этом патче — активка на D отключена, проверить имя" );
	end
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
	if ( npcBot == nil ) then return end;
	Observe( "Tick", npcBot ); -- read-only, 1Hz sample; работает и во время using/retreat

	-- Диагностическая обёртка: в логе 08.11 были «Script Runtime Error: error in
	-- error handling» без указания источника. Теперь наши ошибки печатаются
	-- с текстом и traceback — источник будет виден сразу.
	local ok, err = xpcall( function() AbilityUsageThinkInner( npcBot ) end,
		function( e )
			-- Защита обработчика (ревью GPT): прямой debug.traceback() может
			-- быть недоступен в VM — тогда диагностика сама падает с «error in
			-- error handling» и стирает первоначальную ошибку. Исходный текст
			-- сохраняем всегда, traceback получаем через защищённый вызов.
			local msg = tostring( e );
			local okTb, tb = pcall( function()
				if ( debug ~= nil and type( debug.traceback ) == "function" )
				then
					return debug.traceback();
				end
				return "traceback unavailable";
			end );
			return msg .. " | " .. ( okTb and tostring( tb ) or "traceback call failed" );
		end );
	if ( not ok ) then print( "[MIDBOT ability ERROR] " .. tostring( err ) ); end

end

function AbilityUsageThinkInner( npcBot )

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
		TrackedCast( npcBot, abilityRequiem, "existing_requiem_rule" );
		return;
	end

	-- 2. Рейз по вражескому герою (харасс / добивание)
	local desireRaze, locRaze, razeAbility = ConsiderRazeOnHero( npcBot );
	if ( desireRaze > 0 )
	then
		CastRaze( npcBot, razeAbility, locRaze );
		return;
	end

	-- 3. Feast of Souls — самобафф перед дракой или под пачку крипов
	if ( ConsiderFeastOfSouls( npcBot ) > 0 )
	then
		TrackedCast( npcBot, abilityFeast, "existing_frenzy_rule" );
		return;
	end

	-- 3. Рейз по крипам (фарм)
	local desireFarm, locFarm, farmAbility = ConsiderRazeOnCreeps( npcBot );
	if ( desireFarm > 0 )
	then
		CastRaze( npcBot, farmAbility, locFarm );
		return;
	end
	Observe( "AfterAbilities", npcBot ); -- отдельный opt-in ward profile; без перемещений

end

----------------------------------------------------------------------------------------------------
-- T021: использование предметов. До этого ItemUsageThink в файле ОТСУТСТВОВАЛ —
-- движок вызывал пустое место, и бот никогда не пил ботл и не жал ванд
-- (матч 9081721395: 100 маны при полном ботле). Реализуем минимум мидера:
-- ботл для маны/хп и ванд в трудную минуту.
-- Ботл: реген слетается от урона героев, поэтому рядом с врагом пьём только
-- по нужде (маны нет даже на один рейз) или под добивание.
----------------------------------------------------------------------------------------------------
function ItemUsageThink()

	local npcBot = GetBot();
	if ( npcBot == nil or not npcBot:IsAlive() ) then return end;

	local ok, err = pcall( ItemUsageThinkInner, npcBot );
	if ( not ok ) then print( "[MIDBOT item ERROR] " .. tostring( err ) ); end

end

function ItemUsageThinkInner( npcBot )

	if ( npcBot:IsUsingAbility() or npcBot:IsChanneling() or npcBot:IsSilenced()
		or npcBot:IsMuted() or npcBot:IsStunned() )
	then
		return;
	end

	local manaPct = npcBot:GetMana() / npcBot:GetMaxMana();
	local hpPct = npcBot:GetHealth() / npcBot:GetMaxHealth();
	local tableEnemyHeroes = npcBot:GetNearbyHeroes( 700, true, BOT_MODE_NONE );
	local bEnemyClose = ( tableEnemyHeroes ~= nil and #tableEnemyHeroes > 0 );

	-- Ботл
	local nBottleSlot = npcBot:FindItemSlot( "item_bottle" );
	if ( nBottleSlot >= 0 )
	then
		local itemBottle = npcBot:GetItemInSlot( nBottleSlot );
		if ( itemBottle ~= nil
			and itemBottle:IsFullyCastable()
			and itemBottle:GetCurrentCharges() > 0
			and not npcBot:HasModifier( "modifier_bottle_regeneration" ) )
		then
			local bDrink = false;
			if ( not bEnemyClose )
			then
				-- Спокойная обстановка: поддерживаем ресурс
				if ( manaPct < 0.45 or hpPct < 0.50 ) then bDrink = true; end
			else
				-- Враг рядом: пьём, только если маны нет даже на один рейз
				-- (случай Олега) или врага добиваем и нужен ресурс на комбо
				if ( npcBot:GetMana() < RAZE_MANA_COST ) then bDrink = true; end
				if ( not bDrink and manaPct < 0.45 )
				then
					for _, npcEnemy in pairs( tableEnemyHeroes )
					do
						if ( npcEnemy:CanBeSeen()
							and npcEnemy:GetHealth() / npcEnemy:GetMaxHealth() <= 0.40 )
						then
							bDrink = true;
							break;
						end
					end
				end
			end
			if ( bDrink )
			then
				Observe( "BeforeAction", npcBot, itemBottle );
				npcBot:Action_UseAbilityOnEntity( itemBottle, npcBot );
				Observe( "Action", npcBot, "item_use", itemBottle, nil, "t021_bottle_mana_or_hp" );
				print( "[MIDBOT item] bottle sip mana=" .. npcBot:GetMana() .. " hp%=" .. hpPct );
				return;
			end
		end
	end

	-- Манго (T022): экономика GPT его покупает, но использовать некому.
	-- Экстренная мана перед кастом: враг рядом, маны нет на рейз, ботл пуст/занят.
	-- Манго — consumable без цели, работает только из инвентаря (слоты 0-5,
	-- из стэша не съесть — поэтому доставка курьером критична).
	local nMangoSlot = npcBot:FindItemSlot( "item_enchanted_mango" );
	if ( nMangoSlot >= 0 and nMangoSlot <= 5 )
	then
		local itemMango = npcBot:GetItemInSlot( nMangoSlot );
		if ( itemMango ~= nil
			and itemMango:IsFullyCastable()
			and npcBot:GetMana() < RAZE_MANA_COST
			and GetBottleCharges( npcBot ) == 0
			and bEnemyClose )
		then
			Observe( "BeforeAction", npcBot, itemMango );
			npcBot:Action_UseAbility( itemMango );
			Observe( "Action", npcBot, "item_use", itemMango, nil, "t022_mango_emergency_mana" );
			print( "[MIDBOT item] mango mana=" .. npcBot:GetMana() );
			return;
		end
	end

	-- Кларити (T023): матч 9082042282 — куплена и лежала мёртвым грузом.
	-- Реген слетается от урона героев: только когда врагов нет в 900,
	-- мана ниже половины и мы не под её эффектом. Только слоты 0-5.
	local nClaritySlot = npcBot:FindItemSlot( "item_clarity" );
	if ( nClaritySlot >= 0 and nClaritySlot <= 5 and manaPct < 0.50
		and not npcBot:HasModifier( "modifier_clarity_potion" ) )
	then
		local itemClarity = npcBot:GetItemInSlot( nClaritySlot );
		local tableEnemyWide = npcBot:GetNearbyHeroes( 900, true, BOT_MODE_NONE );
		if ( itemClarity ~= nil and itemClarity:IsFullyCastable()
			and ( tableEnemyWide == nil or #tableEnemyWide == 0 ) )
		then
			Observe( "BeforeAction", npcBot, itemClarity );
			npcBot:Action_UseAbilityOnEntity( itemClarity, npcBot );
			Observe( "Action", npcBot, "item_use", itemClarity, nil, "t023_clarity_calm_mana" );
			print( "[MIDBOT item] clarity mana%=" .. manaPct );
			return;
		end
	end

	-- Фласка (T023): та же логика по здоровью — в спокойствии и не под её эффектом.
	local nFlaskSlot = npcBot:FindItemSlot( "item_flask" );
	if ( nFlaskSlot >= 0 and nFlaskSlot <= 5 and hpPct < 0.50
		and not npcBot:HasModifier( "modifier_flask_healing" ) )
	then
		local itemFlask = npcBot:GetItemInSlot( nFlaskSlot );
		local tableEnemyWide = npcBot:GetNearbyHeroes( 900, true, BOT_MODE_NONE );
		if ( itemFlask ~= nil and itemFlask:IsFullyCastable()
			and ( tableEnemyWide == nil or #tableEnemyWide == 0 ) )
		then
			Observe( "BeforeAction", npcBot, itemFlask );
			npcBot:Action_UseAbilityOnEntity( itemFlask, npcBot );
			Observe( "Action", npcBot, "item_use", itemFlask, nil, "t023_flask_calm_hp" );
			print( "[MIDBOT item] flask hp%=" .. hpPct );
			return;
		end
	end

	-- Ванд/стик: отхил в трудную минуту
	local sWandName = ( npcBot:FindItemSlot( "item_magic_wand" ) >= 0 ) and "item_magic_wand" or "item_magic_stick";
	local nWandSlot = npcBot:FindItemSlot( sWandName );
	if ( nWandSlot >= 0 )
	then
		local itemWand = npcBot:GetItemInSlot( nWandSlot );
		if ( itemWand ~= nil
			and itemWand:IsFullyCastable()
			and itemWand:GetCurrentCharges() >= 8
			and ( hpPct < 0.40 or ( hpPct < 0.60 and manaPct < 0.25 ) ) )
		then
			Observe( "BeforeAction", npcBot, itemWand );
			npcBot:Action_UseAbilityOnEntity( itemWand, npcBot );
			Observe( "Action", npcBot, "item_use", itemWand, nil, "t021_wand_emergency" );
			print( "[MIDBOT item] wand hp%=" .. hpPct .. " mana%=" .. manaPct );
			return;
		end
	end

end

----------------------------------------------------------------------------------------------------
-- Каст рейза. Рейзы — NO_TARGET способности: бьют на фикс. дистанции
-- в направлении, КУДА СМОТРИТ герой. Action_UseAbilityOnLocation тут не работает
-- (фикс аудита GPT).
-- Фикс 2 (ревью GPT по логу observe): AttackMove -> каст в одном тике НЕ
-- гарантирует, что герой успел развернуться — рейз уходит по старому взгляду.
-- Поэтому: если ещё не смотрим на цель — только доворачиваемся этим тиком;
-- каст уходит следующим тиком, когда IsFacingLocation подтвердит разворот.
----------------------------------------------------------------------------------------------------
-- Ревью GPT (PR #27): допуск по углу НЕ гарантирует попадание — при ошибке 19°
-- центр рейза уходит на ~360 ед. мимо (радиус 250). Поэтому перед кастом
-- проверяем ФАКТИЧЕСКИЙ центр удара по текущему направлению взгляда героя,
-- а не только угол. Доворот — коротким шагом (как Prepare в runtime GPT:
-- face_distance=48), а не движением до самой цели.
local RAZE_HIT_MARGIN = 40;     -- факт. центр должен быть внутри радиуса с запасом
local RAZE_FACE_STEP = 48;      -- длина шага доворота (паттерн GPT face_distance)
local RAZE_FACE_THROTTLE = 0.15;-- пауза между шагами доворота, сек
local TOWER_DANGER_RANGE = 750; -- дальность вышки 700 + запас
local nNextFaceTime = 0;

function GetRazeIndexOf( razeAbility )
	for i = 1, 3
	do
		if ( abilityRaze[i] == razeAbility ) then return i end;
	end
	return nil;
end

-- Фактический центр удара i-го рейза при ТЕКУЩЕМ направлении взгляда героя
function GetCurrentRazeImpact( npcBot, i )
	local vBot = npcBot:GetLocation();
	local rad = math.rad( npcBot:GetFacing() );
	return vBot + Vector( math.cos( rad ) * RAZE_DIST[i], math.sin( rad ) * RAZE_DIST[i], 0 );
end

function CastRaze( npcBot, razeAbility, vLoc )
	-- Прерывание подготовки: в отступлении не ходим к цели и не кастуем.
	-- (Остальные прерывания — устаревшая цель/мана/доступность — ловятся сами:
	-- Consider-функции пересчитываются каждый тик и просто перестанут звать CastRaze.)
	if ( npcBot:GetActiveMode() == BOT_MODE_RETREAT ) then return end;

	local i = GetRazeIndexOf( razeAbility );
	if ( i ~= nil )
	then
		local vImpact = GetCurrentRazeImpact( npcBot, i );
		if ( Dist2D( vLoc, vImpact ) <= RAZE_RADIUS - RAZE_HIT_MARGIN )
		then
			TrackedCast( npcBot, razeAbility, "existing_raze_geometry_verified" );
			return;
		end
	elseif ( npcBot:IsFacingLocation( vLoc, 5 ) )
	then
		-- Запасной вариант (способность не из abilityRaze): жёсткий допуск 5°
		TrackedCast( npcBot, razeAbility, "existing_raze_facing_fallback" );
		return;
	end

	-- Доворот: КОРОТКИЙ шаг в сторону цели, а не движение до неё
	local now = GameTime();
	if ( now < nNextFaceTime ) then return end;

	local vBot = npcBot:GetLocation();
	local dx = vLoc.x - vBot.x;
	local dy = vLoc.y - vBot.y;
	local len = math.sqrt( dx * dx + dy * dy );
	if ( len < 1 ) then return end;

	local vStep = vBot + Vector( dx / len * RAZE_FACE_STEP, dy / len * RAZE_FACE_STEP, 0 );

	-- Шаг не должен заводить нас под вражескую вышку
	local tableTowers = npcBot:GetNearbyTowers( 900, true );
	for _, npcTower in pairs( tableTowers )
	do
		if ( GetUnitToLocationDistance( npcTower, vStep ) <= TOWER_DANGER_RANGE ) then return end;
	end

	if ( IsLocationPassable( vStep ) )
	then
		npcBot:Action_MoveDirectly( vStep ); -- прямой микрошаг, без построения пути
		Observe( "Action", npcBot, "existing_face_move", nil, vStep, "existing_raze_turn" );
		nNextFaceTime = now + RAZE_FACE_THROTTLE;
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

-- Безопасный вызов метода юнита. Лог матча 9080972160 (08.11): IsMoving
-- отсутствует в этом Bot API для чужих героев (nil) — прямой вызов роняет
-- весь Think. Метод проверяем перед вызовом, ошибку глушим в nil.
function SafeUnitCall( npcUnit, sMethod )
	local fn = npcUnit[sMethod];
	if ( type( fn ) ~= "function" ) then return nil end;
	local ok, res = pcall( fn, npcUnit );
	if ( not ok ) then return nil end;
	return res;
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
-- Feast of Souls (7.4x, активка на D, nevermore_frenzy): самобафф скорости
-- атаки/передвижения. Прожимаем перед боем (враг рядом) или под жирную пачку
-- крипов. Ману на рейзы бережём: ниже 50% маны не баффаемся.
-- Имя nevermore_frenzy подтверждено игрой (дамп слотов, 08.11).
----------------------------------------------------------------------------------------------------
local FEAST_MANA_PCT = 0.50;      -- минимум маны для баффа
local FEAST_ENEMY_RADIUS = 900;   -- враг в этом радиусе = скоро драка
local FEAST_CREEP_PACK = 4;       -- столько крипов рядом = фарм-бафф

function ConsiderFeastOfSouls( npcBot )

	if ( abilityFeast == nil or not abilityFeast:IsFullyCastable() )
	then
		return BOT_ACTION_DESIRE_NONE;
	end

	if ( npcBot:GetMana() / npcBot:GetMaxMana() < FEAST_MANA_PCT )
	then
		return BOT_ACTION_DESIRE_NONE;
	end

	-- Враг рядом — бафф перед дракой (приоритет)
	local tableEnemyHeroes = npcBot:GetNearbyHeroes( FEAST_ENEMY_RADIUS, true, BOT_MODE_NONE );
	for _, npcEnemy in pairs( tableEnemyHeroes )
	do
		if ( npcEnemy:CanBeSeen() and not npcEnemy:IsInvulnerable() )
		then
			return BOT_ACTION_DESIRE_MODERATE;
		end
	end

	-- Пачка крипов — бафф под фарм
	local tableEnemyCreeps = npcBot:GetNearbyLaneCreeps( 700, true );
	if ( #tableEnemyCreeps >= FEAST_CREEP_PACK )
	then
		return BOT_ACTION_DESIRE_LOW;
	end

	return BOT_ACTION_DESIRE_NONE;
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
	local bestEnemyHpPct = 1.0; -- T021: HP цели лучшего кандидата, для усиленного харасса

	for _, npcEnemy in pairs( tableEnemyHeroes )
	do
		if ( npcEnemy:CanBeSeen() and not npcEnemy:IsMagicImmune() and not npcEnemy:IsInvulnerable() )
		then
			-- Упреждение: куда цель доедет за время каста. Методы движения
			-- могут отсутствовать в Bot API (IsMoving — точно, см. SafeUnitCall),
			-- поэтому просто пробуем взять скорость: стоячая цель даст ~0,
			-- отсутствие метода — статичное прицеливание без падения.
			local vLoc = npcEnemy:GetLocation();
			local vVel = SafeUnitCall( npcEnemy, "GetVelocity" );
			if ( vVel ~= nil )
			then
				vLoc = vLoc + vVel * RAZE_CAST_POINT;
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
							bestEnemyHpPct = npcEnemy:GetHealth() / npcEnemy:GetMaxHealth();
							bestKill = bestEnemyHpPct <= 0.25;
						end
					end
				end
			end
		end
	end

	if ( bestRaze == nil ) then return BOT_ACTION_DESIRE_NONE, nil, nil end;

	-- Добивание — всегда; харасс — если маны хватает. T021: считаем ману С ботлом
	-- (полный ботл = ещё ~3 рейза), иначе бот не харасил, имея полный ботл.
	-- Враг ниже 40% HP = реальный шанс убить за 2-3 рейза: приоритет выше.
	local effManaPct = GetEffectiveMana( npcBot ) / npcBot:GetMaxMana();
	if ( bestKill and manaPct > 0.15 ) then return BOT_ACTION_DESIRE_HIGH, bestLoc, bestRaze end;
	if ( bestEnemyHpPct <= 0.40 and effManaPct >= 0.25 ) then return BOT_ACTION_DESIRE_HIGH, bestLoc, bestRaze end;
	if ( effManaPct >= RAZE_MANA_PCT_HARASS ) then return BOT_ACTION_DESIRE_MODERATE, bestLoc, bestRaze end;

	return BOT_ACTION_DESIRE_NONE, nil, nil;
end

----------------------------------------------------------------------------------------------------
-- T023: не тратим рейз на крипа, которого ДОБЬЮТ свои до удара (каст 0.55с).
-- Репорт Олега 08.11: «крип уже мёртв, а он спустя 0.5 сек жмёт койл в труп».
-- Усиление 08.11 (вечер): считаем не только снаряды в полёте, но и союзных
-- крипов/вышки, которые УЖЕ бьют цель — за каст-поинт долетит минимум по удару.
-- Нет API/ошибка — не пропускаем (fail-open, как раньше).
----------------------------------------------------------------------------------------------------
local CREEP_PROJECTILE_DAMAGE = 22;
local TOWER_HIT_DAMAGE = 110;
local function SafeAttackTarget( unit )
	local ok, target = pcall( function() return unit:GetAttackTarget() end );
	if ( ok ) then return target end;
	return nil;
end
local function WillDieBeforeRaze( npcBot, npcCreep )
	-- Труп/умирающий — не кастуем вообще
	if ( npcCreep:GetHealth() <= 0
		or ( type( npcCreep.IsAlive ) == "function" and not npcCreep:IsAlive() ) )
	then
		return true;
	end
	local nHp = npcCreep:GetHealth();
	local incoming = 0;
	-- 1) летящие снаряды союзников
	local ok, projectiles = pcall( function() return npcCreep:GetIncomingTrackingProjectiles() end );
	if ( ok and type( projectiles ) == "table" )
	then
		for _, proj in pairs( projectiles ) do
			if ( proj.is_attack ) then incoming = incoming + CREEP_PROJECTILE_DAMAGE end;
		end
	end
	if ( incoming >= nHp ) then return true end;
	-- 2) союзные крипы, которые уже атакуют эту цель
	local okA, allies = pcall( function() return npcBot:GetNearbyLaneCreeps( 1200, false ) end );
	if ( okA and type( allies ) == "table" )
	then
		for _, ally in pairs( allies ) do
			if ( SafeAttackTarget( ally ) == npcCreep )
			then
				incoming = incoming + CREEP_PROJECTILE_DAMAGE;
				if ( incoming >= nHp ) then return true end;
			end
		end
	end
	-- 3) союзная вышка, которая бьёт цель
	local okT, towers = pcall( function() return npcBot:GetNearbyTowers( 1200, false ) end );
	if ( okT and type( towers ) == "table" )
	then
		for _, npcTower in pairs( towers ) do
			if ( SafeAttackTarget( npcTower ) == npcCreep )
			then
				incoming = incoming + TOWER_HIT_DAMAGE;
				if ( incoming >= nHp ) then return true end;
			end
		end
	end
	return false;
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
	-- T021: мана-дисциплина. Раньше: плоский порог 25% маны — бот спокойно
	-- сливал последние 75 маны в крипов и оставался пустым для героя/руны
	-- (репорт Олега: "100 маны = 1 койл, а ботл полный"). Теперь держим резерв
	-- RAZE_MANA_RESERVE, КРОМЕ случаев: (а) есть заряды ботла — выпьем и
	-- докастуем; (б) добивание под своей вышкой — там тратимся до дна.
	local nMana = npcBot:GetMana();
	if ( nMana < RAZE_MANA_COST + RAZE_MANA_RESERVE and GetBottleCharges( npcBot ) == 0 )
	then
		-- tableAlliedTowers ниже ещё не собран — спрашиваем вышки напрямую
		local tableOwn = npcBot:GetNearbyTowers( 900, false );
		local bUnderOwnTower = ( tableOwn ~= nil and #tableOwn > 0 );
		if ( not bUnderOwnTower or nMana < RAZE_MANA_COST )
		then
			return BOT_ACTION_DESIRE_NONE, nil, nil;
		end
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
					if ( npcCreep:GetHealth() <= EffectiveRazeDamage( nDamage, npcCreep )
						and not WillDieBeforeRaze( npcBot, npcCreep ) ) -- T023: свои уже добивают
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

-- Число модификаторов юнита (ревью GPT: в проверенном Bot API — NumModifiers,
-- GetModifierCount есть не везде; перебираем оба через pcall)
function ModifierCountOf( npcUnit )
	local ok, n = pcall( function() return npcUnit:NumModifiers() end );
	if ( ok and type( n ) == "number" ) then return n; end
	ok, n = pcall( function() return npcUnit:GetModifierCount() end );
	if ( ok and type( n ) == "number" ) then return n; end
	return 0;
end

-- Число душ SF: стаки модификатора врождённой Necromastery.
-- Возвращает nil, если имя модификатора в текущем патче другое (тогда смотрим diag-лог).
function GetSoulsCount( npcBot )
	for i = 0, ModifierCountOf( npcBot ) - 1
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
	for i = 0, ModifierCountOf( npcEnemy ) - 1
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
	-- Фарм-телеметрия (T019). Матч 9081051372: души=0 весь матч, и по логу
	-- было неотличимо «бот не добивает» от «Necromastery не действует».
	-- LH/denies измеряются напрямую из Bot API, отдельно от душ.
	-- Ноль душ сам по себе не доказывает отсутствие добиваний:
	-- счётчик душ и его доступность нельзя использовать вместо LH.
	print( "[MIDBOT diag] stats: lvl=" .. npcBot:GetLevel()
		.. " lh=" .. npcBot:GetLastHits()
		.. " denies=" .. npcBot:GetDenies()
		.. " gold=" .. npcBot:GetGold()
		.. " souls=" .. tostring( GetSoulsCount( npcBot ) ) );
	-- Имена способностей в слотах (проверка имён текущего патча, напр. feast_of_souls)
	for nSlot = 0, 8
	do
		local ability = npcBot:GetAbilityInSlot( nSlot );
		if ( ability ~= nil )
		then
			print( "[MIDBOT diag] ability[" .. nSlot .. "]=" .. ability:GetName() );
		end
	end
	for i = 0, ModifierCountOf( npcBot ) - 1
	do
		print( "[MIDBOT diag] self: " .. npcBot:GetModifierName( i )
			.. " stacks=" .. tostring( npcBot:GetModifierStackCount( i ) ) );
	end
	local tableEnemyHeroes = npcBot:GetNearbyHeroes( 1200, true, BOT_MODE_NONE );
	for _, npcEnemy in pairs( tableEnemyHeroes )
	do
		if ( npcEnemy:CanBeSeen() )
		then
			-- Доступность методов движения в этом окружении (матч 9080972160:
			-- IsMoving был nil у чужого героя) — печатаем факт, а не гадаем
			print( "[MIDBOT diag] enemy API: IsMoving=" .. type( npcEnemy.IsMoving )
				.. " GetVelocity=" .. type( npcEnemy.GetVelocity ) );
			for i = 0, ModifierCountOf( npcEnemy ) - 1
			do
				print( "[MIDBOT diag] enemy: " .. npcEnemy:GetModifierName( i )
					.. " stacks=" .. tostring( npcEnemy:GetModifierStackCount( i ) ) );
			end
		end
	end
end
