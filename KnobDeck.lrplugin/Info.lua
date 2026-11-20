--[[ KnobDeck for Lightroom Classic: lets the KnobDeck app's dial and keys drive Lightroom through
the Lightroom Classic SDK. See README.md in https://github.com/Knobdeck/knobdeck-lightroom-companion. ]]

return {
  LrSdkVersion = 13.0,
  LrSdkMinimumVersion = 10.0, -- Lightroom Classic 10 (color grading); LrSelection needs 6.0
  LrToolkitIdentifier = 'com.knobdeck.lightroom',
  LrPluginName = 'KnobDeck',
  LrPluginInfoUrl = 'https://github.com/Knobdeck/knobdeck-lightroom-companion',
  LrPluginInfoProvider = 'PluginInfo.lua',
  LrInitPlugin = 'Init.lua',
  LrForceInitPlugin = true, -- start listening when Lightroom starts, not when a menu is first used
  LrShutdownPlugin = 'Shutdown.lua',
  LrDisablePlugin = 'Shutdown.lua',
  LrEnablePlugin = 'Init.lua',
  VERSION = { major = 1, minor = 0, revision = 0, build = 0 },
}
