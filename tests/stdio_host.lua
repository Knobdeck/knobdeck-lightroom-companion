--[[ Runs the real plug-in (Init.lua, Bridge.lua, Commands.lua) in the fake Lightroom, with its two
LrSockets carried over stdin / stdout so tests/lrsocket_bridge.py can put them on real TCP ports.

  stdin  "O receive" / "O send"   a client connected to the command / event socket
         "X receive" / "X send"   it disconnected
         "C <line>"               a line arrived on the command socket
         "T"                      time passes: async tasks (the link's poll loop) run once
         "W <lua>"                change the world (the user doing something in Lightroom);
                                  the chunk gets `world`
         "Q"                      Lightroom quits (Shutdown.lua)
  stdout "S <line>"               a line the plug-in sent on the event socket
         "K <mode>"               the plug-in closed that socket (its client is dropped)
         "L <text>"               a note for the test log

Lightroom runs async tasks cooperatively; here each is a coroutine and LrTasks.sleep yields.
]]

local HERE = (debug.getinfo(1, 'S').source:match('^@(.*[/\\])') or './')
local Fake = dofile(HERE .. 'fake_lr.lua')
local world = Fake.newWorld()
world.module = 'develop'
Fake.install(world)

local Tasks = import 'LrTasks'
local running = {}
function Tasks.startAsyncTask(fn)
  running[#running + 1] = coroutine.create(fn)
end
function Tasks.sleep(_)
  coroutine.yield()
end

local function step()
  local still = {}
  for _, co in ipairs(running) do
    local ok, e = coroutine.resume(co)
    if not ok then io.write('L task failed: ', tostring(e), '\n') end
    if coroutine.status(co) ~= 'dead' then still[#still + 1] = co end
  end
  -- Tasks started during this step run on the next one.
  for i = #still + 1, #running do running[i] = nil end
  for i, co in ipairs(still) do running[i] = co end
end

-- The latest socket of each mode, and its send side.
local function socket(mode)
  for i = #world.sockets, 1, -1 do
    if world.sockets[i].params.mode == mode then return world.sockets[i] end
  end
end
local Socket = import 'LrSocket'
local bind = Socket.bind
function Socket.bind(params)
  local s = bind(params)
  function s:send(line)
    io.write('S ', (line:gsub('\n$', '')), '\n')
    io.flush()
  end
  local close = s.close
  function s:close()
    close(self)
    -- LrSocket drops the client when its socket closes.
    io.write('K ', self.params.mode, '\n')
    io.flush()
  end
  return s
end

-- Lightroom loads the plug-in.
dofile(Fake.PLUGIN_DIR .. 'Init.lua')
step()
io.write('L plug-in loaded, ', #world.sockets, ' sockets\n')
io.flush()

for line in io.lines() do
  local kind, rest = line:match('^(%a)%s?(.*)$')
  if kind == 'O' or kind == 'X' then
    local s = socket(rest)
    if s then
      local cb
      if kind == 'O' then cb = s.params.onConnected else cb = s.params.onClosed end
      if cb then cb(s, s.params.port) end
    end
  elseif kind == 'C' then
    local s = socket('receive')
    s.params.onMessage(s, rest)
  elseif kind == 'T' then
    step()
  elseif kind == 'W' then
    local chunk, err = loadstring(rest)
    if not chunk then
      io.write('L bad world chunk: ', err, '\n')
    else
      setfenv(chunk, setmetatable({ world = world }, { __index = _G }))
      local ok, e = pcall(chunk)
      if not ok then io.write('L world chunk failed: ', tostring(e), '\n') end
    end
  elseif kind == 'Q' then
    dofile(Fake.PLUGIN_DIR .. 'Shutdown.lua')
    step()
    break
  end
  step()
  io.flush()
end
