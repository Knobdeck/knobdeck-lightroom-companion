--[[ The line protocol between this plug-in and the KnobDeck `lightroom-classic` plugin.

Lightroom's LrSocket speaks plain lines, one message per line, and a socket only sends or only
receives. So there are two loopback sockets that Lightroom listens on and KnobDeck connects to:

  command port (default 58770, LrSocket "receive"): KnobDeck -> Lightroom
      <id> TAB <command> [TAB <arg>]...
  event port   (default 58771, LrSocket "send"):    Lightroom -> KnobDeck
      R TAB <id> TAB ok  [TAB <value>]...      the answer to command <id>
      R TAB <id> TAB err TAB <message>
      E TAB <event> [TAB <value>]...           something changed

Fields are escaped so they never hold a tab or a line break: backslash -> \\, tab -> \t,
line feed -> \n, carriage return -> \r. Numbers are written with %.10g.

Commands and events are a contract with the Rust plugin: add, never rename.
Pure Lua 5.1, no Lightroom imports, so the tests run it as it is.
]]

local Protocol = {}

Protocol.VERSION = 1

local ESC = { ['\\'] = '\\\\', ['\t'] = '\\t', ['\n'] = '\\n', ['\r'] = '\\r' }
local UNESC = { ['\\'] = '\\', t = '\t', n = '\n', r = '\r' }

function Protocol.escape(s)
  return (tostring(s):gsub('[\\\t\n\r]', ESC))
end

function Protocol.unescape(s)
  return (s:gsub('\\(.)', function(c) return UNESC[c] or c end))
end

--- A field as text: numbers with up to 10 significant digits, booleans as 1 / 0.
function Protocol.field(v)
  if v == nil then return '' end
  if type(v) == 'number' then
    if v ~= v then return '' end -- NaN
    local s = string.format('%.10g', v)
    if s == '-0' then s = '0' end
    return s
  end
  if type(v) == 'boolean' then return v and '1' or '0' end
  return Protocol.escape(v)
end

--- One line (without the line break) from fields.
function Protocol.encode(...)
  local n = select('#', ...)
  local out = {}
  for i = 1, n do
    out[i] = Protocol.field((select(i, ...)))
  end
  return table.concat(out, '\t')
end

--- Fields of one received line (a trailing CR / LF is dropped).
function Protocol.split(line)
  line = line:gsub('[\r\n]+$', '')
  local fields = {}
  local start = 1
  while true do
    local i = line:find('\t', start, true)
    if not i then
      fields[#fields + 1] = Protocol.unescape(line:sub(start))
      break
    end
    fields[#fields + 1] = Protocol.unescape(line:sub(start, i - 1))
    start = i + 1
  end
  return fields
end

--- Reply lines.
function Protocol.ok(id, ...)
  return Protocol.encode('R', id, 'ok', ...)
end

function Protocol.err(id, message)
  return Protocol.encode('R', id, 'err', message)
end

function Protocol.event(name, ...)
  return Protocol.encode('E', name, ...)
end

return Protocol
