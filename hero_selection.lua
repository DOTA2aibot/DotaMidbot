----------------------------------------------------------------------------------------------------
-- MIDBOT: выбор героев
-- Наш бот — Shadow Fiend (nevermore), идёт в мид.
-- Остальные 4 слота команды — простые герои под управлением стандартного ИИ
-- (у них нет своих lua-файлов, значит работает дефолтная логика Valve).
-- Если в команде есть живой игрок — его слот пропускаем, он пикает сам.
----------------------------------------------------------------------------------------------------

local heroes_pool = {
	"npc_dota_hero_nevermore",        -- наш мидер
	"npc_dota_hero_juggernaut",
	"npc_dota_hero_bristleback",
	"npc_dota_hero_lion",
	"npc_dota_hero_crystal_maiden",
};

-- Имена ботов в игре: первый (наш SF) помечен, чтобы сразу было видно, что это наш
function GetBotNames()
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
	local i = 1;

	for _, id in pairs( ids )
	do
		if ( IsPlayerBot( id ) and i <= #heroes_pool )
		then
			SelectHero( id, heroes_pool[i] );
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

