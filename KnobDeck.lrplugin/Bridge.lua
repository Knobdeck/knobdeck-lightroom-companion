--[[ The link to KnobDeck: two LrSocket ports on this computer, pairing, and the events that keep
KnobDeck's keys in step (module, photo, flag, rating, label, develop values).

LrSocket listens on localhost only and a socket either sends or receives, so Lightroom listens on
two ports and the KnobDeck plugin connects to both (see Protocol.lua). Before anything else
KnobDeck sends `hello <token>`. The first time a token is seen Lightroom asks the user to allow it;
the allowed token is kept in this plug-in's preferences, and any other token is refused. Other
programs on this computer can't drive Lightroom without that approval.
]]

local LrApplication = import 'LrApplication'
local LrApplicationView = import 'LrApplicationView'
local LrDevelopController = import 'LrDevelopController'
local LrDialogs = import 'LrDialogs'
local LrPrefs = import 'LrPrefs'
local LrSocket = import 'LrSocket'
local LrTasks = import 'LrTasks'

local Commands = require 'Commands'
local Info = require 'Info'
local Protocol = require 'Protocol'

local Bridge = {}

Bridge.COMMAND_PORT = 58770
Bridge.EVENT_PORT = 58771
Bridge.POLL = 0.15 -- seconds between checks of the module, photo and develop values

local function version()
  local v = Info.VERSION
  return string.format('%d.%d.%d', v.major, v.minor, v.revision)
end
Bridge.version = version

local function prefs()
  return LrPrefs.prefsForPlugin()
end

local function port(v, default)
  local n = tonumber(v)
  if n and n >= 1024 and n <= 65535 and n == math.floor(n) then return n end
  return default
end

function Bridge.ports()
  local p = prefs()
  return port(p.commandPort, Bridge.COMMAND_PORT), port(p.eventPort, Bridge.EVENT_PORT)
end

-- ── Session: one KnobDeck connection ─────────────────────────────────────────

local Session = {}
Session.__index = Session

--- `send(line)` writes one line (without the line break) to KnobDeck.
function Bridge.session(send)
  return setmetatable({
    send = send,
    paired = false,
    asking = false, -- the Allow dialog is open
    denied = {}, -- tokens the user refused while Lightroom runs
    watched = {}, -- develop settings KnobDeck shows
    sent = {}, -- what was last sent: values, module, photo
    dirty = true, -- develop values may have changed
  }, Session)
end

function Session:emit(...)
  self.send(Protocol.event(...))
end

--- KnobDeck disconnected: it has to say hello again.
function Session:reset()
  self.paired = false
  self.sent = {}
  self.dirty = true
end

local function lightroomVersion()
  local ok, v = pcall(function() return LrApplication.versionString() end)
  return ok and v or ''
end

function Session:hello(id, token)
  if type(token) ~= 'string' or #token < 16 then
    return self.send(Protocol.err(id, 'bad token'))
  end
  local p = prefs()
  if p.token == token then
    self.paired = true
    self.sent = {}
    self.dirty = true
    self.status = 'Linked to KnobDeck'
    self.send(Protocol.ok(id, version(), lightroomVersion(), Protocol.VERSION))
    self:poll()
    return
  end
  if self.denied[token] then
    return self.send(Protocol.err(id, 'denied'))
  end
  self.send(Protocol.err(id, 'pending'))
  if self.asking then return end
  self.asking = true
  self.status = 'Waiting for you to allow KnobDeck'
  LrTasks.startAsyncTask(function()
    local answer = LrDialogs.confirm(
      'Allow KnobDeck to control Lightroom Classic?',
      'KnobDeck asked to change develop settings, ratings, flags and the selection from its dial and keys. '
        .. 'Allow it only if you just set up KnobDeck on this computer. You can forget it again in File > Plug-in Manager > KnobDeck.',
      'Allow',
      'Don\'t Allow'
    )
    self.asking = false
    if answer == 'ok' then
      prefs().token = token
      self.status = 'Allowed; KnobDeck links in a moment'
      self:emit('paired')
    else
      self.denied[token] = true
      self.status = 'You didn\'t allow KnobDeck'
      self:emit('denied')
    end
  end)
end

