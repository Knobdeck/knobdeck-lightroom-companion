local Fake = dofile((debug.getinfo(1, 'S').source:match('^@(.*[/\\])') or './') .. 'fake_lr.lua')
local TOKEN = 'abcdefghijklmnop0123456789'

local function setup()
  local w = Fake.install()
  local Bridge = require 'Bridge'
  local P = require 'Protocol'
  local out = {}
  local s = Bridge.session(function(line) out[#out + 1] = P.split(line) end)
  return w, s, out, Bridge
end

local function find(out, kind, name)
  for _, f in ipairs(out) do
    if f[1] == kind and (f[2] == name or (kind == 'R' and f[2] == name)) then return f end
  end
end

local function pair(w, s, out)
  w.prefs.token = TOKEN
  s:handle('1\thello\t' .. TOKEN .. '\ttest')
  local r = find(out, 'R', '1')
  eq(r[3], 'ok', 'hello')
  return r
end

test('nothing runs before hello', function()
  local w, s, out = setup()
  s:handle('1\tmodule\tdevelop')
  eq(out[1][3], 'err'); eq(out[1][4], 'not paired')
  eq(w.module, 'library', 'module unchanged')
end)

test('a new token asks the user, then pairs', function()
  local w, s, out = setup()
  s:handle('1\thello\t' .. TOKEN)
  eq(out[1][3], 'err'); eq(out[1][4], 'pending')
  s:handle('2\thello\t' .. TOKEN)
  eq(out[2][4], 'pending')
  Fake.flush(w)
  eq(#w.confirms, 1, 'one dialog for two hellos')
  eq(w.prefs.token, TOKEN, 'token kept')
  eq(out[3][1], 'E'); eq(out[3][2], 'paired')
  s:handle('3\thello\t' .. TOKEN)
  local r = find(out, 'R', '3')
  eq(r[3], 'ok'); eq(r[4], '1.0.0', 'plug-in version'); eq(r[5], '15.1', 'Lightroom version'); eq(r[6], '1', 'protocol')
end)

test('a refused token is refused until Lightroom restarts', function()
  local w, s, out = setup()
  w.confirm = 'cancel'
  s:handle('1\thello\t' .. TOKEN)
  Fake.flush(w)
  eq(w.prefs.token, nil)
  eq(out[2][2], 'denied')
  s:handle('2\thello\t' .. TOKEN)
  eq(out[3][4], 'denied'); eq(#w.confirms, 1, 'no second dialog')
end)

test('another token than the allowed one asks again and short tokens are refused', function()
  local w, s, out = setup()
  w.prefs.token = TOKEN
  s:handle('1\thello\tshort')
  eq(out[1][4], 'bad token')
  s:handle('2\thello\tzzzzzzzzzzzzzzzzzzzz')
  eq(out[2][4], 'pending')
end)

test('after hello the state is sent, and commands answer', function()
  local w, s, out = setup()
  pair(w, s, out)
  local m = find(out, 'E', 'module'); eq(m[3], 'library')
  local p = find(out, 'E', 'photo'); eq(p[3], 'IMG_0001.CR3'); eq(p[4], 'none'); eq(p[5], '0'); eq(p[6], 'none')
  s:handle('2\twatch\tExposure,Contrast,Tint')
  eq(find(out, 'R', '2')[4], '3')
  s:handle('3\tnudge\tExposure\t2\t\tadjustPanel')
  local r = find(out, 'R', '3')
  eq(r[3], 'ok'); eq(r[4], 'Exposure'); eq(r[5], '0.1')
  -- Now in Develop: module event and the watched values follow.
  eq(find(out, 'E', 'module') ~= nil, true)
  local values = {}
  for _, f in ipairs(out) do if f[1] == 'E' and f[2] == 'value' then values[f[3]] = f[4] end end
  eq(values.Exposure, '0.1'); eq(values.Contrast, '0'); eq(values.Tint, '10')
end)

test('errors come back as sentences', function()
  local w, s, out = setup()
  pair(w, s, out)
  w.target = nil
  s:handle('5\tflag\tpick')
  local r = find(out, 'R', '5')
  eq(r[3], 'err'); eq(r[4], 'Select a photo in Lightroom first')
  s:handle('6\tteleport')
  assert(find(out, 'R', '6')[4]:find('has no command teleport'), 'unknown command')
end)

test('changes made in Lightroom are pushed once', function()
  local w, s, out = setup()
  pair(w, s, out)
  s:handle('2\twatch\tExposure')
  s:handle('3\tmodule\tdevelop')
  local before = #out
  s:poll()
  eq(#out, before, 'nothing changed, nothing sent')
  w.photos[1].develop.Exposure = 0.7 -- the user moves the slider
  s.dirty = true -- the adjustment observer's job
  s:poll()
  eq(out[#out][2], 'value'); eq(out[#out][4], '0.7')
  w.photos[1].rating = 4 -- the user presses 4
  s:poll()
  eq(out[#out][2], 'photo'); eq(out[#out][5], '4')
  w.target = 2
  s:poll()
  local photo
  for _, f in ipairs(out) do if f[2] == 'photo' then photo = f end end
  eq(photo[3], 'IMG_0002.CR3')
end)

test('a disconnect needs a new hello', function()
  local w, s, out = setup()
  pair(w, s, out)
  s:reset()
  s:handle('9\tundo')
  eq(find(out, 'R', '9')[4], 'not paired')
end)

test('run binds a receive and a send socket on the configured ports and stops', function()
  local w, _, _, Bridge = setup()
  w.prefs.commandPort = 60001
  w.prefs.eventPort = 'nonsense'
  local loops = 0
  w.onSleep = function()
    loops = loops + 1
    if loops == 2 then Bridge.stop() end
  end
  Bridge.run({})
  eq(#w.sockets, 2, 'two sockets')
  eq(w.sockets[1].params.mode, 'receive'); eq(w.sockets[1].params.port, 60001)
  eq(w.sockets[2].params.mode, 'send'); eq(w.sockets[2].params.port, 58771, 'bad pref -> default')
  assert(w.sockets[1].closed and w.sockets[2].closed, 'closed on stop')
end)

test('the receive socket closing rebinds the send socket and drops the pairing', function()
  local w, _, _, Bridge = setup()
  w.prefs.token = TOKEN
  local checked = false
  w.onSleep = function()
    -- Drive the sockets' callbacks as Lightroom would, while the link runs.
    local recv, send = w.sockets[1].params, w.sockets[2].params
    send.onConnected(w.sockets[2])
    recv.onMessage(w.sockets[1], '1\thello\t' .. TOKEN)
    eq(Bridge.current.paired, true)
    eq(#w.sockets[2].sent > 0, true, 'hello answered on the send socket')
    recv.onClosed(w.sockets[1])
    eq(Bridge.current.paired, false, 'unpaired')
    eq(#w.sockets, 3, 'a fresh send socket')
    eq(w.sockets[2].closed, true, 'the old one closed')
    recv.onError(w.sockets[1], 'timeout')
    eq(w.sockets[1].reconnects, 2, 'reconnected after close and timeout')
    checked = true
    Bridge.stop()
  end
  Bridge.run({})
  eq(checked, true)
end)

test('forget drops the allowed token', function()
  local w, s, out, Bridge = setup()
  pair(w, s, out)
  Bridge.current = s
  Bridge.forget()
  eq(w.prefs.token, nil); eq(s.paired, false)
end)

test('the Plug-in Manager section builds', function()
  local w = Fake.install()
  local Info = require 'PluginInfo'
  local f = setmetatable({}, { __index = function(_, k) return function(_, t) t.kind = k; return t end end })
  local sections = Info.sectionsForTopOfDialog(f, {})
  eq(sections[1].title, 'KnobDeck')
  eq(w.prefs.commandPort, 58770); eq(w.prefs.eventPort, 58771)
end)
