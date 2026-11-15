-- Prevent the native watcher objective BEFORE it starts.
-- Cancellation from ability think cannot lower its native desire and caused a loop.
function GetDesire() return 0 end;
function OnStart() end;
function Think() end;
function OnEnd() end;
