-- XP -- за смерть в радиусе по правилам сценария, не награда за собственный last hit.
local D = require( GetScriptDirectory() .. "/laning/advanced/mechanics" );
local M = {};
function M.AtDeath( s, target, dt )
    local rules = s.xp_rules or {};
    if not rules.verified or not D.Number( rules.radius ) or rules.radius <= 0 then return { status = "xp_rules_unknown" } end;
    if s.hero.alive == false then return { status = "hero_dead", eligible = false, xp = 0 } end;
    if s.hero.alive ~= true then return { status = "hero_alive_unknown" } end;
    if target.kind ~= "enemy_creep" then return { status = "not_enemy_lane_creep", eligible = false, xp = 0 } end;
    local radius = rules.radius;
    local p = D.Predict( target, dt );
    local distance = D.Distance( s.hero, p ); -- текущие планы не перемещают своего героя
    local error = ( target.position_error_per_s or 0 ) * dt;
    if math.max( 0, distance - error ) > radius then return { status = "outside", eligible = false, xp = 0, distance = distance } end;
    if distance + error > radius then return { status = "boundary_uncertain", distance = distance } end;
    local recipients = target.xp_allied_recipients;
    if not D.Number( recipients ) or recipients < 1 or recipients % 1 ~= 0 or not target.xp_recipients_verified then
        return { status = "recipients_unknown", eligible = true, distance = distance };
    end
    local bounty = target.bounty_xp;
    if not D.Number( bounty ) or bounty < 0 then return { status = "bounty_unknown", eligible = true } end;
    if not D.Number( target.xp_factor ) or target.xp_factor < 0 then return { status = "xp_modifiers_unknown", eligible = true } end;
    return { status = "estimated", eligible = true, xp = math.floor( bounty * target.xp_factor / recipients ), distance = distance,
        assumptions = "observed recipients and supplied XP factor; revalidate at death" };
end
function M.Context( s, horizon )
    local out = { in_range_xp = 0, at_risk_xp = 0, unknown_deaths = 0, records = {},
        requires_reposition = false, level_timing = "unknown", predictions_are_outcomes = false };
    -- Внешние прогнозы смертей из видимой истории, независимо от наших last hits.
    for _, death in ipairs( s.expected_creep_deaths or {} ) do
        if death.source == "visible_forecast" and D.Number( death.at_s ) and death.at_s >= 0 and death.at_s <= horizon then
            local target;
            for _, t in ipairs( s.targets or {} ) do if t.id == death.target_id and t.visible and t.alive then target = t end end;
            if target then
                local r = M.AtDeath( s, target, death.at_s ); r.target_id, r.at_s = target.id, death.at_s;
                out.records[#out.records + 1] = r;
                if r.xp and r.eligible then out.in_range_xp = out.in_range_xp + r.xp;
                elseif r.status == "outside" then
                    out.requires_reposition = true;
                    if D.Number( target.bounty_xp ) then out.at_risk_xp = out.at_risk_xp + target.bounty_xp end;
                else out.unknown_deaths = out.unknown_deaths + 1 end;
            end
        end
    end
    table.sort( out.records, function( a, b ) if a.at_s ~= b.at_s then return a.at_s < b.at_s end; return tostring( a.target_id ) < tostring( b.target_id ) end );
    if out.unknown_deaths == 0 and D.Number( s.hero.xp_needed_to_level ) and s.hero.xp_needed_to_level > 0 then
        out.level_timing = out.in_range_xp >= s.hero.xp_needed_to_level and "possible_from_forecast" or "insufficient_forecast_xp";
    end
    return out;
end
return M;
