"""Build dist/KnobDeck.lrplugin.zip (the folder KnobDeck.lrplugin/ and nothing else) and print the
version from KnobDeck.lrplugin/Info.lua.

    python3 tools/build.py            # builds, prints the version
    python3 tools/build.py --version  # only prints it
"""

import os
import re
import sys
import zipfile

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
PLUGIN = "KnobDeck.lrplugin"


def version():
    info = open(os.path.join(ROOT, PLUGIN, "Info.lua"), encoding="utf-8").read()
    m = re.search(r"VERSION\s*=\s*\{\s*major\s*=\s*(\d+),\s*minor\s*=\s*(\d+),\s*revision\s*=\s*(\d+)", info)
    if not m:
        sys.exit("Info.lua has no VERSION = { major = .., minor = .., revision = .. }")
    return ".".join(m.groups())


def build():
    os.makedirs(os.path.join(ROOT, "dist"), exist_ok=True)
    out = os.path.join(ROOT, "dist", f"{PLUGIN}.zip")
    with zipfile.ZipFile(out, "w", zipfile.ZIP_DEFLATED) as z:
        for name in sorted(os.listdir(os.path.join(ROOT, PLUGIN))):
            path = os.path.join(ROOT, PLUGIN, name)
            if os.path.isfile(path) and not name.startswith("."):
                z.write(path, f"{PLUGIN}/{name}")
    return out


if __name__ == "__main__":
    if sys.argv[1:] == ["--version"]:
        print(version())
    else:
        print(build(), version(), file=sys.stderr)
        print(version())
