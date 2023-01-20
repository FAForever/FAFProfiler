local Funcs = nil
local CFunc = nil
local YieldTime = nil
local EventTime = nil
local SkipEvent = false
local RunTime = nil

local Yielding = {[coroutine.yield]=true,[WaitFor]=true,[SuspendCurrentThread]=true}

local function GetFuncID(Info)
    if Info.what == 'C' then return Info.func end
    return Info.source..Info.linedefined
end

local function GetFunc(Info)
    local FuncID = GetFuncID(Info)
    local Func = Funcs[FuncID]
    if not Func then
        Func = {Cnt = 0, Time = 0, YieldTime = 0, Yield = 0, Calls = {}, Info = Info}
        Funcs[FuncID] = Func
    end
    return Func
end

local getinfo = debug.getinfo
local allocatedsize = debug.allocatedsize
local GetTimeForProfile = GetTimeForProfile

local LStateName = 'UI'
local GetGameTick
if not pcall(function() GetGameTick = GameTick end) then
    GetGameTick = _G.GetGameTick
    LStateName = 'Sim'
end

local InitTime = GetTimeForProfile(0)

local function FuncHook(Action)
    local CurTime = GetTimeForProfile(RunTime)
    if SkipEvent then
        SkipEvent = false
        return
    end
    local Info = getinfo(2, 'Sfn')
    local Func = GetFunc(Info)
    local pInfo = getinfo(3, 'Sfn')
    local pFunc = CFunc
    if pInfo then pFunc = GetFunc(pInfo) end
    if Action == 'call' then
        Func.Cnt = Func.Cnt + 1
        if CFunc and (not pInfo or pFunc == CFunc) then
            CFunc.Calls[Func] = Info
        end
        if pFunc and EventTime then
            pFunc.Time = pFunc.Time + CurTime - EventTime
        end
        if Yielding[Info.func] ~= nil then
            local Thread = CurrentThread()
            YieldTime[Thread] = GetGameTick()
            pFunc.Yield = pFunc.Yield + 1
            CurTime = nil
            CFunc = nil
        elseif Info.what == 'C' then
            CFunc = Func
        end
    elseif Yielding[Info.func] ~= nil then
        local Thread = CurrentThread()
        if YieldTime[Thread] then
            pFunc.YieldTime = pFunc.YieldTime + GetGameTick() - YieldTime[Thread]
            YieldTime[Thread] = nil
        end
        SkipEvent = true
    else
        if EventTime then
            Func.Time = Func.Time + CurTime - EventTime
        end
        if Info.what == 'C' then CFunc = nil end
        if (not pInfo) and (not CFunc) then CurTime = nil end
    end
    if CurTime then CurTime = GetTimeForProfile(RunTime) end
    EventTime = CurTime
end

function FuncProfilerToggle()
    if RunTime then
        debug.sethook()
        RunTime = GetTimeForProfile(RunTime)
        WARN(string.format('FAFProfiler: Functions Profiler - Stop (Duration: %0.1f, GameTime: %0.1f)', RunTime, GetGameTimeSeconds()))
        WARN('Functions: '..table.getsize(Funcs))
        local Keys = table.keys(Funcs, function(a,b) return Funcs[a].Time > Funcs[b].Time end)
        for i,k in Keys do
            local Func = Funcs[k]
            if Func.Info.what == 'C' then
                WARN(string.format('Time: %0.6f, Cnt: %d, What: %s', Func.Time, Func.Cnt, Func.Info.what))
                WARN('Name: '..repru(Func.Info.func, 0, 0))
                for k,v in Func.Calls do
                    if v.what == 'C' then
                        WARN('Call: '..repru(v.func, 0, 0)..', C')
                    else
                        WARN('Call: '..(v.name or '')..', '..v.linedefined..', '..v.source)
                    end
                end
            else
                WARN(string.format('Time: %0.6f, Cnt: %d, YieldTicks: %d, Yield: %d, Line: %d, What: %s', Func.Time, Func.Cnt, Func.YieldTime, Func.Yield, Func.Info.linedefined, Func.Info.what))
                if Func.Info.name then WARN('Name: '..Func.Info.name) end
                WARN(Func.Info.source)
            end
            WARN(' ')
        end
        RunTime = nil
    else
        Funcs = {}
        YieldTime = {}
        CFunc = nil
        EventTime = nil
        SkipEvent = false
        RunTime = GetTimeForProfile(0)
        WARN(string.format('FAFProfiler: '..LStateName..' Functions Profiler - Run (RealTime: %0.1f, GameTime: %0.1f)', RunTime - InitTime, GetGameTimeSeconds()))
        debug.sethook(FuncHook, 'cr')
    end
