"""End to end: the real KnobDeck `lightroom-classic` plugin (from Knobdeck/knobdeck-plugins) and this
plug-in's real Lua code in the fake Lightroom, joined over TCP the way LrSocket joins them
(tests/lrsocket_bridge.py). This script plays KnobDeck: it speaks the plugin's stdio protocol
(hello, ready, sync, invoke) and checks what the keys show.

    python3 tests/e2e_plugin.py <plugin exe>

Lightroom itself is not involved: the fake answers as the SDK documents. LUA picks the interpreter
(default lua5.1, the Lua of Lightroom Classic).
"""

import json
import os
import subprocess
import sys
import tempfile
import threading
import time

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)

from lrsocket_bridge import LrSocketBridge  # noqa: E402

TOKEN = "e2e-token-0123456789abcdef"


class Plugin:
    def __init__(self, exe, env):
        meta = json.loads(subprocess.run([exe], env={**os.environ, "KNOBDECK_CODEGEN": "1"}, capture_output=True, check=True).stdout)
        self.id = meta["manifest"]["id"]
        # short id -> full id: "<manifest id>-<short>-<8 hex>"
        self.ids = {a["id"][len(self.id) + 1 : -9]: a["id"] for a in meta["actions"]["actions"]}
        self.data = tempfile.mkdtemp(prefix="kd-plugin-")
        self.proc = subprocess.Popen(
            [exe],
            stdin=subprocess.PIPE,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
            bufsize=1,
            env={**os.environ, **env, "KNOBDECK_PLUGIN_DATA": self.data},
        )
        self.frames, self.waiters, self.lock = [], {}, threading.Lock()
        self.ready = threading.Event()
        self.seq = 0
        threading.Thread(target=self._read, daemon=True).start()
        threading.Thread(target=lambda: [None for _ in self.proc.stderr], daemon=True).start()

    def send(self, msg):
        with self.lock:
            self.proc.stdin.write(json.dumps(msg) + "\n")
            self.proc.stdin.flush()

    def _read(self):
        for line in self.proc.stdout:
            f = json.loads(line)  # a non-JSON line fails the run
            self.frames.append(f)
            t = f.get("type")
            if t == "ready":
                self.ready.set()
            elif t == "host_call":
                self.send({"type": "result", "id": f["id"], "ok": False, "error": f"{f['method']} is not available here"})
            if t in ("done", "result") and f.get("id") in self.waiters:
                self.waiters.pop(f["id"]).append(f)

    def hello(self, instances):
        self.send(
            {
                "type": "hello",
                "protocol": 2,
                "plugin_id": self.id,
                "data_dir": self.data,
                "host_version": "e2e",
                "features": ["state_match", "events", "notify", "app_state"],
                "host_pid": os.getpid(),
            }
        )
        assert self.ready.wait(10), "plugin sent no ready"
        self.instances = instances
        self.send(
            {
                "type": "sync",
                "instances": [{"instance_id": i, "action_id": self.ids[a], "inputs": inputs} for i, (a, inputs) in instances.items()],
            }
        )

    def invoke(self, instance, trigger="press", **extra):
        action, inputs = self.instances[instance]
        self.seq += 1
        fid = f"i{self.seq}"
        start = len(self.frames)
        self.waiters[fid] = box = []
        self.send(
            {
                "type": "invoke",
                "id": fid,
                "instance_id": instance,
                "action_id": self.ids[action],
                "trigger": trigger,
                "inputs": {**inputs, **extra},
            }
        )
        end = time.monotonic() + 15
        while not box and time.monotonic() < end:
            time.sleep(0.01)
        assert box, f"no done for {instance}"
        return [f["message"] for f in self.frames[start:] if f.get("type") == "error" and f.get("instance_id") == instance]

    def shown(self, instance):
        """The latest state and label pushed for an instance (directly or for its whole action)."""
        action = self.ids[self.instances[instance][0]]
        state = label = None
        for f in self.frames:
            if f.get("type") != "state":
                continue
            if f.get("instance_id") == instance or f.get("action_id") == action:
                state = f.get("state", state)
                label = f.get("label", label)
        return state, label

    def wait_shown(self, instance, state=None, label=None, timeout=10):
        end = time.monotonic() + timeout
        while time.monotonic() < end:
            s, lab = self.shown(instance)
            if (state is None or s == state) and (label is None or (lab or "").startswith(label)):
                return
            time.sleep(0.05)
        raise AssertionError(f"{instance}: shows {self.shown(instance)}, wanted state={state!r} label={label!r}")

    def stop(self):
        self.send({"type": "shutdown"})
        try:
            self.proc.wait(timeout=5)
        except subprocess.TimeoutExpired:
            self.proc.kill()


