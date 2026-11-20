--[[ Starts the link to KnobDeck when Lightroom loads the plug-in (LrForceInitPlugin). ]]

local LrFunctionContext = import 'LrFunctionContext'
local LrTasks = import 'LrTasks'

local Bridge = require 'Bridge'

if not Bridge.state then
  LrTasks.startAsyncTask(function()
    LrFunctionContext.callWithContext('KnobDeck link', function(context)
      Bridge.run(context)
    end)
  end)
end