end

local TForks = nil
local TKills = nil
local TFuncs = nil
local ECalls = nil
local FSumForks = nil
local TSumKills = nil
local TSumEnds = nil
local TSuspend = nil
local TResume = nil

local function ThreadHook(Action)
    local Info = getinfo(2, 'Sfn')
    if Action == 'call' then
        local Domen = nil
        if Yielding[Info.func] ~= nil then
            if Info.func == SuspendCurrentThread then
                TSuspend = TSuspend + 1
            end
            local Depth = 4
            while true do
                Info = getinfo(Depth, 'Sn')
                if not Info then break end
                Depth = Depth + 1
            end
            Info = getinfo(Depth - 1, 'Sn')
            local Func = TFuncs[GetFuncID(Info)]
            if Func then
                if Depth > 4 then
                    Func.Yield = Func.Yield + 1
                else
                    Func.RootYield = Func.RootYield + 1
                end
            end
            return
        elseif Info.func == ForkThread then
            local Depth = 3
            while true do
                Info = getinfo(Depth, 'Sn')
                if Info.name ~= 'ForkThread' then break end
                Depth = Depth + 1
            end
            Domen = TForks
            FSumForks = FSumForks + 1
        elseif Info.func == KillThread then
            local Depth = 3
            while true do
                Info = getinfo(Depth, 'Sn')
                if Info.name ~= 'KillThread' then break end
                Depth = Depth + 1
            end
            Domen = TKills
            TSumKills = TSumKills + 1
        elseif Info.func == ResumeThread then
            TResume = TResume + 1
        elseif not getinfo(3, 'f') then
            local Status, Thread = pcall(CurrentThread)
            if Status then Domen = TFuncs else Domen = ECalls end
        else return end
        local FuncID = GetFuncID(Info)
        local Func = Domen[FuncID]
        if not Func then
            if Info.what == 'C' then
                Info.linedefined = ''
                Info.name = repru(Info.func, 0, 0)
                Info.source = 'C'
            end
            Func = {Cnt = 0, Ends = 0, RootYield = 0, Yield = 0, LineDefined = Info.linedefined, Name = Info.name or '', Source = Info.source}
            Domen[FuncID] = Func
        end
        Func.Cnt = Func.Cnt + 1
    elseif not getinfo(3, 'f') then
        local Status, Thread = pcall(CurrentThread)
        if Status then
            TSumEnds = TSumEnds + 1
            local Func = TFuncs[GetFuncID(Info)]
            if Func then Func.Ends = Func.Ends + 1 end
        end
    end
end

local function PrintFuncs(Funcs)
    WARN('CallCnt - LineDefined - FuncName - Source')
    local Keys = table.keys(Funcs, function(a,b) return Funcs[a].Cnt > Funcs[b].Cnt end)
    for i,k in Keys do
        local Func = Funcs[k]
        if i > 500 then break end
        WARN(Func.Cnt..' - '..Func.LineDefined..' - '..Func.Name..' - '..Func.Source)
    end
end

