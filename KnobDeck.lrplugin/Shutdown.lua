--[[ Lightroom quits, or the plug-in is disabled / reloaded: tell KnobDeck and close the ports. ]]

local Bridge = require 'Bridge'

Bridge.stop()
