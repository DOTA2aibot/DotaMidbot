----------------------------------------------------------------------------------------------------
-- MIDBOT: выбор героев
-- Наш бот — Shadow Fiend (nevermore), идёт в мид.
-- Остальные 4 слота команды — простые герои под управлением стандартного ИИ
-- (у них нет своих lua-файлов, значит работает дефолтная логика Valve).
-- Если в команде есть живой игрок — его слот пропускаем, он пикает сам.
----------------------------------------------------------------------------------------------------

-- Ограничиваем ВЫБОР героя одним SF в native 1v1 Solo Mid.
-- Это не удаляет player/bot slots: фактический состав после загрузки проверяется в игре.
-- В остальных режимах сохраняется командный пул. false отключает solo-пик и в 1v1.
local SOLO_1V1 = true;
-- DOTA_GAMEMODE_1V1MID = 21 в клиентском dota_shared_enums.proto.
local NATIVE_1V1_MODE = 21;
local soloPlayerID, lastSelectionLog = nil, nil;
local ControllerProfile = { name = "unknown", controller = "unknown" };
do
    local ok, info = pcall( function() return require( GetScriptDirectory() .. "/laning/profile" ) end );
    if ok and type( info ) == "table" then ControllerProfile = info end;
end

local function profile()
    if type( GetGameMode ) ~= "function" then return false, nil end;
    local ok, mode = pcall( GetGameMode );
    if not ok or type( mode ) ~= "number" or mode <= 0 then return false, nil end;
    return SOLO_1V1 and mode == NATIVE_1V1_MODE, mode;
end

local function selectedName( id )
    if type( GetSelectedHeroName ) ~= "function" then return nil end;
    local ok, name = pcall( GetSelectedHeroName, id );
    if ok and type( name ) == "string" then return name end;
    return nil;
end

local function report( ids, solo, mode, reason )
    local bots, selected, humans, unknown = 0, 0, 0, 0;
    for _, id in ipairs( ids ) do
        if IsPlayerBot( id ) then
            bots = bots + 1;
            local name = selectedName( id );
            if name == nil then unknown = unknown + 1 elseif name ~= "" then selected = selected + 1 end;
        else humans = humans + 1 end;
    end;
    local status = reason or ( solo and ( selected > 1 and "extra_bot_heroes"
        or ( unknown > 0 and "selected_names_unknown" or "check_match_roster" ) ) or "team_selection" );
    local line = "[MIDBOT selection] profile=" .. ( solo and "solo_1v1" or "team" )
        .. " game_mode=" .. tostring( mode ) .. " bot_slots=" .. bots .. " selected_bot_heroes=" .. selected
        .. " human_slots=" .. humans .. " unknown_bot_names=" .. unknown .. " status=" .. status
        .. " controller_profile=" .. tostring( ControllerProfile.name )
        .. " controller=" .. tostring( ControllerProfile.controller );
    if line ~= lastSelectionLog then print( line ); lastSelectionLog = line end;
end

local heroes_pool_solo = {
	"npc_dota_hero_nevermore",        -- наш мидер, единственный бот
};

local heroes_pool = {
	"npc_dota_hero_nevermore",        -- наш мидер
	"npc_dota_hero_juggernaut",
	"npc_dota_hero_bristleback",
	"npc_dota_hero_lion",
	"npc_dota_hero_crystal_maiden",
};

-- Имена ботов в игре: первый (наш SF) помечен, чтобы сразу было видно, что это наш
function GetBotNames()
	if ( profile() )
	then
		return {
			"MIDBOT v0.3.8-ward-phase",
		};
	end
	return {
		"MIDBOT v0.3.8-ward-phase",
		"MIDBOT teammate 2",
		"MIDBOT teammate 3",
		"MIDBOT teammate 4",
		"MIDBOT teammate 5",
	};
end

function Think()

	local ids = GetTeamPlayers( GetTeam() );
	local solo, mode = profile();
	if mode == nil then report( ids, false, nil, "game_mode_unknown_no_pick" ); return end;
	local pool = solo and heroes_pool_solo or heroes_pool;
	if solo then
		local firstBot, existingBot, existingCount, unknown = nil, nil, 0, false;
		for _, id in ipairs( ids ) do
			if not IsPlayerBot( id ) then report( ids, true, mode, "human_on_bot_side_no_pick" ); return end;
			firstBot = firstBot or id;
			local name = selectedName( id );
			if name == nil then unknown = true elseif name ~= "" then existingBot, existingCount = id, existingCount + 1 end;
		end;
		if existingCount > 1 then report( ids, true, mode, "extra_bot_heroes_no_pick" ); return end;
		if unknown then report( ids, true, mode, "selected_names_unknown_no_pick" ); return end;
		soloPlayerID = soloPlayerID or existingBot or firstBot;
		if existingBot and existingBot ~= soloPlayerID then report( ids, true, mode, "other_bot_already_selected_no_pick" ); return end;
		local present = false;
		for _, id in ipairs( ids ) do if id == soloPlayerID then present = true end end;
		if not present then report( ids, true, mode, "solo_slot_missing_no_pick" ); return end;
		local name = selectedName( soloPlayerID );
		if name == "" then SelectHero( soloPlayerID, pool[1] )
		elseif name ~= pool[1] then report( ids, true, mode, "unexpected_solo_hero_no_overwrite" ); return end;
		report( ids, true, mode ); return;
	end;
	local i = 1;

	for _, id in ipairs( ids )
	do
		if ( IsPlayerBot( id ) and i <= #pool )
		then
			if selectedName( id ) == "" then SelectHero( id, pool[i] ) end;
			i = i + 1;
		end
	end
	report( ids, false, mode );

end

----------------------------------------------------------------------------------------------------

-- Таблица индексируется слотом GetTeamPlayers (1..N), не глобальным PlayerID.
-- SF назначаем mid явно; остальные боты распределяются по боковым линиям.
-- Для живых игроков сохраняется базовая раскладка, их героев не переопределяем.
function UpdateLaneAssignments()
    local ids = GetTeamPlayers( GetTeam() );
    local lanes = {};
    local sideIndex = 0;
    for slot, id in ipairs( ids ) do
        lanes[slot] = slot % 2 == 0 and LANE_TOP or LANE_BOT;
        if IsPlayerBot( id ) then
            if GetSelectedHeroName( id ) == "npc_dota_hero_nevermore" then
                lanes[slot] = LANE_MID;
            else
                sideIndex = sideIndex + 1;
                lanes[slot] = sideIndex <= 2 and LANE_TOP or LANE_BOT;
            end
        end
    end
    return lanes;
end

