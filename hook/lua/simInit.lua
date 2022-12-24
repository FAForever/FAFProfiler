local baseSetupSession = SetupSession
function SetupSession()
    WARN('FAFProfiler: To activate Sim Profiler press:')
    WARN('FAFProfiler: Functions Profiler - Ctrl-P')
    SimConExecute('IN_BindKey Ctrl-P SimLua FuncProfilerToggle()')
    WARN('FAFProfiler: Threads Profiler - Ctrl-O')
    SimConExecute('IN_BindKey Ctrl-O SimLua ThreadProfilerToggle()')
    WARN('FAFProfiler: Tables Profiler - Ctrl-I')
    SimConExecute('IN_BindKey Ctrl-I SimLua TablesProfiler()')
    WARN('FAFProfiler: Lines Profiler - Ctrl-U')
    SimConExecute('IN_BindKey Ctrl-U SimLua LineProfilerToggle()')
    baseSetupSession()
end