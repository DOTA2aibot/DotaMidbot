local U=require(GetScriptDirectory().."/laning/tactical/util");
local C=require(GetScriptDirectory().."/laning/tactical/config");
local B=require(GetScriptDirectory().."/laning/tactical/broker");
local Q=require(GetScriptDirectory().."/laning/tactical/requiem");
local Resources=require(GetScriptDirectory().."/laning/tactical/resources");
local Finisher=require(GetScriptDirectory().."/laning/tactical/finisher");
local Trades=require(GetScriptDirectory().."/laning/tactical/trades");
local Sentry=require(GetScriptDirectory().."/laning/vision/sentry");
local Items=require(GetScriptDirectory().."/laning/tactical/items");
local Threat=require(GetScriptDirectory().."/laning/tactical/threats");
local PT=require(GetScriptDirectory().."/laning/tactical/treads");
local Neutral=require(GetScriptDirectory().."/laning/tactical/neutrals");
local Ward=require(GetScriptDirectory().."/laning/tactical/wards");
local Phase=require(GetScriptDirectory().."/laning/vision/service");
local VisionDiagnostics=require(GetScriptDirectory().."/laning/vision/diagnostics");
local Delivery=require(GetScriptDirectory().."/laning/items/delivery_mode");
local Recovery=require(GetScriptDirectory().."/laning/vision/recovery");
local M={};
local function fail(s,where,err)
    B.Emit(s,"helper_error",{where=where,error=tostring(err):sub(1,180)});
    if s then s.error_until=(U.Now() or 0)+2 end;
end;
local function enabled(s) return C.enabled==true and s and U.Now()>=(s.error_until or -math.huge) end;
local function tick(bot,s)
    B.Poll(bot,s);Ward.Poll(bot,s);VisionDiagnostics.Tick(bot,s);Phase.Poll(bot,s);
    if not enabled(s) then return not B.Free(s) end;
    if Threat.Tick(bot,s) then Phase.Leave(bot,"emergency_bkb");return true end;
    if Q.Tick(bot,s) then Phase.Leave(bot,"requiem_control");return true end;
    if Phase.Holds(bot,s) then return true end;
    if not B.Free(s) then return true end;
    if Resources.Emergency(bot,s) then return true end;
    if Finisher.Tick(bot,s) then return true end;
    if Items.Tick(bot,s) then return true end;
    return not B.Free(s);
end;
local function prepare(bot,s,ability)
    if not enabled(s) or not B.Free(s) or Phase.Holds(bot,s) then return false end;
    local ok,ready=pcall(PT.Before,bot,s,ability);
    if not ok then fail(s,"prepare",ready);return false end;
    return ready and B.Free(s);
