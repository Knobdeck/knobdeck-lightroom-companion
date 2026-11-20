--[[ Runs the plug-in's unit tests against the fake Lightroom (Lua 5.1, as in Lightroom Classic):

  lua5.1 tests/run.lua          (luajit tests/run.lua works too)
]]

local HERE = (debug.getinfo(1, 'S').source:match('^@(.*[/\\])') or './')
package.path = HERE .. '?.lua;' .. package.path

local tests, failed = {}, 0
function _G.test(name, fn) tests[#tests + 1] = { name = name, fn = fn } end

function _G.eq(got, want, what)
  if got ~= want then
    error(string.format('%s: got %s, want %s', what or 'value', tostring(got), tostring(want)), 2)
  end
end

for _, file in ipairs({ 'test_protocol', 'test_commands', 'test_bridge' }) do
  dofile(HERE .. file .. '.lua')
end

for _, t in ipairs(tests) do
  local ok, e = pcall(t.fn)
  if ok then
    print('ok    ' .. t.name)
  else
    failed = failed + 1
    print('FAIL  ' .. t.name .. '\n      ' .. tostring(e))
  end
end
print(string.format('%d tests, %d failed (%s)', #tests, failed, _VERSION))
os.exit(failed == 0 and 0 or 1)
