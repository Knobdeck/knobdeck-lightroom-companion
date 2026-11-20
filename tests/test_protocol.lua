local Fake = dofile((debug.getinfo(1, 'S').source:match('^@(.*[/\\])') or './') .. 'fake_lr.lua')
Fake.install()
local P = require 'Protocol'

test('fields with tabs, line breaks and backslashes survive a round trip', function()
  local line = P.encode('7', 'set', 'a\tb', 'c\nd\r', 'back\\slash')
  assert(not line:find('\n'), 'no line break in a line')
  local f = P.split(line .. '\r\n')
  eq(#f, 5, 'fields')
  eq(f[3], 'a\tb'); eq(f[4], 'c\nd\r'); eq(f[5], 'back\\slash')
end)

test('numbers are short and exact enough', function()
  eq(P.field(0.35), '0.35'); eq(P.field(5500), '5500'); eq(P.field(-0.0), '0'); eq(P.field(1 / 3), '0.3333333333')
  eq(P.field(true), '1'); eq(P.field(nil), '')
end)

test('replies and events', function()
  eq(P.ok('3', 'Exposure', 0.5), 'R\t3\tok\tExposure\t0.5')
  eq(P.err('3', 'Select a photo'), 'R\t3\terr\tSelect a photo')
  eq(P.event('value', 'Tint', -4), 'E\tvalue\tTint\t-4')
  local f = P.split('9\twatch\t')
  eq(#f, 3); eq(f[3], '')
end)
