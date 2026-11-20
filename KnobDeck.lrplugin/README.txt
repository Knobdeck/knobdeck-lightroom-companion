KnobDeck for Lightroom Classic
==============================

Lets the KnobDeck app (https://knobdeck.harshalkudale.com) control Lightroom Classic 10 or newer
through the Lightroom Classic SDK: Develop sliders on its dial with live values, modules, photos,
flags, ratings, colour labels, rotate, copy / paste settings, auto tone, before / after and undo.

Install
-------
Easiest: run the setup of the "Lightroom Classic" plugin in KnobDeck. It copies this folder into
Lightroom's Modules folder, where Lightroom loads it at start-up:
  Windows: %APPDATA%\Adobe\Lightroom\Modules
  macOS:   ~/Library/Application Support/Adobe/Lightroom/Modules

Or by hand: put this folder somewhere it can stay and add it with File > Plug-in Manager > Add.

Restart Lightroom. When KnobDeck first links, Lightroom asks you to allow it; click Allow.

Link
----
The plug-in listens on this computer only (localhost), on two ports: 58770 for KnobDeck's commands
and 58771 for answers and changes (an LrSocket either sends or receives). Change them in
File > Plug-in Manager > KnobDeck (then Reload Plug-in) and in KnobDeck's setup, if another app
uses them. Only the KnobDeck you allowed can drive Lightroom; "Forget KnobDeck" there undoes it.

Source, privacy and help: https://github.com/Knobdeck/knobdeck-lightroom-companion
