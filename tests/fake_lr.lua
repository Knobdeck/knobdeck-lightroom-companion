--[[ A fake Lightroom Classic for the tests: the Lr* namespaces the plug-in imports, backed by a
plain "world" table the tests set up and inspect. It follows the SDK's documented behaviour
(LrDevelopController values clamp to getRange and only exist in Develop, LrSelection acts on the
target photo, LrSocket binds a send or a receive socket), not Lightroom's every detail.

  local Fake = dofile('tests/fake_lr.lua')
  local world = Fake.install()          -- fresh world, `import` and package.path set
  local Bridge = require 'Bridge'
]]

local Fake = {}

local HERE = (debug.getinfo(1, 'S').source:match('^@(.*[/\\])') or './')
Fake.PLUGIN_DIR = HERE .. '../KnobDeck.lrplugin/'

local function copy(t)
  local o = {}
  for k, v in pairs(t) do o[k] = v end
  return o
end

-- Ranges and defaults of the settings the tests use (Lightroom's, for a raw photo).
local SETTINGS = {
  Temperature = { 2000, 50000, 5500 },
  Tint = { -150, 150, 10 },
  Exposure = { -5, 5, 0 },
  Contrast = { -100, 100, 0 },
  Highlights = { -100, 100, 0 },
  Shadows = { -100, 100, 0 },
  Whites = { -100, 100, 0 },
  Blacks = { -100, 100, 0 },
  Texture = { -100, 100, 0 },
  Clarity = { -100, 100, 0 },
  Dehaze = { -100, 100, 0 },
  Vibrance = { -100, 100, 0 },
  Saturation = { -100, 100, 0 },
  SharpenRadius = { 0.5, 3, 1 },
  Sharpness = { 0, 150, 40 },
  HueAdjustmentRed = { -100, 100, 0 },
  ParametricShadows = { -100, 100, 0 },
}

function Fake.newWorld()
  local w = {
    module = 'library',
    view = 'loupe',
    tool = 'loupe',
    panel = nil,
    settings = {},
    photos = {
      { name = 'IMG_0001.CR3', flag = 0, rating = 0, label = 'none', rotation = 0, develop = {} },
      { name = 'IMG_0002.CR3', flag = 1, rating = 3, label = 'red', rotation = 0, develop = {} },
      { name = 'IMG_0003.CR3', flag = 0, rating = 0, label = 'none', rotation = 0, develop = {} },
    },
    target = 1, -- index into photos, or nil
    selected = { 1 }, -- what getTargetPhotos returns
    undo = {}, -- names of undone / redone steps
    canUndo = true,
    canRedo = false,
    confirm = 'ok', -- the answer LrDialogs.confirm gives
    confirms = {}, -- messages it was asked
    prefs = {},
    sockets = {},
    tasks = {},
    calls = {}, -- LrDevelopController calls, in order
    observers = {},
    yields = 0,
    writes = {},
    version = '15.1',
  }
  for name, s in pairs(SETTINGS) do w.settings[name] = { min = s[1], max = s[2], default = s[3] } end
  for _, p in ipairs(w.photos) do
    for name, s in pairs(SETTINGS) do p.develop[name] = s[3] end
    p.develop.CropTop = 0
    p.develop.Orientation = 'AB'
    p.develop.MaskGroupBasedCorrections = {}
  end
  return w
end

local function modules(w)
  local function photo()
    return w.target and w.photos[w.target] or nil
  end
  local function needDevelop(fn)
    if w.module ~= 'develop' then error('LrDevelopController.' .. fn .. ': not in the Develop module', 2) end
  end
  local function setting(name)
    return w.settings[name]
  end

  local Photo = {}
  Photo.__index = Photo
  function Photo:getFormattedMetadata(key)
    if key == 'fileName' then return self.p.name end
  end
  function Photo:rotateLeft() self.p.rotation = (self.p.rotation - 90) % 360 end
  function Photo:rotateRight() self.p.rotation = (self.p.rotation + 90) % 360 end
  function Photo:getDevelopSettings() return copy(self.p.develop) end
  function Photo:applyDevelopSettings(s)
    if not w.writing then error('applyDevelopSettings needs catalog write access') end
    for k, v in pairs(s) do self.p.develop[k] = v end
  end
  local function wrap(p) return p and setmetatable({ p = p }, Photo) or nil end

  local catalog = {}
  function catalog:getTargetPhoto() return wrap(photo()) end
  function catalog:getTargetPhotos()
    local out = {}
    for _, i in ipairs(w.selected) do out[#out + 1] = wrap(w.photos[i]) end
    return out
  end
  function catalog:withWriteAccessDo(name, fn)
    w.writes[#w.writes + 1] = name
    w.writing = true
    local ok, e = pcall(fn)
    w.writing = false
    if not ok then error(e, 0) end
  end

  local Dev = {}
  function Dev.getValue(name)
    needDevelop('getValue')
    local p = photo()
    if not p or not setting(name) then return nil end
    return p.develop[name]
  end
  function Dev.getRange(name)
    needDevelop('getRange')
    local s = setting(name)
    if not s then return nil end
    return s.min, s.max
  end
  function Dev.setValue(name, v)
    needDevelop('setValue')
    local s = setting(name)
    if not s then error('unknown parameter ' .. name) end
    w.calls[#w.calls + 1] = 'setValue ' .. name .. ' ' .. v
    photo().develop[name] = math.max(s.min, math.min(s.max, v))
    for _, o in ipairs(w.observers) do o() end
  end
  local function inc(name, sign)
    local s = setting(name)
    local step = (s.max - s.min) / 20 -- Lightroom's own increments are coarser than a dial's
    Dev.setValue(name, photo().develop[name] + sign * step)
  end
  function Dev.increment(name) w.calls[#w.calls + 1] = 'increment ' .. name; inc(name, 1) end
  function Dev.decrement(name) w.calls[#w.calls + 1] = 'decrement ' .. name; inc(name, -1) end
  function Dev.resetToDefault(name)
    needDevelop('resetToDefault')
    photo().develop[name] = setting(name).default
    w.calls[#w.calls + 1] = 'resetToDefault ' .. name
  end
  function Dev.resetAllDevelopAdjustments()
    needDevelop('resetAllDevelopAdjustments')
    for name, s in pairs(w.settings) do photo().develop[name] = s.default end
    w.calls[#w.calls + 1] = 'resetAll'
  end
  function Dev.setAutoTone() needDevelop('setAutoTone'); w.calls[#w.calls + 1] = 'autoTone'; photo().develop.Exposure = 0.4 end
  function Dev.setAutoWhiteBalance() needDevelop('setAutoWhiteBalance'); w.calls[#w.calls + 1] = 'autoWB'; photo().develop.Temperature = 5100 end
  function Dev.revealPanel(panel) w.panel = panel end
  function Dev.selectTool(tool) needDevelop('selectTool'); w.tool = tool end
  function Dev.goToHealing() needDevelop('goToHealing'); w.tool = 'dust' end
  function Dev.goToMasking() needDevelop('goToMasking'); w.tool = 'masking' end
  function Dev.addAdjustmentChangeObserver(_, _, fn) w.observers[#w.observers + 1] = fn end

  local View = {}
  function View.getCurrentModuleName() return w.module end
  function View.switchToModule(m) w.module = m end
  function View.showView(v) w.view = v end

  local FLAGS = { pick = 1, reject = -1, none = 0 }
  local Sel = {}
  local function need() local p = photo(); if not p then error('no photo') end; return p end
  function Sel.nextPhoto() if w.target and w.target < #w.photos then w.target = w.target + 1; w.selected = { w.target } end end
  function Sel.previousPhoto() if w.target and w.target > 1 then w.target = w.target - 1; w.selected = { w.target } end end
  function Sel.getFlag() local p = photo(); return p and p.flag or nil end
  function Sel.flagAsPick() need().flag = FLAGS.pick end
  function Sel.flagAsReject() need().flag = FLAGS.reject end
  function Sel.removeFlag() need().flag = FLAGS.none end
  function Sel.getRating() local p = photo(); return p and p.rating or nil end
  function Sel.setRating(n) need().rating = n end
  function Sel.increaseRating() local p = need(); p.rating = math.min(5, p.rating + 1) end
  function Sel.decreaseRating() local p = need(); p.rating = math.max(0, p.rating - 1) end
  function Sel.getColorLabel() local p = photo(); return p and p.label or nil end
  function Sel.setColorLabel(l) need().label = l end
  for _, c in ipairs({ 'Red', 'Yellow', 'Green', 'Blue', 'Purple' }) do
    Sel['toggle' .. c .. 'Label'] = function()
      local p = need()
      local l = c:lower()
      p.label = (p.label == l) and 'none' or l
    end
  end

  local Undo = {}
  function Undo.canUndo() return w.canUndo end
  function Undo.canRedo() return w.canRedo end
  function Undo.undo() w.undo[#w.undo + 1] = 'undo' end
  function Undo.redo() w.undo[#w.undo + 1] = 'redo' end

  local Tasks = {}
  function Tasks.startAsyncTask(fn) w.tasks[#w.tasks + 1] = fn end
  function Tasks.yield() w.yields = w.yields + 1 end
  function Tasks.sleep(_)
    if w.onSleep then w.onSleep() end
  end
  Tasks.pcall = pcall

  local Dialogs = {}
  function Dialogs.confirm(message)
    w.confirms[#w.confirms + 1] = message
    return w.confirm
  end

  local Socket = {}
  function Socket.bind(params)
    local s = { params = params, closed = false, reconnects = 0, sent = {} }
    function s:send(line) self.sent[#self.sent + 1] = line end
    function s:close() self.closed = true end
    function s:reconnect() self.reconnects = self.reconnects + 1 end
    w.sockets[#w.sockets + 1] = s
    return s
  end

  local App = {}
  function App.activeCatalog() return catalog end
  function App.versionString() return w.version end

  local Prefs = {}
  function Prefs.prefsForPlugin() return w.prefs end

  local Context = {}
  function Context.callWithContext(_, fn) return fn({}) end

  local View2 = { bind = function(t) return t end }

  return {
    LrApplication = App,
    LrApplicationView = View,
    LrDevelopController = Dev,
    LrDialogs = Dialogs,
    LrFunctionContext = Context,
    LrPrefs = Prefs,
    LrSelection = Sel,
    LrSocket = Socket,
    LrTasks = Tasks,
    LrUndo = Undo,
    LrView = View2,
  }
end

--- Run the async tasks started so far (the Allow dialog, ...).
function Fake.flush(w)
  while #w.tasks > 0 do
    local t = table.remove(w.tasks, 1)
    t()
  end
end

local PLUGIN_MODULES = { 'Bridge', 'Commands', 'Info', 'Protocol', 'PluginInfo' }

--- A fresh world with `import`, `_PLUGIN` and the plug-in's folder on package.path.
function Fake.install(world)
  local w = world or Fake.newWorld()
  local m = modules(w)
  _G.import = function(name)
    local x = m[name]
    if not x then error('the fake Lightroom has no ' .. name) end
    return x
  end
  _G._PLUGIN = { path = Fake.PLUGIN_DIR, id = 'com.knobdeck.lightroom' }
  if not package.path:find(Fake.PLUGIN_DIR, 1, true) then
    package.path = Fake.PLUGIN_DIR .. '?.lua;' .. package.path
  end
  for _, name in ipairs(PLUGIN_MODULES) do package.loaded[name] = nil end
  return w
end

return Fake
