local Fake = dofile((debug.getinfo(1, 'S').source:match('^@(.*[/\\])') or './') .. 'fake_lr.lua')

local function setup()
  local w = Fake.install()
  local C = require 'Commands'
  return w, C, C.handlers
end

local function fails(fn, want)
  local ok, e = pcall(fn)
  assert(not ok, 'expected an error')
  local _, C = nil, require 'Commands'
  local msg = C.message(e)
  assert(msg:find(want, 1, true), 'message "' .. msg .. '" lacks "' .. want .. '"')
end

test('a develop nudge switches to Develop and moves by the default step', function()
  local w, _, H = setup()
  local p, v = H.nudge('Exposure', '3', '', 'adjustPanel')
  eq(w.module, 'develop', 'module'); eq(p, 'Exposure'); eq(v, 0.15, 'exposure')
  eq(w.panel, 'adjustPanel', 'revealed panel')
  assert(w.yields > 0, 'waited for the module switch')
  _, v = H.nudge('Contrast', '-2', '5')
  eq(v, -10, 'contrast with a step of 5')
end)

test('values clamp to the setting range', function()
  local _, _, H = setup()
  local _, v = H.nudge('Exposure', '1000', '1')
  eq(v, 5, 'max')
  _, v = H.set('Exposure', '-9')
  eq(v, -5, 'min')
  _, v = H.set('Temperature', '6500')
  eq(v, 6500)
end)

test('default steps fit each setting', function()
  local _, C = setup()
  eq(C.defaultStep('Temperature', 2000, 50000), 50, 'raw kelvin')
  eq(C.defaultStep('Temperature', -100, 100), 1, 'jpeg temperature')
  eq(C.defaultStep('Exposure', -5, 5), 0.05)
  eq(C.defaultStep('Contrast', -100, 100), 1)
  eq(C.defaultStep('Tint', -150, 150), 2)
  eq(C.defaultStep('Sharpness', 0, 150), 1)
  eq(C.defaultStep('SharpenRadius', 0.5, 3), 0.01)
end)

test('"lr" steps use Lightroom increment / decrement', function()
  local w, _, H = setup()
  H.nudge('Contrast', '2', 'lr')
  eq(w.calls[1], 'increment Contrast'); eq(w.calls[3], 'increment Contrast')
  H.nudge('Contrast', '-1', 'lr')
  local last = w.calls[#w.calls - 1]
  eq(last, 'decrement Contrast')
end)

test('reset, reset all, auto tone and white balance', function()
  local w, _, H = setup()
  H.set('Tint', '40')
  local _, v = H.reset('Tint')
  eq(v, 10, 'tint default')
  H.set('Exposure', '1')
  H.resetall()
  eq(w.photos[1].develop.Exposure, 0)
  H.auto('tone'); H.auto('wb')
  eq(w.photos[1].develop.Temperature, 5100)
  fails(function() H.auto('everything') end, 'Unknown auto setting')
end)

test('bad and unknown settings are clear errors', function()
  local _, _, H = setup()
  fails(function() H.get('Exp osure') end, 'Not a develop setting')
  fails(function() H.get('NoSuchSlider') end, 'no develop setting called NoSuchSlider')
  fails(function() H.set('Exposure', 'lots') end, 'Not a number')
end)

test('develop commands need a photo', function()
  local w, _, H = setup()
  w.target = nil
  fails(function() H.nudge('Exposure', '1') end, 'Select a photo in Lightroom first')
  fails(function() H.flag('pick') end, 'Select a photo')
end)

test('get returns value and range', function()
  local _, _, H = setup()
  local v, lo, hi = H.get('Tint')
  eq(v, 10); eq(lo, -150); eq(hi, 150)
end)

test('modules, panels, tools and views', function()
  local w, _, H = setup()
  eq(H.module('map'), 'map'); eq(w.module, 'map')
  fails(function() H.module('photoshop') end, 'Unknown Lightroom module')
  H.panel('detailPanel'); eq(w.module, 'develop'); eq(w.panel, 'detailPanel')
  fails(function() H.panel('everything') end, 'Unknown Develop panel')
  H.tool('crop'); eq(w.tool, 'crop')
  H.tool('healing'); eq(w.tool, 'dust')
  H.tool('masking'); eq(w.tool, 'masking')
  fails(function() H.tool('lasso') end, 'Unknown Develop tool')
  local s = {}
  eq(H.view(s, 'toggle'), 'before_after_horiz'); eq(w.view, 'develop_before_after_horiz')
  eq(H.view(s, 'toggle'), 'loupe'); eq(w.view, 'develop_loupe')
  eq(H.view(s, 'before_after_vert'), 'before_after_vert')
  eq(H.view(s, 'toggle'), 'loupe')
end)

test('photos: next, previous, flags, ratings, labels', function()
  local w, C, H = setup()
  local name, flag, rating, label = H.photo('next')
  eq(name, 'IMG_0002.CR3'); eq(flag, 'pick'); eq(rating, 3); eq(label, 'red')
  eq(H.flag('pick'), 'none', 'pick on a pick unflags')
  eq(H.flag('reject'), 'reject')
  eq(H.flag('none'), 'none')
  eq(H.rating('5'), 5); eq(H.rating('up'), 5); eq(H.rating('down'), 4); eq(H.rating('0'), 0)
  fails(function() H.rating('6') end, '0 to 5')
  eq(H.label('red'), 'none', 'red on red removes it'); eq(H.label('blue'), 'blue'); eq(H.label('none'), 'none')
  fails(function() H.label('pink') end, 'Unknown colour label')
  H.photo('previous')
  eq(w.target, 1)
  w.target = nil
  eq(C.photoInfo(), nil, 'no photo')
end)

test('rotate turns the target photo', function()
  local w, _, H = setup()
  H.rotate('right'); eq(w.photos[1].rotation, 90)
  H.rotate('left'); H.rotate('left'); eq(w.photos[1].rotation, 270)
end)

test('copy and paste the global settings, not crop or masks', function()
  local w, _, H = setup()
  local s = {}
  fails(function() H.paste(s) end, 'Copy the settings')
  w.photos[1].develop.Exposure = 1.2
  w.photos[1].develop.CropTop = 0.3
  w.photos[1].develop.Orientation = 'BC'
  eq(H.copy(s), 'IMG_0001.CR3')
  w.selected = { 2, 3 }
  eq(H.paste(s), 2, 'pasted on two photos')
  eq(w.photos[2].develop.Exposure, 1.2); eq(w.photos[3].develop.Exposure, 1.2)
  eq(w.photos[2].develop.CropTop, 0, 'crop stays'); eq(w.photos[3].develop.Orientation, 'AB', 'orientation stays')
  eq(w.writes[1], 'KnobDeck: Paste Settings')
end)

test('undo and redo', function()
  local w, _, H = setup()
  H.undo(); eq(w.undo[1], 'undo')
  fails(function() H.redo() end, 'Nothing to redo')
  w.canUndo = false
  fails(function() H.undo() end, 'Nothing to undo')
end)
