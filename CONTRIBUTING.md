# Developing the KnobDeck plug-in for Lightroom Classic

The plug-in it talks to is [`lightroom-classic`](https://github.com/Knobdeck/knobdeck-plugins/tree/master/lightroom-classic)
in knobdeck-plugins (Rust). The line protocol (`KnobDeck.lrplugin/Protocol.lua`, mirrored in that
plugin's `src/proto.rs`) and the command and event names are a contract between the two: add,
never rename, and keep old commands working (KnobDeck's setup installs the newest plug-in, which
may meet an older KnobDeck plugin).

## Layout

- `KnobDeck.lrplugin/`: the plug-in, Lua 5.1 as Lightroom runs it. No other files are needed.
  - `Info.lua`: SDK versions, toolkit id `com.knobdeck.lightroom`, `VERSION` (the release version).
  - `Init.lua` / `Shutdown.lua`: start and stop the link (`LrForceInitPlugin`, so it starts with
    Lightroom).
  - `Bridge.lua`: the two `LrSocket` ports, pairing, the poll loop that sends module / photo /
    value changes.
  - `Commands.lua`: what each command does, with the SDK only (never key events).
  - `Protocol.lua`: line encoding; pure Lua.
  - `PluginInfo.lua`: the Plug-in Manager section.
- `tests/fake_lr.lua`: a fake Lightroom (the `Lr*` namespaces the plug-in imports) over a plain
  world table. `test_*.lua` are the unit tests (`run.lua` runs them).
- `tests/stdio_host.lua` runs the real plug-in in the fake Lightroom with its sockets on stdio;
  `tests/lrsocket_bridge.py` puts those on real TCP ports the way LrSocket does;
  `tests/e2e_plugin.py` plays KnobDeck between the real Rust plugin and the plug-in.
- `tools/build.py`: builds `dist/KnobDeck.lrplugin.zip`.

## Build and test

Lua 5.1 (`lua5.1`, or `luajit`) and Python 3.9+:

```sh
for f in KnobDeck.lrplugin/*.lua tests/*.lua; do luac5.1 -p "$f"; done
lua5.1 tests/run.lua
luajit tests/run.lua
python3 tools/build.py

# with the real plugin: cargo build -p lightroom-classic in knobdeck-plugins
python3 tests/e2e_plugin.py ../knobdeck-plugins/target/debug/lightroom-classic
```

To try it in Lightroom: **File ▸ Plug-in Manager ▸ Add** this repo's `KnobDeck.lrplugin` folder,
and **Reload Plug-in** after each change. The fake Lightroom follows the SDK documentation, not
Lightroom itself: check new commands in a real Lightroom Classic before releasing them.

CI (`.github/workflows/ci.yml`) syntax-checks the Lua, runs the unit tests on Lua 5.1 and LuaJIT,
builds the zip, and runs the end-to-end test with the `lightroom-classic` plugin built from
knobdeck-plugins master.

## Releasing

Bump `VERSION` in `KnobDeck.lrplugin/Info.lua`, add a `CHANGELOG.md` entry, merge to `master`.
The Release workflow (`.github/workflows/release.yml`) runs CI and, when the version has no
release yet, creates the tag `v<version>` and a GitHub release with `KnobDeck.lrplugin.zip` (the
fixed name KnobDeck's setup downloads from `releases/latest/download/`). A push that doesn't bump
the version only runs CI.

Not done yet: an Adobe Exchange listing (needs an Adobe developer account; Lightroom Classic
plug-ins don't need one to install).
