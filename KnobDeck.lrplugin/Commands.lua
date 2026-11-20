--[[ What each KnobDeck command does in Lightroom Classic, through the SDK only:
LrDevelopController (develop settings), LrApplicationView (modules and views), LrSelection
(photos, flags, ratings, labels), LrUndo, and the catalog's photos. Never key events.

Each command returns the reply's values, or raises Commands.fail(message) with a sentence the
KnobDeck key shows. Commands are a contract with the Rust plugin: add, never rename.
]]

local LrApplication = import 'LrApplication'
local LrApplicationView = import 'LrApplicationView'
local LrDevelopController = import 'LrDevelopController'
local LrSelection = import 'LrSelection'
local LrTasks = import 'LrTasks'
local LrUndo = import 'LrUndo'

local Commands = {}

local FAIL = {}
FAIL.__index = FAIL
FAIL.__tostring = function(e) return e.message end

--- Stop the command with a message for the user.
function Commands.fail(message)
  error(setmetatable({ message = message }, FAIL), 0)
end
local fail = Commands.fail

--- The user-facing text of an error raised in a command.
function Commands.message(e)
  if getmetatable(e) == FAIL then return e.message end
  return 'Lightroom: ' .. tostring(e)
end

-- ── Helpers ──────────────────────────────────────────────────────────────────

local MODULES = { library = true, develop = true, map = true, book = true, slideshow = true, print = true, web = true }

local function catalog()
  return LrApplication.activeCatalog()
end

local function targetPhoto()
  local photo = catalog():getTargetPhoto()
  if not photo then fail('Select a photo in Lightroom first') end
  return photo
end

--- Develop settings change only in the Develop module: switch to it (as turning a develop dial
--- asks for) and let Lightroom finish the switch.
local function inDevelop()
  if LrApplicationView.getCurrentModuleName() ~= 'develop' then
    LrApplicationView.switchToModule('develop')
    LrTasks.yield()
  end
  targetPhoto()
end

local function checkParam(param)
  if type(param) ~= 'string' or not param:match('^[%a][%w]*$') then
    fail('Not a develop setting: ' .. tostring(param))
  end
end

local function value(param)
  local v = LrDevelopController.getValue(param)
  if type(v) ~= 'number' then fail('Lightroom has no develop setting called ' .. param) end
  return v
end

local function range(param)
  local lo, hi = LrDevelopController.getRange(param)
  if type(lo) ~= 'number' or type(hi) ~= 'number' then fail('Lightroom has no develop setting called ' .. param) end
  return lo, hi
end

local function clamp(v, lo, hi)
  if v < lo then return lo end
  if v > hi then return hi end
  return v
end

--- Dial arithmetic without float dust (0.1 + 0.05 = 0.15, not 0.15000000000000002).
local function tidy(v)
  return math.floor(v * 10000 + 0.5) / 10000
end

local function num(s, what)
  local n = tonumber(s)
  if not n or n ~= n then fail('Not a number for ' .. what .. ': ' .. tostring(s)) end
  return n
end

--- The step a dial tick moves a setting by when KnobDeck sends none.
function Commands.defaultStep(param, lo, hi)
  if param == 'Temperature' then
    -- Raw photos: kelvin (2,000-50,000); JPEG and others: -100..100.
    return (hi > 1000) and 50 or 1
  end
  if param == 'Exposure' then return 0.05 end
  local r = (hi - lo) / 200
  if r >= 0.75 then return math.floor(r + 0.5) end
  -- Small ranges (Sharpen Radius 0.5-3.0, ...): one significant digit.
  local p = 10 ^ math.floor(math.log10(r))
  return math.floor(r / p + 0.5) * p
end

local function reveal(panel)
  if panel and panel ~= '' then
    LrDevelopController.revealPanel(panel)
  end
end

-- ── Develop settings ─────────────────────────────────────────────────────────

local C = {}
Commands.handlers = C

--- get <param> -> value, min, max
function C.get(param)
  checkParam(param)
  inDevelop()
  local lo, hi = range(param)
  return value(param), lo, hi
end

--- set <param> <value> [panel to reveal] -> param, value
function C.set(param, v, panel)
  checkParam(param)
  inDevelop()
  local lo, hi = range(param)
  LrDevelopController.setValue(param, clamp(num(v, param), lo, hi))
  reveal(panel)
  return param, value(param)
end