function ThreadProfilerToggle()
    if RunTime then
        debug.sethook()
        RunTime = GetTimeForProfile(RunTime)
        WARN(string.format('FAFProfiler: Threads Profiler - Stop (Duration: %0.1f, GameTime: %0.1f)', RunTime, GetGameTimeSeconds()))
        WARN('Forks: '..FSumForks..', Kills: '..TSumKills..', Ends: '..TSumEnds..', Suspend: '..TSuspend..', Resume: '..TResume)
        WARN('Fork points: '..table.getsize(TForks))
        PrintFuncs(TForks)
        WARN(' ')
        WARN('Kill points: '..table.getsize(TKills))
        PrintFuncs(TKills)
        WARN(' ')
        WARN('Thread funcs: '..table.getsize(TFuncs))
        WARN('CallCnt - Ends - Yield - LineDefined - FuncName - Source')
        local Keys = table.keys(TFuncs, function(a,b) return TFuncs[a].Cnt > TFuncs[b].Cnt end)
        for i,k in Keys do
            local Func = TFuncs[k]
            if i > 500 then break end
            WARN(Func.Cnt - Func.RootYield..' - '..Func.Ends..' - '..Func.RootYield + Func.Yield..' - '..Func.LineDefined..' - '..Func.Name..' - '..Func.Source)
        end
        WARN(' ')
        WARN('Engine calls: '..table.getsize(ECalls))
        PrintFuncs(ECalls)
        RunTime = nil
    else
        TForks = {}
        TKills = {}
        TFuncs = {}
        ECalls = {}
        FSumForks = 0
        TSumKills = 0
        TSumEnds = 0
        TSuspend = 0
        TResume = 0
        RunTime = GetTimeForProfile(0)
        WARN(string.format('FAFProfiler: '..LStateName..' Threads Profiler - Run (RealTime: %0.1f, GameTime: %0.1f)', RunTime - InitTime, GetGameTimeSeconds()))
        debug.sethook(ThreadHook, 'cr')
    end
end

local function DeepSizeVal(v, seen)
    if seen[v] then return 0, 0, 0 end
    local bytes = allocatedsize(v)
    if bytes == 0 then return 0, 0, 0 end
    local allocs, vals = 1, 0
    seen[v] = true
    local bytes2, allocs2, vals2
    local m = getmetatable(v)
    if m then
        bytes2, allocs2, vals2 = DeepSizeVal(m, seen)
        bytes, allocs, vals = bytes + bytes2, allocs + allocs2, vals + vals2
    end
    if type(v) == 'table' then
        for k, v in v do
            vals = vals + 2
            bytes2, allocs2, vals2 = DeepSizeVal(k, seen)
            bytes, allocs, vals = bytes + bytes2, allocs + allocs2, vals + vals2
            bytes2, allocs2, vals2 = DeepSizeVal(v, seen)
            bytes, allocs, vals = bytes + bytes2, allocs + allocs2, vals + vals2
        end
        vals = vals - table.getn(v)
    end
    return bytes, allocs, vals
end

function DeepSize(v, seen)
    if not v then return 0, 0, 0 end
    local size = allocatedsize(v)
    if size == 0 then return 8, 0, 1 end
    if type(v) ~= 'table' then return size, 1, 1 end
    return DeepSizeVal(v, seen or {})
end

local function TabProc(t, Seen, Tables)
    for k,v in t do
        local Bytes, Allocs, Vals = 0, 0, 0
        if (type(k) == 'table') and (not Seen[k]) then
            local Bytes2, Allocs2, Vals2 = DeepSizeVal(k, Seen)
            Bytes, Allocs, Vals = Bytes + Bytes2, Allocs + Allocs2, Vals + Vals2
        end
        if (type(v) == 'table') and (not Seen[v]) then
            local Bytes2, Allocs2, Vals2 = DeepSizeVal(v, Seen)
            Bytes, Allocs, Vals = Bytes + Bytes2, Allocs + Allocs2, Vals + Vals2
        end
        if Bytes == 0 then continue end
        Tables[v] = {Bytes = Bytes, Allocs = Allocs, Vals = Vals, Name = tostring(k)}
    end
    Seen[t] = nil
    local Bytes, Allocs, Vals = DeepSizeVal(t, Seen)
    for _,t in Tables do
        Bytes = Bytes + t.Bytes
        Allocs = Allocs + t.Allocs
        Vals = Vals + t.Vals
    end
    return Bytes, Allocs, Vals
