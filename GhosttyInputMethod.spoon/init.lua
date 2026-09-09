--- === GhosttyInputMethod ===
--- Per-terminal input-source rules for Ghostty and foreground CLI agents.
local obj = {}
obj.__index = obj
obj.name = "GhosttyInputMethod"
obj.version = "0.1.3"
obj.author = "AgentType contributors"
obj.license = "MIT - see LICENSE"
obj.terminalSource = "com.apple.keylayout.ABC"
obj.agentSource = "com.tencent.inputmethod.wetype.pinyin"
obj.pollInterval = 0.15
obj.queryTimeout = 3
obj.cleanupInterval = 30
obj.bundleID = "com.mitchellh.ghostty"
local settingsKey = "GhosttyInputMethod.states.v1"
local function validID(id)
    return type(id) == "string" and id:match("^[%w%-]+$") ~= nil
end
local function validSource(id)
    return type(id) == "string" and id:match("^[%w%._%-]+$") ~= nil
end
local function now() return hs.timer.secondsSinceEpoch() end

--- GhosttyInputMethod:init()
--- Method
--- Initializes persistent state without starting background work.
function obj:init()
    self.states, self.revisions = {}, {}
    for id, state in pairs(hs.settings.get(settingsKey) or {}) do
        if validID(id) and state == "agent" then self.states[id] = state end
    end
    self.epoch, self.revision = 0, 0
    self.log = hs.logger.new(self.name, "warning")
    self.stats = {queries = 0, failures = 0, selections = 0}
    return self
end

function obj:_active()
    local app = hs.application.frontmostApplication()
    return app ~= nil and app:bundleID() == self.bundleID
end
function obj:_save() hs.settings.set(settingsKey, self.states) end
function obj:_error(message)
    if self.lastError ~= message then self.log.w(message) end
    self.lastError = message
end

--- GhosttyInputMethod:resolveTTY(tty) -> string | nil
--- Method
--- Resolves the caller's TTY rather than the currently focused terminal.
function obj:resolveTTY(tty)
    if not self.running or type(tty) ~= "string" or not tty:match("^/dev/ttys[%w]+$") then return nil end
    -- Validation above makes interpolation safe. No arbitrary script evaluation API.
    local ok, id = hs.osascript.applescript([[tell application "Ghostty"
        repeat with t in terminals
            if tty of t is "]] .. tty .. [[" then return id of t as text
        end repeat
        return ""
    end tell]])
    if ok and validID(id) then return id end
    self:_error("Cannot resolve TTY; check Ghostty interfaces and Automation permission")
    return nil
end

--- GhosttyInputMethod:setState(id, state) -> boolean
--- Method
--- Records 'agent' or 'terminal' against a previously resolved terminal ID.
function obj:setState(id, state)
    if not self.running or not validID(id) or (state ~= "agent" and state ~= "terminal") then return false end
    local value = state == "agent" and "agent" or nil
    if self.states[id] == value then return true end
    self.states[id] = value
    self.revisions[id] = (self.revisions[id] or 0) + 1
    self.revision = self.revision + 1
    self:_save()
    return true
end

function obj:_cancelQuery()
    local task = self.task
    self.task = nil
    if task and task:isRunning() then task:terminate() end
end

