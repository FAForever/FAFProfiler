FAFProfiler for sim. Outputs the collected information to the log.
It is recommended to configure the log file(Example: /log log.txt).
Only one profiler is running at a time.
To disable profiler, call same function again.

Warning: GetSystemTimeSecondsOnlyForProfileUse
    loses its accuracy over time after the application is launched.
    Measurements should be taken as early as possible.

FuncProfilerToggle()
    Collects information about the called functions.

ThreadProfilerToggle()
    Collects information about Fork and Kill points, functions called by the engine, root functions of threads.

LineProfilerToggle()
    Collects information about each executed line.

TablesProfiler()
    Recursively counts the number of values in unique(the first reference is considered unique) tables(first for __modules then for _G).

TableProfiler(Table)
    Recursively counts the number of values in unique(to which there is a single reference) nested tables.

BreakpointToggle(BPs, PassCnt, Callback)
    Sets breakpoint. When reached calls a callback.
    
    BPs is {[Environment] = LineNum, ...}
    PassCnt is number callback calls(default 1, 0 is infinity)
    Callback is function without input params(default PrintBPInfo)
    
Example:
    SimLua BreakpointToggle({[import('/lua/sim/score.lua')] = 168}, 1, DoCallback)
    
PrintBPInfo(level)
    Used as a callback for a breakpoint. Prints caller info, locals and upvalues.