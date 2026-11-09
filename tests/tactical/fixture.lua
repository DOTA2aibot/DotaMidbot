-- Synthetic Bot API, deliberately no engine/path/vision-success claim.
local function scenario()
    local s={time=100,orders={},logs={},heroes={},creeps={},neutrals={},towers={},items={},wards={},trees={},linear={},mana=500,hp=1000,level=7,mode=1,action=0,recent=100};
    local env=setmetatable({}, {__index=_G});env._G=env;s.env=env;local cache={};
    env.DotaTime=function() return s.time end;env.GameTime=env.DotaTime;env.RealTime=env.DotaTime;
    env.GetScriptDirectory=function() return "bots" end;
    env.Vector=function(x,y,z) return {x=x,y=y,z=z or 0} end;
    env.BOT_MODE_NONE=0;env.BOT_MODE_LANING=1;env.BOT_MODE_ATTACK=2;env.BOT_MODE_RETREAT=4;env.BOT_MODE_FARM=5;
    env.BOT_ACTION_TYPE_MOVE_TO=1;env.BOT_MODE_RUNE=7;env.BOT_MODE_EVASIVE_MANEUVERS=19;
    env.BOT_ACTION_TYPE_IDLE=0;env.BOT_ACTION_TYPE_NONE=-1;env.BOT_ACTION_TYPE_ATTACK=3;
    env.BOT_ACTION_DESIRE_NONE=0;env.BOT_ACTION_DESIRE_MODERATE=.5;env.BOT_ACTION_DESIRE_HIGH=.75;env.BOT_ACTION_DESIRE_VERYHIGH=.9;
    env.ABILITY_BEHAVIOR_UNIT_TARGET=8;env.ABILITY_BEHAVIOR_NO_TARGET=4;env.DOTA_ABILITY_BEHAVIOR_NO_TARGET=4;
    env.ATTRIBUTE_STRENGTH=0;env.ATTRIBUTE_AGILITY=1;env.ATTRIBUTE_INTELLECT=2;
    env.DAMAGE_TYPE_MAGICAL=2;env.DAMAGE_TYPE_PHYSICAL=1;env.TEAM_NEUTRAL=4;env.DOTA_TEAM_NEUTRALS=4;
    env.UNIT_LIST_ALLIED_WARDS=4;env.LANE_MID=2;env.RUNE_POWERUP_1=0;env.RUNE_POWERUP_2=1;
    env.print=function(line) if s.logger_error then error("logger unavailable") end;s.logs[#s.logs+1]=line end;
    env.GetLinearProjectiles=function() return s.linear end;
    env.GetUnitList=function() return s.wards end;
    env.GetAllTrees=function() local a={};for i in ipairs(s.trees) do a[#a+1]=i end;return a end;
    env.GetTreeLocation=function(i) return s.trees[i] end;
    env.GetLocationAlongLane=function(_,v) return {x=(v-.5)*10000,y=0} end;
    env.GetRuneSpawnLocation=function(id) return {x=0,y=id==0 and 1000 or -1000} end;
    env.GetHeightLevel=function(p)
        if s.height_fn then return s.height_fn(p) end;
        if math.abs(p.y)>200 then return 3 end;
        if math.abs(p.x)<100 and math.abs(p.y)<100 then return 1 end;return 2;
    end;
    env.IsLocationPassable=function(p) return math.abs(p.y)<200 end; -- cliffs are intentionally not walkable
    env.IsLocationVisible=function() return s.location_visible~=false end;
    env.GetUnitToLocationDistance=function(bot,p) local q=bot:GetLocation();return math.sqrt((q.x-p.x)^2+(q.y-p.y)^2) end;
    env.GetUnitToUnitDistance=function(a,b) return env.GetUnitToLocationDistance(a,b:GetLocation()) end;
    env.IsPlayerBot=function() return true end;env.GetHeroKills=function() return 0 end;env.GetHeroDeaths=function() return 0 end;
    local function unit(name,team,x,y)
        local u={name=name,team=team,x=x or 0,y=y or 0,hp=500,maxhp=1000,visible=true,illusion=false,id=8,modifiers={}};
        function u:GetLocation() return {x=self.x,y=self.y,z=0} end;
        function u:GetUnitName() return self.name end;function u:GetTeam() return self.team end;
        function u:IsNull() return false end;function u:IsAlive() return self.hp>0 end;
        function u:CanBeSeen() return self.visible end;function u:IsHero() return self.name:find("npc_dota_hero_",1,true)==1 end;
        function u:IsIllusion() return self.illusion end;function u:IsInvulnerable() return false end;
        function u:IsMagicImmune() return false end;function u:IsAttackImmune() return false end;
        function u:GetPlayerID() return self.id end;function u:GetHealth() return self.hp end;function u:GetMaxHealth() return self.maxhp end;
        function u:GetExtrapolatedLocation(t) return {x=self.x+(self.vx or 0)*t,y=self.y+(self.vy or 0)*t} end;
        function u:HasModifier(m) return self.modifiers[m] or false end;
        function u:GetActualIncomingDamage(raw,_) return raw*(self.magic_factor or 1) end;
        function u:GetCurrentActiveAbility() return self.active end;function u:GetTarget() return self.target end;
        function u:GetAttackRange() return self.range or 150 end;
        function u:GetModifierByName() return -1 end;function u:GetModifierStackCount() return 0 end;
        function u:GetCurrentVisionRange() return 1600 end;
        return u;
    end;
    s.unit=unit;local bot=unit("npc_dota_hero_nevermore",2,0,0);bot.id=7;s.bot=bot;
    function bot:GetHealth() return s.hp end;function bot:GetMaxHealth() return 1000 end;
    function bot:IsAlive() return s.hp>0 end;
    function bot:GetMana() return s.mana end;function bot:GetMaxMana() return s.maxmana or 800 end;
    function bot:GetLevel() return s.level end;function bot:GetAbilityPoints() return 0 end;
    function bot:GetActiveMode() return s.mode end;function bot:GetCurrentActionType() return s.action end;
    function bot:GetNearbyHeroes(radius,enemy,_)
        if s.enemies_unknown then return nil end;
        local out={};if enemy then for _,e in ipairs(s.heroes) do if env.GetUnitToUnitDistance(self,e)<=radius and e.visible and e.hp>0 then out[#out+1]=e end end end;return out;
    end;
    function bot:GetNearbyLaneCreeps() return s.creeps end;function bot:GetNearbyNeutralCreeps() return s.neutrals end;
    function bot:GetNearbyTowers(_,enemy) return enemy==false and {} or s.towers end;
    function bot:IsUsingAbility() return s.using or false end;function bot:IsChanneling() return s.channel or false end;
    function bot:IsStunned() return s.stunned or false end;function bot:IsHexed() return false end;
    function bot:IsMuted() return false end;function bot:IsSilenced() return false end;
    function bot:NumQueuedActions() return s.queued or 0 end;
    function bot:GetCurrentActiveAbility() return s.active end;
    function bot:GetAttackTarget() return s.attack end;
    function bot:TimeSinceDamagedByAnyHero() return s.recent end;
    function bot:WasRecentlyDamagedByAnyHero(t) return s.recent<=t end;
    function bot:WasRecentlyDamagedByHero(_,t) return s.recent<=t end;
    function bot:GetIncomingTrackingProjectiles() return s.projectiles or {} end;
    function bot:GetAttackDamage() return 100 end;function bot:GetAttackRange() return 525 end;
    function bot:GetFacing() return 0 end;function bot:IsFacingLocation() return true end;
    function bot:GetItemInSlot(slot) return s.items[slot] end;
    function bot:FindItemSlot(name) for i=0,14 do if s.items[i] and s.items[i].name==name then return i end end;return -1 end;
    s.abilities={};
    function s:ability(name,opts)
        opts=opts or {};local a={name=name,level=opts.level or 1,cost=opts.cost or 75,cd=0,phase=false,special=opts.special or {},castpoint=1.7};
        function a:GetName() return self.name end;function a:GetLevel() return self.level end;
        function a:GetManaCost() return self.cost end;function a:GetCooldownTimeRemaining() return self.cd end;
        function a:IsFullyCastable() return self.level>0 and self.cd<=0 and s.mana>=self.cost end;
        function a:IsInAbilityPhase() return self.phase end;function a:IsHidden() return false end;
        function a:GetCastPoint() return self.castpoint end;function a:GetBehavior() return 4 end;
        function a:GetAbilityDamage() return self.damage or 200 end;function a:GetDamageType() return 2 end;
        function a:GetSpecialValueFloat(k) return self.special[k] or 0 end;a.GetSpecialValueInt=a.GetSpecialValueFloat;
        function a:CanAbilityBeUpgraded() return false end;function a:GetMaxLevel() return 4 end;
        function a:GetCastRange() return self.range or 700 end;
        function a:GetCaster() return self.caster or bot end;
        s.abilities[name]=a;return a;
    end;
    for i,r in ipairs({200,450,700}) do s:ability("nevermore_shadowraze"..i,{special={shadowraze_range=r,shadowraze_radius=250}}) end;
    s:ability("nevermore_frenzy",{cost=70});s:ability("nevermore_requiem",{cost=150,special={requiem_radius=1000}});
    function bot:GetAbilityByName(name) return s.abilities[name] end;
    function bot:GetAbilityInSlot(n) return s.abilities[({"nevermore_shadowraze1","nevermore_shadowraze2","nevermore_shadowraze3","nevermore_frenzy","nevermore_requiem"})[n+1]] end;
    function bot:Action_UseAbility(a)
        s.orders[#s.orders+1]={kind="self",ability=a.name};
        if a.name=="item_power_treads" then if not s.pt_stuck then a.stat=({[0]=2,[2]=1,[1]=0})[a.stat] end
        elseif a.name=="item_ward_dispenser" then a.toggle=not a.toggle
        elseif a.name:find("item_",1,true)==1 then a.charges=math.max(0,a.charges-1);a.cd=10
        else s.active=a;s.using=true;a.phase=true end;
        if s.action_throw then error("unknown after order") end;
    end;
    function bot:Action_UseAbilityOnEntity(a,target)
        assert(target==bot);s.orders[#s.orders+1]={kind="entity",ability=a.name};a.charges=math.max(0,a.charges-1);a.cd=10;
        if s.action_throw then error("unknown after order") end;
    end;
    function bot:Action_ClearActions(stop)
        assert(stop==true);s.orders[#s.orders+1]={kind="clear"};if s.active then s.active.phase=false end;s.using=false;s.active=nil;
    end;
    function bot:Action_UseAbilityOnLocation(a,p)
        local k=a.name=="item_ward_observer" and "observer" or a.name=="item_ward_sentry" and "sentry" or (a.toggle and "observer" or "sentry");
        s.orders[#s.orders+1]={kind="ward",ward_kind=k,location=p};
        if k=="observer" then a.charges=a.charges-1 else if a.name=="item_ward_dispenser" then a.secondary=a.secondary-1 else a.charges=a.charges-1 end end;
        local w=unit(k=="observer" and "npc_dota_observer_wards" or "npc_dota_sentry_wards",bot:GetTeam(),p.x,p.y);w.id=7;s.wards[#s.wards+1]=w;
    end;
    function bot:Action_MoveDirectly(p) s.orders[#s.orders+1]={kind="face",location=p} end;bot.Action_MoveToLocation=bot.Action_MoveDirectly;
    env.GetBot=function() return bot end;
    s.observer={Tick=function() s.observed=(s.observed or 0)+1 end,BeforeAction=function() end,
        Action=function() s.legacy_actions=(s.legacy_actions or 0)+1 end,
        AfterAbilities=function() s.old_wards=(s.old_wards or 0)+1 end};
    env.require=function(path)
        local p=assert(path:match("laning/.*"));
        if p=="laning/observer/entry" then if s.observer_missing then error("observer missing") end;return s.observer end;
        if p=="laning/runtime/guard" then return {AbilityGate=function() return false end} end;
        if not cache[p] then local f=assert(loadfile(p..".lua"));setfenv(f,env);cache[p]=f() end;return cache[p];
    end;
    function s:mod(name) return env.require("bots/laning/tactical/"..name) end;
    s.config=s:mod("config");s.broker=s:mod("broker");s.state=s.broker.State(bot);
    function s:item(name,slot,opts)
        opts=opts or {};local item={name=name,charges=opts.charges or 1,secondary=opts.secondary or 0,cd=0,stat=opts.stat or 1,
            toggle=opts.toggle==true,behavior=opts.behavior or 4,special=opts.special or {},range=opts.range or 500};
        function item:GetName() return self.name end;function item:GetCurrentCharges() return self.charges end;
        function item:GetSecondaryCharges() return self.secondary end;function item:GetBehavior() return self.behavior end;
        function item:GetCooldownTimeRemaining() return self.cd end;function item:IsFullyCastable() return self.cd<=0 end;
        -- stat stays a semantic hero attribute in tests; API returns the separate raw PT code.
        function item:IsHidden() return false end;function item:GetPowerTreadsStat() return ({[0]=0,[1]=2,[2]=1})[self.stat] end;
        function item:GetToggleState() return self.toggle end;function item:GetCastRange() return self.range end;
        function item:GetSpecialValueFloat(k) return self.special[k] or 0 end;item.GetSpecialValueInt=item.GetSpecialValueFloat;
        s.items[slot or 0]=item;return item;
    end;
    function s:advance(dt) self.time=self.time+(dt or .1);self.state=self.broker.State(self.bot) end;
    function s:release(a) a.phase=false;a.cd=10;self.using=false;self.active=nil end;
    function s:bind()
        local f=assert(loadfile(CURRENT_OWNER_SOURCE or "tests/tactical/fixtures/ability_pr43_f605944.lua"));setfenv(f,env);f();
        -- Existing decisions are not the subject of synthetic lane fixtures.
        env.ConsiderRazeOnHero=function() return 0 end;env.ConsiderRazeOnCreeps=function() return 0 end;env.ConsiderFeastOfSouls=function() return 0 end;
        return self:mod("entry").BindLegacy(env);
    end;
    return s;
end;
return scenario;