end

local function PrintTables(Tables)
    WARN('Deep Bytes - Allocs - Values - Name')
    local Keys = table.keys(Tables, function(a,b) return Tables[a].Bytes > Tables[b].Bytes end)
    for i,k in Keys do
        local Table = Tables[k]
        if i > 1000 then break end
        WARN(Table.Bytes..' - '..Table.Allocs..' - '..Table.Vals..' - '..Table.Name)
    end
end

function TableProfiler(Table, Ignore)
    local Seen = {[Table] = true}
    for _,v in Ignore or {} do
        DeepSize(v, Seen)
    end
    Seen[Table] = nil
    local Tables = {}
    local Bytes, Allocs, Vals = TabProc(Table, Seen, Tables)
    WARN('Sum - Bytes: '..Bytes..', Allocs: '..Allocs..', Values: '..Vals)
    PrintTables(Tables)
end

function TablesProfiler()
    WARN('FAFProfiler: '..LStateName..' Tables Profiler')
    WARN('Size _G: '..table.getsize(_G)..', __modules: '..table.getsize(__modules)..', GCInfo: '..gcinfo()..'kb')
    local Seen = {[_G] = true}
    for _,m in __modules do
        Seen[m] = true
    end
    local Tables = {}
    local Bytes, Allocs, Vals = TabProc(_G, Seen, Tables)
    WARN(' ')
    WARN('Bytes: '..Bytes..', Allocs: '..Allocs..', Values: '..Vals)
    PrintTables(Tables)
    local Modules = {}
    for n,m in __modules do
        Tables = {}
        Bytes, Allocs, Vals = TabProc(m, Seen, Tables)
        table.insert(Modules, {Bytes = Bytes, Allocs = Allocs, Vals = Vals, Tables = Tables, Name = n})
    end
    Bytes, Allocs, Vals = 0, 0, 0
    for _,m in Modules do
        Bytes = Bytes + m.Bytes
        Allocs = Allocs + m.Allocs
        Vals = Vals + m.Vals
    end
    WARN(' ')
    WARN('Modules Bytes: '..Bytes..', Allocs: '..Allocs..', Values: '..Vals)
    table.sort(Modules, function(a,b) return a.Bytes > b.Bytes end)
    for i,m in Modules do
        if i > 200 then break end
        WARN(' ')
        WARN(m.Name)
        WARN('Sum - Bytes: '..m.Bytes..', Allocs: '..m.Allocs..', Values: '..m.Vals)
        PrintTables(m.Tables)
    end
end

local Lines = nil
local Line = nil
local LineTime = nil

local function LineHook(Action, LineNum)
    local CurTime = GetTimeForProfile(RunTime)
    local CurLine = nil
    if Action == 'line' then
        local Info = getinfo(2, 'Sn')
        local CurLineID = Info.source..LineNum
        CurLine = Lines[CurLineID]
        if not CurLine then
            CurLine = {Cnt = 0, Time = 0, Num = LineNum, Name = Info.name or '', Source = Info.source}
            Lines[CurLineID] = CurLine
        end
    end
    if Line then
        Line.Cnt = Line.Cnt + 1
        Line.Time = Line.Time + CurTime - LineTime
    end
    Line = CurLine
    LineTime = GetTimeForProfile(RunTime)
end

function LineProfilerToggle()
    if RunTime then
        debug.sethook()
        RunTime = GetTimeForProfile(RunTime)
        WARN(string.format('FAFProfiler: Lines Profiler - Stop (Duration: %0.1f, GameTime: %0.1f)', RunTime, GetGameTimeSeconds()))
        local SumTime = 0
        for _,l in Lines do
            SumTime = SumTime + l.Time
        end
        WARN(string.format('Found lines: %d, Sum time: %0.6f',table.getsize(Lines), SumTime))
        WARN('SumTime - CallCnt - LineNum - FuncName - Source')
        local Keys = table.keys(Lines, function(a,b) return Lines[a].Time > Lines[b].Time end)
        for i,k in Keys do
            local Line = Lines[k]
            if i > 1000 then break end
            WARN(string.format('%0.6f', Line.Time)..' - '..Line.Cnt..' - '..Line.Num..' - '..Line.Name..' - '..Line.Source)
        end
        RunTime = nil
    else
        Lines = {}
        Line = nil
        RunTime = GetTimeForProfile(0)
        WARN(string.format('FAFProfiler: '..LStateName..' Lines Profiler - Run (RealTime: %0.1f, GameTime: %0.1f)', RunTime - InitTime, GetGameTimeSeconds()))
        debug.sethook(LineHook, 'rl')
    end