function obj:_poll()
    if not self.running or self.task or not self:_active() or now() < (self.nextQuery or 0) then return end
    local sweep = now() >= (self.nextCleanup or 0)
    local query = [[tell application "Ghostty"
        if not frontmost then return ""
        if (count of windows) = 0 then return ""
        set resultText to id of focused terminal of selected tab of front window as text
    ]]
    if sweep then
        query = query .. [[
        set resultText to resultText & linefeed & "LIVE"
        repeat with t in terminals
            set resultText to resultText & linefeed & (id of t as text)
        end repeat
        ]]
    end
    query = query .. "\nreturn resultText\nend tell"
    local epoch, revision = self.epoch, self.revision
    local task
    task = hs.task.new("/usr/bin/osascript", function(code, out, err)
        if self.task ~= task then return end
        self.task = nil
        if not self.running or epoch ~= self.epoch or not self:_active() then return end
        if code ~= 0 then
            self.stats.failures = self.stats.failures + 1
            self.nextQuery = now() + 2
            self:_error("Ghostty query failed: " .. (err or "unknown error"))
            return
        end
        local lines = {}
        for line in (out or ""):gmatch("[^\r\n]+") do lines[#lines + 1] = line end
        local id = lines[1]
        if not validID(id) then return end
        if sweep and lines[2] == "LIVE" and revision == self.revision then
            local live, wellFormed = {}, true
            for i = 3, #lines do
                if validID(lines[i]) then live[lines[i]] = true else wellFormed = false end
            end
            if wellFormed and live[id] then
                local changed = false
                for old in pairs(self.states) do
                    if not live[old] then self.states[old], self.revisions[old], changed = nil, nil, true end
                end
                for old in pairs(self.revisions) do
                    if not live[old] then self.revisions[old] = nil end
                end
                if changed then self:_save() end
                self.nextCleanup = now() + self.cleanupInterval
            end
        end
        local key = id .. ":" .. (self.revisions[id] or 0)
        if key ~= self.last then
            self.last, self.attempts, self.confirmed = key, 0, false
        end
        self.focusedID = id
        local desired = self.states[id] == "agent" and self.agentSource or self.terminalSource
        if self.confirmed then self.lastError = nil; return end
        if hs.keycodes.currentSourceID() == desired then
            self.confirmed, self.lastError = true, nil
            return
        end
        if self.attempts >= 3 then return end
        self.attempts = self.attempts + 1
        self.stats.selections = self.stats.selections + 1
        if not hs.keycodes.currentSourceID(desired) then
            self:_error("Input source selection failed: " .. desired)
        elseif self.attempts == 3 then self:_error("Input source verification pending") end
    end, {"-e", query})
    self.task, self.taskStarted = task, now()
    self.stats.queries = self.stats.queries + 1
    if not task or not task:start() then
        self.task = nil
        self.nextQuery = now() + 2
        self:_error("Cannot launch Ghostty query")
    end
end

--- GhosttyInputMethod:start() -> self
--- Method
--- Starts polling and application watching. Safe to call repeatedly.
function obj:start()
    if self.running then return self end
    if not self.states then self:init() end
    assert(validSource(self.terminalSource) and validSource(self.agentSource), "Invalid input source ID")
    assert(type(self.pollInterval) == "number" and self.pollInterval >= 0.1, "pollInterval must be >= 0.1")
    assert(type(self.queryTimeout) == "number" and self.queryTimeout >= 1, "queryTimeout must be >= 1")
    assert(type(self.cleanupInterval) == "number" and self.cleanupInterval >= 5, "cleanupInterval must be >= 5")
    require("hs.ipc")
    self.running, self.last, self.nextQuery, self.nextCleanup = true, nil, 0, 0
    self.watcher = hs.application.watcher.new(function(_, event, app)
        local w = hs.application.watcher
        if event == w.activated or event == w.deactivated then
            self.epoch, self.last = self.epoch + 1, nil
            self:_cancelQuery()
        end
        if event == w.terminated and app and app:bundleID() == self.bundleID then
            self.states, self.revisions, self.last = {}, {}, nil
            self.revision = self.revision + 1
            self:_save()
        end
    end):start()
    self.timer = hs.timer.doEvery(self.pollInterval, function() self:_poll() end)
    self.watchdog = hs.timer.doEvery(0.5, function()
        if self.task and now() - self.taskStarted >= self.queryTimeout then
            self:_cancelQuery()
            self.nextQuery = now() + 2
            self.stats.failures = self.stats.failures + 1
            self:_error("Ghostty query timed out")
        end
    end)
    return self
end

--- GhosttyInputMethod:stop() -> self
--- Method
--- Stops background work; retains state for a subsequent start or reload.
function obj:stop()
    self.running = false
    self.epoch = (self.epoch or 0) + 1
    for _, key in ipairs({"timer", "watchdog", "watcher"}) do
        if self[key] then self[key]:stop(); self[key] = nil end
    end
    self:_cancelQuery()
    return self
end

--- GhosttyInputMethod:status() -> table
--- Method
--- Returns diagnostic state without changing the input source.
function obj:status()
    local count = 0
    for _ in pairs(self.states or {}) do count = count + 1 end
    return {version = self.version, running = self.running == true,
        focusedID = self.focusedID, agentTerminals = count, lastError = self.lastError,
        terminalSource = self.terminalSource, agentSource = self.agentSource,
        pollInterval = self.pollInterval, stats = self.stats}
end
return obj