--- One line from KnobDeck.
function Session:handle(line)
  local f = Protocol.split(line)
  local id, cmd = f[1], f[2]
  if not id or id == '' or not cmd then return end
  local args = {}
  for i = 3, #f do args[#args + 1] = f[i] end

  if cmd == 'hello' then return self:hello(id, args[1]) end
  if not self.paired then return self.send(Protocol.err(id, 'not paired')) end

  if cmd == 'watch' then
    self.watched = {}
    for p in (args[1] or ''):gmatch('[^,]+') do self.watched[#self.watched + 1] = p end
    self.dirty = true
    self.send(Protocol.ok(id, #self.watched))
    self:poll()
    return
  end
  if cmd == 'state' then
    self.sent = {}
    self.dirty = true
    self.send(Protocol.ok(id))
    self:poll()
    return
  end

  local h = Commands.handlers[cmd]
  if not h then return self.send(Protocol.err(id, 'Lightroom plug-in ' .. version() .. ' has no command ' .. cmd .. '; update the KnobDeck plug-in')) end
  local withSession = Commands.WITH_SESSION[cmd]
  -- LrTasks.pcall: commands may yield (module switch, catalog writes), which plain pcall forbids.
  local r = { LrTasks.pcall(function()
    if withSession then return h(self, unpack(args)) end
    return h(unpack(args))
  end) }
  if r[1] then
    self.send(Protocol.ok(id, unpack(r, 2, table.maxn(r))))
    self.dirty = true
    self:poll()
  else
    self.send(Protocol.err(id, Commands.message(r[2])))
  end
end

--- Send what changed: module, photo (flag, rating, label), develop values of the watched settings.
function Session:poll()
  if not self.paired then return end
  local sent = self.sent
  local ok, module = pcall(LrApplicationView.getCurrentModuleName)
  if ok and module ~= sent.module then
    sent.module = module
    self:emit('module', module or '')
    self.dirty = true
  end
  local info = { pcall(Commands.photoInfo) }
  if info[1] then
    local key = info[2] and Protocol.encode(info[2], info[3], info[4], info[5]) or ''
    if key ~= sent.photo then
      sent.photo = key
      if info[2] then self:emit('photo', info[2], info[3], info[4], info[5]) else self:emit('photo') end
      self.dirty = true
    end
  end
  -- Develop values can only be read in Develop, with a photo.
  if self.dirty and module == 'develop' and info[1] and info[2] then
    self.dirty = false
    sent.values = sent.values or {}
    for _, p in ipairs(self.watched) do
      local got, v = pcall(LrDevelopController.getValue, p)
      if got and type(v) == 'number' and sent.values[p] ~= v then
        sent.values[p] = v
        self:emit('value', p, v)
      end
    end
  end
end

-- ── Sockets ──────────────────────────────────────────────────────────────────

--- Listen for KnobDeck until Bridge.stop(). Runs in an async task with a function context.
function Bridge.run(context)
  local commandPort, eventPort = Bridge.ports()
  local state = { running = true, sendConnected = false }
  Bridge.state = state

  local sender
  local session = Bridge.session(function(line)
    if state.sendConnected and sender then
      pcall(function() sender:send(line .. '\n') end)
    end
  end)
  Bridge.current = session
  session.status = 'Waiting for KnobDeck on ports ' .. commandPort .. ' and ' .. eventPort

  local function bindSender()
    sender = LrSocket.bind {
      functionContext = context,
      plugin = _PLUGIN,
      port = eventPort,
      mode = 'send',
      onConnected = function() state.sendConnected = true end,
      onClosed = function() state.sendConnected = false end,
      onError = function(socket, err)
        state.sendConnected = false
        if err ~= 'timeout' then session.status = 'Event port ' .. eventPort .. ': ' .. tostring(err) end
        if state.running then socket:reconnect() end
      end,
    }
    state.sender = sender
  end

  state.receiver = LrSocket.bind {
    functionContext = context,
    plugin = _PLUGIN,
    port = commandPort,
    mode = 'receive',
    onMessage = function(_, message)
      if type(message) == 'string' then session:handle(message) end
    end,
    onClosed = function(socket)
      session:reset()
      if session.status == 'Linked to KnobDeck' then session.status = 'KnobDeck disconnected' end
      if state.running then
        socket:reconnect()
        -- Reconnecting a send socket can hang Lightroom; a fresh one doesn't.
        if sender then pcall(function() sender:close() end) end
        bindSender()
      end
    end,
    onError = function(socket, err)
      if err ~= 'timeout' then session.status = 'Command port ' .. commandPort .. ': ' .. tostring(err) end
      if state.running then socket:reconnect() end
    end,
  }
  bindSender()

  local observing = false
  while state.running do
    if session.paired then
      if not observing and LrApplicationView.getCurrentModuleName() == 'develop' and LrApplication.activeCatalog():getTargetPhoto() then
        -- The observer fires on any develop change (sliders, presets, undo, auto); the next poll
        -- reads the watched values.
        LrDevelopController.addAdjustmentChangeObserver(context, Bridge, function() session.dirty = true end)
        observing = true
      end
      LrTasks.pcall(function() session:poll() end)
    end
    LrTasks.sleep(Bridge.POLL)
  end
end

function Bridge.stop()
  local state = Bridge.state
  if not state then return end
  state.running = false
  if Bridge.current and Bridge.current.paired then
    pcall(function() Bridge.current:emit('bye') end)
  end
  for _, s in ipairs({ state.receiver, state.sender }) do
    pcall(function() s:close() end)
  end
  Bridge.state = nil
end

--- Forget the allowed KnobDeck: the next hello asks again.
function Bridge.forget()
  prefs().token = nil
  if Bridge.current then
    Bridge.current.paired = false
    Bridge.current.status = 'Forgot KnobDeck; it asks again when it next links'
  end
end

function Bridge.status()
  if Bridge.current and Bridge.current.status then return Bridge.current.status end
  return 'Not running'
end

return Bridge
