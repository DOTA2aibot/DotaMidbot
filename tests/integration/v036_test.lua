local count=0;
local function eq(a,b) assert(a==b,tostring(a).." ~= "..tostring(b)) end;
local function test(name,fn) fn();count=count+1;print("PASS V036 "..name) end;
test("fresh rune order retains ownership and re-issues a pickup the engine lost",function()
    local s=ECON_CASE();s.time=370;s.mode=7;s.visible=false;
    s.bot.Action_PickUpRune=function(_,r) s.runes[#s.runes+1]=r;s.action=1 end;
    s.rune_policy.Think(s.bot);eq(#s.runes,1);
    -- T026 (матч 9082418779): движок терял приказ (3с IDLE до конца grace,
    -- затем отмена) — теперь перевыдаём раз в секунду вместо отмены.
    s.time=370.13;s.rune_policy.Think(s.bot);eq(s.rune_policy.GetDesire(s.bot),.85);eq(#s.runes,1); -- throttle 1с
    s.time=371.2;s.rune_policy.Think(s.bot);eq(#s.runes,2); -- перевыдача
    s.action=8;s.rune_policy.Think(s.bot);eq(#s.runes,2); -- движок начал pickup — не трогаем
end);
test("real source footer activates tactical callbacks",function()
    local s=TACTICAL_SCENARIO();eq(s:bind(),true);assert(s.env.MIDBOT_TACTICAL_BOUND);
end);
test("safe moving ward uses tactical cliff quality and is confirmed",function()
    local s=TACTICAL_SCENARIO();s.action=1;s:item("item_ward_observer",0);local w=s:mod("wards");
    local p=w.Plan(s.bot);assert(p);eq(p.height,3);assert(p.rune_location);
    eq(w.Tick(s.bot,s.state),true);eq(s.orders[1].ward_kind,"observer");s:advance();w.Poll(s.bot,s.state);eq(s.state.ward_pending,nil);
end);
test("ward cannot interrupt rune, combat, retreat or evasion modes",function()
    for _,mode in ipairs({2,4,7,19}) do
        local s=TACTICAL_SCENARIO();s.mode=mode;s.action=1;s:item("item_ward_observer",0);
        local p,why=s:mod("wards").Plan(s.bot);eq(p,nil);eq(why,"ward_preserve_priority_mode");eq(#s.orders,0);
    end;
end);
test("ward still preserves native attacks and unknown actions",function()
    for _,action in ipairs({3,99}) do local s=TACTICAL_SCENARIO();s.action=action;s:item("item_ward_observer",0);eq(s:mod("wards").Plan(s.bot),nil) end;
end);
local function realObserver(s)
    local original=s.env.require;local actual;
    s.env.require=function(path)
        if path:match("laning/.*")=="laning/observer/entry" then
            if not actual then local f=assert(loadfile("laning/observer/entry.lua"));setfenv(f,s.env);actual=f() end;
            return actual;
        end;
        return original(path);
    end;
end;
test("actual observer Action records own requiem and permits controlled cancellation",function()
    local s=TACTICAL_SCENARIO();realObserver(s);
    local e=s.unit("npc_dota_hero_lina",3,400,0);e.hp=300;s.heroes={e};s:bind();s.env.AbilityUsageThink();
    eq(s.orders[1].ability,"nevermore_requiem");assert(s.state.requiem);
    e.x=1400;s:advance(.2);s.env.AbilityUsageThink();s:advance(.2);s.env.AbilityUsageThink();
    eq(s.orders[2].kind,"clear");eq(#s.orders,2);
    assert(not table.concat(s.logs):find("[MIDBOT ability ERROR]",1,true));
end);
test("actual observer AfterAbilities uses only tactical high-cliff ward executor",function()
    local s=TACTICAL_SCENARIO();realObserver(s);s:item("item_ward_observer",0);s.action=1;s:bind();s.env.AbilityUsageThink();
    eq(#s.orders,1);eq(s.orders[1].kind,"ward");eq(s.orders[1].ward_kind,"observer");
    assert(s.env.GetHeightLevel(s.orders[1].location)>=3);
    s.env.ItemUsageThink();eq(#s.orders,1);s:advance();s.env.AbilityUsageThink();
    assert(table.concat(s.logs):find("ward_placement_observed",1,true));
end);
test("diagnostic runtime cannot activate tactical controller",function()
    local s=TACTICAL_SCENARIO();local profile=s.env.require("bots/laning/profile");profile.runtime_enabled=true;
    local ok,why=s:bind();eq(ok,false);eq(why,"diagnostic_runtime_disabled");eq(s.env.MIDBOT_TACTICAL_BOUND,nil);
end);
local function courierScenario()
    local s=ECON_CASE();s.items[9]=s:item("item_branches");s.courierCalls=0;
    local courier={GetPlayerID=function() return 7 end,GetItemInSlot=function() return nil end};
    s.couriers={courier};s.env.COURIER_ACTION_TAKE_AND_TRANSFER_ITEMS=6;
    s.env.COURIER_STATE_IDLE=0;s.env.COURIER_STATE_AT_BASE=1;
    s.bot.ActionImmediate_Courier=function(_,c,action)
        eq(c,courier);eq(action,6);s.courierCalls=s.courierCalls+1;return s.accepted;
    end;
    return s,courier;
end;
test("global courier state works with mana purchases and local logger",function()
    local s,c=courierScenario();s.env.GetCourierState=function(unit) eq(unit,c);return 0 end;
    c.GetCourierState=function() error("global binding must be preferred") end;
    s:load("item_purchase_nevermore.lua");s.env.ItemPurchaseThink();eq(s.courierCalls,1);eq(s.calls[1],"item_clarity");
    assert(table.concat(s.logs,"\n"):find("take_and_transfer submitted",1,true));
    s.time=s.time+1;s.env.ItemPurchaseThink();eq(s.courierCalls,1);
end);
test("courier method remains a fallback when global API is absent",function()
    local s,c=courierScenario();c.GetCourierState=function() return 1 end;
    s:load("item_purchase_nevermore.lua");s.env.ItemPurchaseThink();eq(s.courierCalls,1);
end);
test("missing or throwing courier state API does not stop purchases",function()
    for _,throws in ipairs({false,true}) do
        local s=courierScenario();
        if throws then s.env.GetCourierState=function() error("unavailable binding") end end;
        s:load("item_purchase_nevermore.lua");s.env.ItemPurchaseThink();eq(s.courierCalls,0);eq(#s.calls,1);
        assert(table.concat(s.logs,"\n"):find("state_unavailable",1,true));
    end;
end);
test("busy or unknown courier state and missing enums never submit delivery",function()
    for _,variant in ipairs({"busy","unknown","enums"}) do
        local s=courierScenario();s.env.GetCourierState=function()
            if variant=="unknown" then return nil end;
            if variant=="enums" then return 0 end;return 99;
        end;
        if variant=="enums" then s.env.COURIER_STATE_IDLE=nil;s.env.COURIER_STATE_AT_BASE=nil end;
        s:load("item_purchase_nevermore.lua");s.env.ItemPurchaseThink();eq(s.courierCalls,0);eq(#s.calls,1);
    end;
end);
test("false courier submission is not logged as a delivery",function()
    local s=courierScenario();s.accepted=false;s.env.GetCourierState=function() return 0 end;
    s:load("item_purchase_nevermore.lua");s.env.ItemPurchaseThink();eq(s.courierCalls,1);
    local logs=table.concat(s.logs,"\n");assert(logs:find("send_failed",1,true));
    assert(not logs:find("take_and_transfer submitted",1,true));
end);
test("illusion non-SF and unknown identity cannot buy mana or request runes",function()
    for _,variant in ipairs({"illusion","nonhero","otherhero","unknown"}) do
        local s=ECON_CASE();s.time=370;s.mode=7;
        if variant=="illusion" then s.bot.IsIllusion=function() return true end
        elseif variant=="nonhero" then s.bot.IsHero=function() return false end
        elseif variant=="otherhero" then s.bot.GetUnitName=function() return "npc_dota_hero_lina" end
        else s.bot.IsIllusion=nil end;
        s:load("item_purchase_nevermore.lua");s.env.ItemPurchaseThink();
        eq(s.mana_policy.TryPurchase(s.bot),false);eq(s.rune_policy.GetDesire(s.bot),0);
        s.rune_policy.Think(s.bot);eq(#s.calls,0);eq(#s.runes,0);
    end;
end);
test("actual observer ignores illusions without snapshots or ward orders",function()
    local s=TACTICAL_SCENARIO();realObserver(s);s.bot.IsIllusion=function() return true end;
    local observer=s.env.require("bots/laning/observer/entry");
    local before=#s.logs;observer.Tick(s.bot);observer.AfterAbilities(s.bot);
    eq(#s.logs,before);eq(#s.orders,0);eq(observer.ItemsBusy(s.bot),true);
end);
print("V036 INTEGRATION PASSED "..count.." cases (mock API; live Dota not verified)");
