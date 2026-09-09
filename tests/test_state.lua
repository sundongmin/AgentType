-- Runs with a mocked hs environment; never changes real input sources or settings.
local pluginPath = assert(arg[1])
local saved, timestamp, foreground, input = {}, 100, "com.mitchellh.ghostty", "ABC"
local tasks, timers, watchers, writes = {}, {}, {}, {}
hs = {
    settings = {get = function(k) return saved[k] end, set = function(k,v)
        local copy = {}; for key,value in pairs(v) do copy[key]=value end; saved[k]=copy
    end},
    logger = {new = function() return {w = function() end} end},
    timer = {secondsSinceEpoch = function() return timestamp end},
    application = {watcher = {activated=1, deactivated=2, terminated=3}},
    keycodes = {currentSourceID = function(value)
        if value then writes[#writes+1]=value; input=value; return true end
        return input
    end},
    osascript = {applescript = function() return true, "terminal-A" end},
    task = {},
}
function hs.application.frontmostApplication()
    return {bundleID = function() return foreground end}
end
local function stoppable(o)
    o.start=function(self) self.running=true; return self end
    o.stop=function(self) self.running=false; return self end
    return o
end
function hs.timer.doEvery(interval, callback)
    local timer=stoppable({callback=callback, interval=interval, running=true})
    timers[#timers+1]=timer; return timer
end
function hs.application.watcher.new(callback)
    local watcher=stoppable({callback=callback})
    watchers[#watchers+1]=watcher; return watcher
end
function hs.task.new(path, callback, args)
    local task=stoppable({callback=callback, args=args})
    task.isRunning=function(self) return self.running end
    task.terminate=function(self) self.running=false end
    tasks[#tasks+1]=task; return task
end
package.preload["hs.ipc"] = function() return {} end
local function new()
    local spoon=dofile(pluginPath):init()
    spoon.terminalSource, spoon.agentSource="ABC", "PINYIN"
    return spoon:start()
end
local function finish(task, output, code)
    task.running=false; task.callback(code or 0,output,"error")
end
local function poll(spoon, output)
    spoon:_poll(); assert(spoon.task,"query expected")
    finish(spoon.task,output or "terminal-A\nLIVE\nterminal-A\nterminal-B\n")
end
local count=0
local function check(value, message) assert(value,message); count=count+1 end
local s=new()
check(#timers==2 and #watchers==1,"retained background objects")
s:start(); check(#timers==2,"start is idempotent")
check(s:resolveTTY('/dev/ttys001')=='terminal-A',"TTY resolution")
check(s:resolveTTY('/dev/ttys001\" bad')==nil,"reject injected TTY")
check(not s:setState('bad"id','agent'),"reject invalid ID")
check(not s:setState('terminal-A','invalid'),"reject invalid state")
poll(s); check(s.confirmed and #writes==0,"already correct source")
s:setState('terminal-A','agent'); poll(s)
check(input=='PINYIN',"agent source")
poll(s); input='MANUAL'; poll(s)
check(input=='MANUAL',"manual change respected after confirmation")
s:setState('terminal-B','agent'); poll(s)
check(input=='MANUAL',"background state must not reset foreground rule")
s:setState('terminal-A','terminal'); poll(s)
check(input=='ABC',"agent exit restores ABC")
poll(s,'terminal-B\n'); check(input=='PINYIN',"split focus applies target state")
s:_poll(); local old=s.task; local n=#tasks; s:_poll()
check(#tasks==n,"only one in-flight query")
foreground='another.app'; s.watcher.callback('',hs.application.watcher.activated)
input='OTHER'; finish(old,'terminal-A\n')
check(input=='OTHER',"stale query cannot change another app")
s:_poll(); check(#tasks==n,"no external query while background")
foreground=s.bundleID; s.watcher.callback('',hs.application.watcher.activated)
s:_poll(); old=s.task; timestamp=timestamp+4; s.watchdog.callback()
check(s.task==nil and not old.running,"hung task canceled")
finish(old,'terminal-A\n'); check(input=='OTHER',"late timeout result ignored")
timestamp=timestamp+3; poll(s); check(input=='ABC',"recovers after timeout")
s:setState('closed-terminal','agent'); s.nextCleanup=0
poll(s); check(s.states['closed-terminal']==nil,"closed state cleanup")
s:setState('terminal-A','agent'); s:stop()
local again=new(); check(again.states['terminal-A']=='agent',"reload retains state")
again:_poll(); old=again.task
again:setState('new-terminal','agent'); finish(old,'terminal-A\nLIVE\nterminal-A\n')
check(again.states['new-terminal']=='agent',"cleanup does not discard newly reported state")
again:_poll(); old=again.task; again:stop(); input='STOPPED'; finish(old,'terminal-A\n')
check(input=='STOPPED' and not again.timer,"stop prevents late selection")
again:start(); again.watcher.callback('',hs.application.watcher.terminated,{bundleID=function() return again.bundleID end})
check(next(again.states)==nil,"Ghostty termination clears historical states")
again:stop()
-- Selection failures are bounded and state changes reopen retries.
local attempts=0
hs.keycodes.currentSourceID=function(value)
    if value then attempts=attempts+1; return false end
    return 'UNAVAILABLE'
end
local failing=new()
for _=1,8 do poll(failing) end
check(attempts==3,"selection retry bound")
failing:setState('terminal-A','agent'); poll(failing)
check(attempts==4,"state transition permits another attempt")
failing:stop()
print('PASS: '..count..' state-machine assertions')