def main(exe):
    lr = LrSocketBridge()
    kd = Plugin(
        exe,
        {"LIGHTROOM_COMMAND_PORT": str(lr.command_port), "LIGHTROOM_EVENT_PORT": str(lr.event_port), "LIGHTROOM_TOKEN": TOKEN},
    )
    ok = False
    try:
        kd.hello(
            {
                "exp": ("exposure", {"steps": "fine", "reveal": True}),
                "tint": ("develop-slider", {"param": "Tint", "steps": "fine", "step": "5", "reveal": True}),
                "contrast-lr": ("contrast", {"steps": "lightroom", "reveal": False}),
                "flag": ("flag", {"flag": "pick"}),
                "rating": ("rating", {"rating": "4"}),
                "rdial": ("rating-dial", {}),
                "blue": ("color-label", {"label": "blue"}),
                "lib": ("module", {"module": "library"}),
                "status": ("status", {}),
                "next": ("next-photo", {}),
                "copy": ("copy-settings", {}),
                "paste": ("paste-settings", {}),
                "view": ("develop-view", {"view": "toggle"}),
                "tool": ("develop-tool", {"tool": "crop"}),
                "panel": ("show-panel", {"panel": "detailPanel"}),
                "auto": ("auto-tone", {}),
                "rotate": ("rotate-right", {}),
                "undo": ("undo", {}),
                "redo": ("redo", {}),
            }
        )
        # Pairing: the plug-in asks (the fake user allows), then KnobDeck says hello again.
        kd.wait_shown("status", label="Develop\nIMG_0001.CR3")
        print("linked; status:", kd.shown("status"))

        assert kd.invoke("exp", "adjust", delta=3) == []
        kd.wait_shown("exp", state="0.15")
        assert kd.invoke("tint", "adjust", value=40) == []
        kd.wait_shown("tint", state="40", label="Tint")
        assert kd.invoke("tint", "adjust", delta=-2) == []
        kd.wait_shown("tint", state="30")
        assert kd.invoke("contrast-lr", "adjust", delta=1) == []
        kd.wait_shown("contrast-lr", state="10")  # Lightroom's own (fake) increment: range / 20
        assert kd.invoke("exp") == []  # press resets
        kd.wait_shown("exp", state="0")
        print("dials ok")

        assert kd.invoke("flag") == []
        kd.wait_shown("flag", state="pick")
        assert kd.invoke("flag") == []
        kd.wait_shown("flag", state="none")
        assert kd.invoke("rating") == []
        kd.wait_shown("rating", label="★★★★☆")
        assert kd.invoke("rdial", "adjust", delta=1) == []
        kd.wait_shown("rdial", state="5")
        assert kd.invoke("blue") == []
        kd.wait_shown("blue", state="on")
        print("flags, ratings, labels ok")

        for key in ("copy", "view", "tool", "panel", "auto", "rotate", "undo"):
            errors = kd.invoke(key)
            assert errors == [], f"{key}: {errors}"
        assert kd.invoke("redo") == ["Nothing to redo"], "redo with nothing to redo"
        kd.wait_shown("copy", label="Copied\nIMG_0001.CR3")
        assert kd.invoke("next") == []
        kd.wait_shown("status", label="Develop\nIMG_0002.CR3")
        assert kd.invoke("paste") == []
        kd.wait_shown("paste", label="Pasted")
        assert kd.invoke("lib") == []
        kd.wait_shown("lib", state="on")
        kd.wait_shown("status", label="Library\nIMG_0002.CR3")
        print("keys ok")

        # The user works in Lightroom: values and the photo follow on the keys.
        lr.world("world.module = 'develop'; world.photos[2].develop.Exposure = 1.25; for _, o in ipairs(world.observers) do o() end")
        kd.wait_shown("exp", state="1.25")
        kd.wait_shown("lib", state="off")
        lr.world("world.photos[2].rating = 2")
        kd.wait_shown("rating", label="★★☆☆☆")
        print("live values ok")

        # The Allow dialog came once: the first hello waited, the next was accepted.
        assert lr.sent[0].startswith("R\t") and lr.sent[0].endswith("\terr\tpending"), lr.sent[0]
        assert lr.sent[1] == "E\tpaired", lr.sent[1]

        lr.quit()
        kd.wait_shown("status", label="Lightroom offline")
        errors = kd.invoke("undo")
        assert errors and "isn't linked" in errors[0], errors
        print("offline ok")
        ok = True
    finally:
        kd.stop()
        if lr.alive:
            lr.close()
        if not ok:
            print("--- KnobDeck got:", *[json.dumps(f, ensure_ascii=False) for f in kd.frames[-25:]], sep="\n  ")
            print("--- plug-in sent:", *lr.sent[-30:], sep="\n  ")
            print("--- notes:", *lr.notes, sep="\n  ")
    print("e2e: all good")


if __name__ == "__main__":
    if len(sys.argv) != 2:
        sys.exit("usage: python3 tests/e2e_plugin.py <lightroom-classic plugin exe>")
    main(sys.argv[1])
