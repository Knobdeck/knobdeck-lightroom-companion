--[[ The KnobDeck section of File > Plug-in Manager: link status, ports, Forget KnobDeck. ]]

local LrView = import 'LrView'
local LrPrefs = import 'LrPrefs'

local Bridge = require 'Bridge'

local function sections(f, _)
  local bind = LrView.bind
  local prefs = LrPrefs.prefsForPlugin()
  local commandPort, eventPort = Bridge.ports()
  if prefs.commandPort == nil then prefs.commandPort = commandPort end
  if prefs.eventPort == nil then prefs.eventPort = eventPort end
  return {
    {
      title = 'KnobDeck',
      synopsis = Bridge.status(),
      f:row { f:static_text { title = 'Status: ' .. Bridge.status(), fill_horizontal = 1 } },
      f:row {
        f:static_text { title = 'Command port', width_in_chars = 12 },
        f:edit_field { value = bind { key = 'commandPort', bind_to_object = prefs }, width_in_digits = 6, min = 1024, max = 65535, precision = 0 },
        f:static_text { title = 'Event port', width_in_chars = 10 },
        f:edit_field { value = bind { key = 'eventPort', bind_to_object = prefs }, width_in_digits = 6, min = 1024, max = 65535, precision = 0 },
      },
      f:row {
        f:static_text {
          title = 'Use the same ports in KnobDeck (Lightroom Classic plugin setup). Port changes apply after Reload Plug-in or a restart.',
          fill_horizontal = 1,
          height_in_lines = 2,
          width_in_chars = 60,
        },
      },
      f:row {
        f:push_button {
          title = 'Forget KnobDeck',
          action = function() Bridge.forget() end,
        },
        f:static_text { title = 'KnobDeck asks to be allowed again the next time it links.' },
      },
    },
  }
end

return { sectionsForTopOfDialog = sections }
