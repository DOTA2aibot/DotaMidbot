# Read-only воспроизведения для code review

Запуск выполнен Artem (GPT) с Lupa Lua5.1 на неизменённых файлах PR53 head0dc2e60
в локальном combined source v0.3.12. Результаты: review-repro-results.json.
Это не новый clientrun и не исправление; причина неправильного client pickup
здесь не моделируется. Установленная игра не затрагивается.

Из checkout с указанным PR53 (или combined source), где доступны tests/economy
и Lupa, Python:

```python
from pathlib import Path
from lupa.lua51 import LuaRuntime
lua = LuaRuntime(unpack_returned_tuples=True)
lua.globals().print = lambda *args: None
lua.globals().CASE = lua.execute(Path('tests/economy/economy_test.lua').read_text(encoding='utf-8'))
```

Затем выполнить следующий Lua snippet через lua.execute и вывести результат.
Fixture сама исполняет исходные36 economy cases при загрузке; они не являются
новыми regression tests и не доказывают client API behavior.

```lua
local out={};
local function case()
    local s=CASE();s.time=130;s.mode=7;s.items[0]=s:item("item_bottle",0);
    s.env.GetRuneStatus=function(r) return r==0 and 1 or 2 end;
    return s;
end;
for _,path in ipairs({"Decide","Think"}) do
    local s=case();s.rune_policy.Think(s.bot);s.rune_policy.Think(s.bot);
    -- Fixture starts PICK_UP_RUNE but gives no resources.
    s.action=2;s.time=131; -- interrupted by movement, target is still AVAILABLE
    local reason;
    if path=="Decide" then local plan;plan,reason=s.rune_policy.Decide(s.bot)
    else s.rune_policy.Think(s.bot);reason="rune_done="..tostring(table.concat(s.logs,"\n"):find('rune_done',1,true)~=nil) end;
    s.rune_policy.Leave(s.bot,"test_interruption");s.time=142;
    local plan,after=s.rune_policy.Decide(s.bot);
    out[#out+1]=path..": "..tostring(reason)..", AVAILABLE="..s.env.GetRuneStatus(0)
        ..", bottle="..s.items[0]:GetCurrentCharges()..", next="..tostring(plan and plan.rune)..", "..tostring(after);
end;
local s=case();s.bot.Action_PickUpRune=function() end;
s.rune_policy.Think(s.bot);s.time=146;s.rune_policy.GetDesire(s.bot);
s.rune_policy.Leave(s.bot,"rune_pickup_timeout");s.time=157;
local plan,why=s.rune_policy.Decide(s.bot);
out[#out+1]="retry_after_failure: next="..tostring(plan and plan.rune)..", "..tostring(why);
return table.concat(out,"\n");
```

Фактический результат обеих первых веток: AVAILABLE1, bottle0, next=nil,
already_resolved:d=400. Ветка Think успела записать rune_done=true.
Третья ветка: в том же spawn cycle снова next=0/bottle_empty_rune_run.
Это демонстрирует два независимых book-keeping края, а не число/тип реальных
водных рун и не гарантированный способ исправить клиент.