--- nudge <param> <ticks> [step | "lr"] [panel to reveal] -> param, value
--- "lr" steps with Lightroom's own increment / decrement (as its + / - keys do), one per tick.
function C.nudge(param, ticks, step, panel)
  checkParam(param)
  inDevelop()
  ticks = num(ticks, 'ticks')
  if step == 'lr' then
    local n = math.min(50, math.floor(math.abs(ticks) + 0.5))
    for _ = 1, n do
      if ticks > 0 then LrDevelopController.increment(param) else LrDevelopController.decrement(param) end
    end
  else
    local lo, hi = range(param)
    local s = tonumber(step)
    if not s or s <= 0 then s = Commands.defaultStep(param, lo, hi) end
    LrDevelopController.setValue(param, clamp(tidy(value(param) + ticks * s), lo, hi))
  end
  reveal(panel)
  return param, value(param)
end

--- reset <param> -> param, value (the setting's default)
function C.reset(param)
  checkParam(param)
  inDevelop()
  LrDevelopController.resetToDefault(param)
  return param, value(param)
end

function C.resetall()
  inDevelop()
  LrDevelopController.resetAllDevelopAdjustments()
end

--- auto tone | wb
function C.auto(what)
  inDevelop()
  if what == 'tone' then
    LrDevelopController.setAutoTone()
  elseif what == 'wb' then
    LrDevelopController.setAutoWhiteBalance()
  else
    fail('Unknown auto setting: ' .. tostring(what))
  end
end

local PANELS = {
  adjustPanel = true, tonePanel = true, mixerPanel = true, colorGradingPanel = true, detailPanel = true,
  lensCorrectionsPanel = true, transformPanel = true, effectsPanel = true, calibratePanel = true,
}

--- panel <panel>: show and expand a Develop panel
function C.panel(panel)
  if not PANELS[panel] then fail('Unknown Develop panel: ' .. tostring(panel)) end
  if LrApplicationView.getCurrentModuleName() ~= 'develop' then
    LrApplicationView.switchToModule('develop')
    LrTasks.yield()
  end
  LrDevelopController.revealPanel(panel)
end

--- tool loupe | crop | healing | redeye | masking
function C.tool(tool)
  inDevelop()
  if tool == 'healing' then
    if LrDevelopController.goToHealing then LrDevelopController.goToHealing() else LrDevelopController.selectTool('dust') end
  elseif tool == 'masking' then
    if LrDevelopController.goToMasking then LrDevelopController.goToMasking() else LrDevelopController.selectTool('masking') end
  elseif tool == 'loupe' or tool == 'crop' or tool == 'redeye' then
    LrDevelopController.selectTool(tool)
  else
    fail('Unknown Develop tool: ' .. tostring(tool))
  end
end

-- ── Modules and views ────────────────────────────────────────────────────────

--- module <name> -> name
function C.module(name)
  if not MODULES[name] then fail('Unknown Lightroom module: ' .. tostring(name)) end
  LrApplicationView.switchToModule(name)
  return name
end

local VIEWS = {
  loupe = 'develop_loupe',
  before_after_horiz = 'develop_before_after_horiz',
  before_after_vert = 'develop_before_after_vert',
  before = 'develop_before',
}

--- view loupe | before_after_horiz | before_after_vert | before | toggle -> the view shown
--- "toggle" goes between the Develop loupe and the side-by-side before / after view.
function C.view(session, view)
  inDevelop()
  if view == 'toggle' then
    view = (session.view and session.view ~= 'loupe') and 'loupe' or 'before_after_horiz'
  end
  local name = VIEWS[view]
  if not name then fail('Unknown Develop view: ' .. tostring(view)) end
  LrApplicationView.showView(name)
  session.view = view
  return view
end

-- ── Photos ───────────────────────────────────────────────────────────────────

local FLAGS = { [1] = 'pick', [-1] = 'reject' }

--- name, flag, rating, label of the photo the selection commands act on (nil when none).
function Commands.photoInfo()
  local photo = catalog():getTargetPhoto()
  if not photo then return nil end
  local name = photo:getFormattedMetadata('fileName') or ''
  local flag = FLAGS[LrSelection.getFlag() or 0] or 'none'
  local rating = LrSelection.getRating() or 0
  local label = LrSelection.getColorLabel() or 'none'
  if label == '' then label = 'none' end
  return name, flag, rating, label
end

--- photo next | previous
function C.photo(where)
  if where == 'next' then
    LrSelection.nextPhoto()
  elseif where == 'previous' then
    LrSelection.previousPhoto()
  else
    fail('Unknown direction: ' .. tostring(where))
  end
  return Commands.photoInfo()
end

--- flag pick | reject | none -> the flag after. Pick / reject on a photo that has it already
--- removes it (a key toggles).
function C.flag(flag)
  targetPhoto()
  local now = FLAGS[LrSelection.getFlag() or 0] or 'none'
  if flag == 'none' or flag == now then
    LrSelection.removeFlag()
  elseif flag == 'pick' then
    LrSelection.flagAsPick()
  elseif flag == 'reject' then
    LrSelection.flagAsReject()
  else
    fail('Unknown flag: ' .. tostring(flag))
  end
  return FLAGS[LrSelection.getFlag() or 0] or 'none'
end

--- rating 0..5 | up | down -> the rating after
function C.rating(r)
  targetPhoto()
  if r == 'up' then
    LrSelection.increaseRating()
  elseif r == 'down' then
    LrSelection.decreaseRating()
  else
    local n = tonumber(r)
    if not n or n < 0 or n > 5 or n ~= math.floor(n) then fail('A rating is 0 to 5 stars') end
    LrSelection.setRating(n)
  end
  return LrSelection.getRating() or 0
end

local TOGGLE_LABEL = {
  red = 'toggleRedLabel', yellow = 'toggleYellowLabel', green = 'toggleGreenLabel',
  blue = 'toggleBlueLabel', purple = 'togglePurpleLabel',
}

--- label red | yellow | green | blue | purple | none -> the label after. A colour toggles.
function C.label(label)
  targetPhoto()
  if label == 'none' then
    LrSelection.setColorLabel('none')
  elseif TOGGLE_LABEL[label] then
    LrSelection[TOGGLE_LABEL[label]]()
  else
    fail('Unknown colour label: ' .. tostring(label))
  end
  local now = LrSelection.getColorLabel() or 'none'
  if now == '' then now = 'none' end
  return now
end

--- rotate left | right (Lightroom turns every selected photo)
function C.rotate(dir)
  local photo = targetPhoto()
  if dir == 'left' then
    photo:rotateLeft()
  elseif dir == 'right' then
    photo:rotateRight()
  else
    fail('Unknown direction: ' .. tostring(dir))
  end
end

-- Settings Copy / Paste leaves alone: the crop, orientation and local corrections (healing, red
-- eye, masks), which belong to one photo. What is left are the global adjustments.
local NOT_COPIED = {
  Orientation = true, HasCrop = true, RetouchInfo = true, RetouchAreas = true, RedEyeInfo = true,
  GradientBasedCorrections = true, CircularGradientBasedCorrections = true, PaintBasedCorrections = true,
  MaskGroupBasedCorrections = true,
}

function Commands.copyable(settings)
  local out = {}
  for k, v in pairs(settings or {}) do
    if not NOT_COPIED[k] and not tostring(k):match('^Crop') then out[k] = v end
  end
  return out
end

--- copy -> the photo's file name
function C.copy(session)
  local photo = targetPhoto()
  session.copied = Commands.copyable(photo:getDevelopSettings())
  session.copiedFrom = photo:getFormattedMetadata('fileName') or ''
  return session.copiedFrom
end

--- paste -> how many photos got the settings
function C.paste(session)
  if not session.copied then fail('Copy the settings of a photo first (Copy Settings)') end
  local cat = catalog()
  local photos = cat:getTargetPhotos()
  if not photos or #photos == 0 then fail('Select a photo in Lightroom first') end
  local settings = session.copied
  cat:withWriteAccessDo('KnobDeck: Paste Settings', function()
    for _, p in ipairs(photos) do
      p:applyDevelopSettings(settings)
    end
  end, { timeout = 5 })
  return #photos
end

-- ── History ──────────────────────────────────────────────────────────────────

function C.undo()
  if LrUndo.canUndo and not LrUndo.canUndo() then fail('Nothing to undo') end
  LrUndo.undo()
end

function C.redo()
  if LrUndo.canRedo and not LrUndo.canRedo() then fail('Nothing to redo') end
  LrUndo.redo()
end

-- Commands that keep something between calls get the session as their first argument.
Commands.WITH_SESSION = { view = true, copy = true, paste = true }

return Commands
