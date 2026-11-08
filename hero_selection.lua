----------------------------------------------------------------------------------------------------
-- MIDBOT: выбор героев
-- Наш бот — Shadow Fiend (nevermore), идёт в мид.
-- Остальные 4 слота команды — простые герои под управлением стандартного ИИ
-- (у них нет своих lua-файлов, значит работает дефолтная логика Valve).
-- Если в команде есть живой игрок — его слот пропускаем, он пикает сам.
----------------------------------------------------------------------------------------------------

-- Режим ОДНОГО бота для тестов 1v1 против живого игрока (Олег просил 08.11):
-- true = в команде будет ТОЛЬКО наш SF, ботов-тиммейтов нет вообще.
-- Вернуть false, когда снова понадобится полная команда 5x5.
local SOLO_1V1 = true;

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
	if ( SOLO_1V1 )
	then
		return {
			"MIDBOT v0.3 SOLO",
		};
	end
	return {
		"MIDBOT v0.3",
		"MIDBOT teammate 2",
		"MIDBOT teammate 3",
		"MIDBOT teammate 4",
		"MIDBOT teammate 5",
	};
end

function Think()

	local ids = GetTeamPlayers( GetTeam() );
	local pool = SOLO_1V1 and heroes_pool_solo or heroes_pool;
	local i = 1;

	for _, id in pairs( ids )
	do
		if ( IsPlayerBot( id ) and i <= #pool )
		then
			SelectHero( id, pool[i] );
			i = i + 1;
		end
	end

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