end

local bBPs = nil
local bPassCnt = nil
local bCallback = nil

function PrintBPInfo(level)
    WARN(' ')
    WARN('Event Tick: '..GetGameTick())
    WARN(' ')
    WARN('--- Call Stack ---')
    WARN('+3: '..repru(getinfo(level + 3, 'Snl')))
    WARN('+2: '..repru(getinfo(level + 2, 'Snl')))
    WARN('+1: '..repru(getinfo(level + 1, 'Snl')))
    WARN('+0: '..repru(getinfo(level + 0, 'Snl')))
    local Info = getinfo(level, 'f')
    WARN(' ')
    WARN('--- Locals ---')
    local i = 1
    while true do
        local n, v = debug.getlocal(level, i)
        if not n then break end
        if type(v) == 'cfunction' then
            v = 'cfunction: '..repru(v, 0, 0)
        elseif type(v) == 'table' then
            v = tostring(v)..', Size: '..table.getsize(v)
        end
        WARN(n..': '..tostring(v))
        i = i + 1
    end
    WARN(' ')
    WARN('--- UpValues ---')
    local i = 1
    while true do
        local n, v = debug.getupvalue(Info.func, i)
        if not n then break end
        if type(v) == 'cfunction' then
            v = 'cfunction: '..repru(v, 0, 0)
        elseif type(v) == 'table' then
            v = tostring(v)..', Size: '..table.getsize(v)
        end
        WARN(n..': '..tostring(v))
        i = i + 1
    end
    WARN(' ')
end

local function BreakpointHook(Action, LineNum)
    if bBPs[getfenv(2)][LineNum] == nil then return end
    local Status, Stop = pcall(bCallback, 4)
    if not Status then
        BreakpointToggle()
        WARN(Stop)
        return
    end
    if Stop then BreakpointToggle() end
    if bPassCnt < 1 then return end
    bPassCnt = bPassCnt - 1
    if bPassCnt < 1 then BreakpointToggle() end
end

function BreakpointToggle(BPs, PassCnt, Callback)
    if RunTime then
        debug.sethook()
        WARN('FAFProfiler: Breakpoint - Stop')
        RunTime = nil
    else
        bBPs = BPs
        if table.empty(bBPs) then
            WARN('bad argument #1 (not table or empty)')
            return
        end
        bPassCnt = PassCnt or 1
        if type(bPassCnt) ~= 'number' then
            WARN('bad argument #2 (not number)')
            return
        end
        bCallback = Callback or PrintBPInfo
        if type(bCallback) ~= 'function' then
            WARN('bad argument #3 (not function)')
            return
        end
        RunTime = true
        WARN('FAFProfiler: Breakpoint - Run')
        debug.sethook(BreakpointHook, 'l')
    end
end

local bData = nil

local function CustomBPHook(Action, LineNum)
    if bCallback(bData, Action, LineNum) then
      CustomBPToggle()
    end
end

function CustomBPToggle(Callback, Data)
    if RunTime then
        debug.sethook()
        WARN('FAFProfiler: CustomBP - Stop')
        RunTime = nil
    else
        bCallback = Callback
        if type(bCallback) ~= 'function' then
            WARN('bad argument #1 (not function)')
            return
        end
        bData = Data
        RunTime = true
        WARN('FAFProfiler: CustomBP - Run')
        debug.sethook(CustomBPHook, 'l')
    end
end