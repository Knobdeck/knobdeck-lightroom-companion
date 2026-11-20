# KnobDeck plug-in for Lightroom Classic

A Lightroom Classic plug-in (`KnobDeck.lrplugin`) that lets the
[KnobDeck](https://knobdeck.harshalkudale.com) **Lightroom Classic** plugin control Lightroom
through the Lightroom Classic SDK, instead of sending keyboard shortcuts. Turn a dial to move any
Develop slider and see its value on the tile; press keys to switch modules, step through photos,
flag, rate, label, rotate, copy / paste settings, auto tone and undo.

Works with Lightroom Classic 10 and newer on Windows and macOS.

## Install

1. In KnobDeck, install the **Lightroom Classic** plugin (Get Plugins) and run its setup. With
   *Install the KnobDeck plug-in* ticked, setup downloads `KnobDeck.lrplugin.zip` from this repo's
   latest [release](https://github.com/Knobdeck/knobdeck-lightroom-companion/releases) and unpacks
   it into Lightroom's **Modules** folder, where Lightroom loads plug-ins by itself at start-up:
   - Windows: `%APPDATA%\Adobe\Lightroom\Modules`
   - macOS: `~/Library/Application Support/Adobe/Lightroom/Modules`

   **Or by hand:** download `KnobDeck.lrplugin.zip` from a release, unzip it into a folder that
   stays (not Downloads), and in Lightroom choose **File ▸ Plug-in Manager ▸ Add** and pick the
   `KnobDeck.lrplugin` folder. (A plug-in in the Modules folder shows in Plug-in Manager too, but
   can only be disabled there, not removed.)
2. Restart Lightroom Classic.
3. When KnobDeck links the first time, Lightroom asks **Allow KnobDeck to control Lightroom
   Classic?** Click **Allow**.

**File ▸ Plug-in Manager ▸ KnobDeck** shows whether KnobDeck is linked, the two ports, and
**Forget KnobDeck**.

## How KnobDeck and Lightroom talk

Lightroom plug-ins can't open WebSockets or connect out to KnobDeck's companion hub; the SDK's
`LrSocket` only **listens on localhost**, and each socket either **sends or receives**, never
both. So the plug-in listens on two loopback ports and the KnobDeck plugin connects to both (the
same arrangement MIDI2LR uses):

| Port | LrSocket mode | Carries |
|---|---|---|
| 58770 | `receive` | KnobDeck's commands: `<id> TAB <command> [TAB <arg>]...` |
| 58771 | `send` | answers `R TAB <id> TAB ok [TAB <value>]...` / `R TAB <id> TAB err TAB <message>`, and events `E TAB <event> [TAB <value>]...` |

One line per message; fields escape `\`, tab, LF and CR as `\\`, `\t`, `\n`, `\r`. Both ports can
be changed in Plug-in Manager (then *Reload Plug-in*) and in KnobDeck's setup; they must match.

**Pairing.** Any program on the computer can connect to a localhost port, so the first command on
every connection must be `hello <token>`. KnobDeck makes a random token once and keeps it in the
OS credential store. The first time Lightroom sees a token it answers `pending` and asks you to
allow it; on **Allow** it keeps the token in the plug-in's preferences and sends `E paired`, and
KnobDeck says hello again. Any other token gets the same question (so a stranger can't drive
Lightroom without you clicking Allow), a refused one is refused without asking again until
Lightroom restarts, and nothing but `hello` runs before pairing. *Forget KnobDeck* drops the
token; KnobDeck's setup **Pair again** makes a new one. The event port only carries what the keys
show (module, file name, flag, rating, label, Develop values).

**Commands** (a contract with the Rust plugin: add, never rename): `hello`, `watch <settings>`
(the Develop settings KnobDeck shows), `state`, `get`, `set <setting> <value> [panel]`,
`nudge <setting> <ticks> [step|lr] [panel]`, `reset`, `resetall`, `auto tone|wb`, `panel`, `tool`,
`module`, `view`, `photo next|previous`, `flag`, `rating`, `label`, `rotate`, `copy`, `paste`,
`undo`, `redo`. **Events**: `paired`, `denied`, `module`, `photo <name> <flag> <rating> <label>`,
`value <setting> <number>`, `bye`.

## What each KnobDeck action does in Lightroom

| KnobDeck action | Lightroom SDK |
|---|---|
| Basic panel dials, Develop Slider (tone curve, HSL, color grading, detail, lens, transform, effects, calibration) | `LrDevelopController.getValue` / `setValue` (clamped to `getRange`), or `increment` / `decrement` for Lightroom's own steps; `revealPanel`; switches to Develop first |
| Press a dial | `LrDevelopController.resetToDefault` |
| Live values on the tiles | `LrDevelopController.addAdjustmentChangeObserver`, then the watched values are read and the changed ones sent |
| Reset All, Auto Tone, Auto White Balance | `resetAllDevelopAdjustments`, `setAutoTone`, `setAutoWhiteBalance` |
| Develop Tool, Show Develop Panel | `selectTool`, `goToHealing` / `goToMasking` (newer Lightroom), `revealPanel` |
| Module, Modules wheel | `LrApplicationView.switchToModule` |
| Before / After | `LrApplicationView.showView` (`develop_before_after_horiz` / `_vert`, `develop_before`, `develop_loupe`) |
| Next / Previous Photo, Flag, Rating, Color Label | `LrSelection.nextPhoto` / `previousPhoto`, `flagAsPick` / `flagAsReject` / `removeFlag`, `setRating` / `increaseRating` / `decreaseRating`, `toggle<Color>Label` / `setColorLabel` |
| Rotate Left / Right | `LrPhoto:rotateLeft` / `rotateRight` on the target photo (Lightroom turns the selection) |
| Copy / Paste Settings | `LrPhoto:getDevelopSettings`, then `applyDevelopSettings` on each selected photo inside `withWriteAccessDo`; the crop, orientation and local corrections are left out |
| Undo, Redo | `LrUndo.undo` / `redo` (after `canUndo` / `canRedo`) |

Nothing that exists only as a keyboard shortcut is offered.

## Privacy

It talks only to KnobDeck on your own computer and collects nothing: see [PRIVACY.md](PRIVACY.md).

## Development

See [CONTRIBUTING.md](CONTRIBUTING.md). The plugin it talks to is
[`lightroom-classic`](https://github.com/Knobdeck/knobdeck-plugins/tree/master/lightroom-classic)
in knobdeck-plugins.