end;
function M.BindLegacy(env)
    if type(env)~="table" then return false,"script_environment_required" end;
    if type(env.GetBot)~="function" then return false,"bot_api_missing" end;
    local profileOK,profile=pcall(require,GetScriptDirectory().."/laning/profile");
    if not profileOK or type(profile)~="table" then return false,"profile_unknown" end;
    if profile.runtime_enabled==true then return false,"diagnostic_runtime_disabled" end;
    if env.MIDBOT_TACTICAL_BOUND then return true,"already_bound" end;
    local required={"AbilityUsageThink","ItemUsageThink","ConsiderRequiem","ConsiderRazeOnHero","ConsiderFeastOfSouls","ConsiderRazeOnCreeps","CastRaze"};
    local old={};for _,name in ipairs(required) do if type(env[name])~="function" then return false,"callback_contract_missing:"..name end;old[name]=env[name] end;
    local ok,observer=pcall(require,GetScriptDirectory().."/laning/observer/entry");
    if not ok or type(observer)~="table" or type(observer.Action)~="function" or type(observer.AfterAbilities)~="function" then return false,"observer_contract_missing" end;
    local oldAction,oldAfter=observer.Action,observer.AfterAbilities;
    -- Notifications originate in the existing TrackedCast after its API call.
    observer.Action=function(bot,kind,a,location,reason)
        local s=B.State(bot);
        if C.enabled and s and U.Actor(bot) then
            B.Mark(s);
            if kind=="cast" then
                PT.NoteCast(s,a);
                if U.Call(a,"GetName")=="nevermore_requiem" and s.requiem_selection and s.requiem_selection.at==U.Now() then
                    Q.Submitted(bot,s,a,s.requiem_selection);
                end;
            end;
        end;
        return oldAction(bot,kind,a,location,reason);
    end;
    observer.AfterAbilities=function(bot)
        if not C.enabled or not C.wards then return oldAfter(bot) end;
        local s=B.State(bot);if not enabled(s) or not U.Actor(bot) or not B.Free(s) then return end;
        local success,err=pcall(Ward.Tick,bot,s);if not success then fail(s,"wards",err) end;
    end;
    local function select(name,abilityName,index)
        env[name]=function(bot,...)
            if not C.enabled then return old[name](bot,...) end;
            local s=B.State(bot);if not U.Actor(bot) then return 0 end;
            if not enabled(s) then return old[name](bot,...) end;
            if not B.Free(s) then return 0 end;
            local a;
            local result={old[name](bot,...)};
            if name=="ConsiderRazeOnHero" then
                local success,desire,location,ability=pcall(Trades.Consider,bot,s);
                if success and desire and desire>(result[1] or 0) then result={desire,location,ability} end;
            end;
            if type(result[1])=="number" and result[1]>0 then
                if index then a=result[index] else a=U.Call(bot,"GetAbilityByName",abilityName) end;
                if not a or not prepare(bot,s,a) then return 0 end;
            end;
            return unpack(result);
        end;
    end;
    select("ConsiderRazeOnHero",nil,3);select("ConsiderRazeOnCreeps",nil,3);
    select("ConsiderFeastOfSouls","nevermore_frenzy");
    env.ConsiderRequiem=function(bot)
        if not C.enabled then return old.ConsiderRequiem(bot) end;
        local s=B.State(bot);if not enabled(s) or not B.Free(s) then return 0 end;
        local success,desire,target,selection=pcall(Q.Consider,bot,s);
        if not success then fail(s,"requiem_consider",desire);return 0 end;
        if desire>0 and prepare(bot,s,selection.ability) then selection.at=U.Now();s.requiem_selection=selection;return desire,target end;
        return 0;
    end;
    -- Direct calls from the old body get the same PT/frame guard.
    env.CastRaze=function(bot,a,location)
        if not C.enabled then return old.CastRaze(bot,a,location) end;
        local s=B.State(bot);if not U.Actor(bot) then return end;
        if not enabled(s) then return old.CastRaze(bot,a,location) end;
        if not B.Free(s) or not prepare(bot,s,a) then return end;
        return old.CastRaze(bot,a,location);
    end;
    env.AbilityUsageThink=function()
        if not C.enabled then return old.AbilityUsageThink() end;
        local bot=env.GetBot();local s=B.State(bot);
        if not U.Actor(bot) then return end;
        local sampled,sampleError=pcall(Delivery.Observe,bot,s);if not sampled then fail(s,"courier_observer",sampleError) end;
        local checked,err=pcall(Recovery.Poll,bot,s);if not checked then fail(s,"ward_recovery",err) end;
        -- Keep observation of death, but do not issue dead-hero orders.
        if U.Call(bot,"IsAlive")~=true then pcall(observer.Tick,bot);return end;
        if not s then return old.AbilityUsageThink() end;
        local success,handled=pcall(tick,bot,s);if not success then fail(s,"tick",handled) end;
        if handled==true or not B.Free(s) then
            -- A ward lease must not pause the read-only observer.
            if s.vision_phase then pcall(observer.Tick,bot) end;
            return;
        end;
        if enabled(s) then
            local valid,plan=pcall(Neutral.Consider,bot);
            if valid and plan then
                if not prepare(bot,s,plan.ability) then return end;
                B.Emit(s,"neutral_decision",{reason=plan.reason,count=plan.count,kills=plan.kills,reserve=plan.reserve});
                local executed,result=pcall(Neutral.Execute,bot,s,plan);
                if not executed then fail(s,"neutral_execute",result)
                elseif result then
                    if s.pending[U.Call(plan.ability,"GetName")] then PT.NoteCast(s,plan.ability) end;
                    return;
                end;
            elseif not valid then fail(s,"neutrals",plan) end;
        end;
        local result=old.AbilityUsageThink();
        if enabled(s) and B.Free(s) then pcall(Sentry.Restore,bot,s) end;
        -- PT is leftover work: casts/turning/wards already had the order budget.
        if enabled(s) and B.Free(s) and not s.ward_pending and not Phase.Holds(bot,s) then
            local maintained,ptError=pcall(PT.Tick,bot,s);if not maintained then fail(s,"pt_maintenance",ptError) end;
        end;
        return result;
    end;
    env.ItemUsageThink=function()
        if not C.enabled then return old.ItemUsageThink() end;
        local bot=env.GetBot();local s=B.State(bot);
        if not U.Actor(bot) or not s or U.Call(bot,"IsAlive")~=true then return end;
        local success,handled=pcall(tick,bot,s);if not success then fail(s,"item_tick",handled) end;
        if handled==true or not B.Free(s) or s.ward_pending then return end;
        -- Do not let the legacy regen branch bypass a declined tactical safety gate.
        -- Existing bottle/wand/flask support is in tactical/items; disabled mode
        -- delegates the original whole callback unchanged.
        if not enabled(s) then return old.ItemUsageThink() end;
    end;
    if type(env.AbilityLevelUpThink)=="function" then local level=env.AbilityLevelUpThink;
        env.AbilityLevelUpThink=function() if not C.enabled or U.Actor(env.GetBot()) then return level() end end;
    end;
    env.MIDBOT_TACTICAL_BOUND={version=C.version,originals=old};
    return true,"bound";
end;
return M;
