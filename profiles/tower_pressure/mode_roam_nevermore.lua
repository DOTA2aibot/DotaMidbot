local P=require(GetScriptDirectory().."/laning/pressure/entry");
function GetDesire() return P.GetDesire(GetBot()) end;
function OnStart() local ok,err=pcall(P.Start,GetBot());if not ok then P.Fail(GetBot(),"pressure_start",err) end end;
function Think() local ok,err=pcall(P.Think,GetBot());if not ok then P.Fail(GetBot(),"pressure_think",err) end end;
function OnEnd() P.Leave(GetBot(),"mode_ended") end;
