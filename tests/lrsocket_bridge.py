"""The real plug-in's two LrSockets on real TCP ports, without Lightroom.

Runs tests/stdio_host.lua (the plug-in in the fake Lightroom) and plays LrSocket for it: listens on
127.0.0.1 on a command port (lines in) and an event port (lines out), one client each at a time,
as LrSocket does. Used by e2e_plugin.py; also handy by hand:

    python3 tests/lrsocket_bridge.py 58770 58771
"""

import os
import socket
import subprocess
import sys
import threading
import time

HERE = os.path.dirname(os.path.abspath(__file__))


def free_port():
    with socket.socket() as s:
        s.bind(("127.0.0.1", 0))
        return s.getsockname()[1]


class LrSocketBridge:
    def __init__(self, command_port=0, event_port=0, lua=None):
        lua = lua or os.environ.get("LUA", "lua5.1")
        self.proc = subprocess.Popen(
            [lua, os.path.join(HERE, "stdio_host.lua")],
            stdin=subprocess.PIPE,
            stdout=subprocess.PIPE,
            text=True,
            bufsize=1,
        )
        self.lock = threading.Lock()
        self.event_conn = None
        self.sent = []  # lines the plug-in sent
        self.notes = []
        self.cmd = self._listen(command_port)
        self.evt = self._listen(event_port)
        self.command_port = self.cmd.getsockname()[1]
        self.event_port = self.evt.getsockname()[1]
        self.alive = True
        for target in (self._read_lua, self._serve_commands, self._serve_events, self._tick):
            threading.Thread(target=target, daemon=True).start()

    @staticmethod
    def _listen(port):
        s = socket.socket()
        s.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
        s.bind(("127.0.0.1", port))
        s.listen(1)
        return s

    def to_lua(self, line):
        with self.lock:
            if self.proc.poll() is None:
                self.proc.stdin.write(line + "\n")
                self.proc.stdin.flush()

    def world(self, lua):
        """Change Lightroom's state as its user would (one line of Lua with `world`)."""
        self.to_lua("W " + lua)

    def _read_lua(self):
        for line in self.proc.stdout:
            line = line.rstrip("\n")
            if line.startswith("S "):
                self.sent.append(line[2:])
                conn = self.event_conn
                if conn is not None:
                    try:
                        conn.sendall((line[2:] + "\n").encode())
                    except OSError:
                        pass
            elif line == "K send":
                conn = self.event_conn
                if conn is not None:
                    try:
                        conn.shutdown(socket.SHUT_RDWR)
                    except OSError:
                        pass
            elif line.startswith("L "):
                self.notes.append(line[2:])
                print("[lua]", line[2:], file=sys.stderr)

    def _serve_commands(self):
        while self.alive:
            try:
                conn, _ = self.cmd.accept()
            except OSError:
                return
            self.to_lua("O receive")
            buf = b""
            while True:
                try:
                    data = conn.recv(65536)
                except OSError:
                    data = b""
                if not data:
                    break
                buf += data
                while b"\n" in buf:
                    line, buf = buf.split(b"\n", 1)
                    self.to_lua("C " + line.decode())
            conn.close()
            self.to_lua("X receive")

    def _serve_events(self):
        while self.alive:
            try:
                conn, _ = self.evt.accept()
            except OSError:
                return
            self.event_conn = conn
            self.to_lua("O send")
            try:
                while conn.recv(1024):
                    pass
            except OSError:
                pass
            if self.event_conn is conn:
                self.event_conn = None
            conn.close()
            self.to_lua("X send")

    def _tick(self):
        while self.alive and self.proc.poll() is None:
            self.to_lua("T")
            time.sleep(0.1)

    def quit(self):
        """Lightroom quits: Shutdown.lua runs, then both sockets close."""
        self.to_lua("Q")
        time.sleep(0.3)
        self.close()

    def close(self):
        self.alive = False
        for s in (self.cmd, self.evt):
            s.close()
        if self.event_conn is not None:
            try:
                self.event_conn.shutdown(socket.SHUT_RDWR)
            except OSError:
                pass
        try:
            self.proc.stdin.close()
        except OSError:
            pass
        self.proc.wait(timeout=5)


if __name__ == "__main__":
    ports = [int(p) for p in sys.argv[1:3]] or [58770, 58771]
    b = LrSocketBridge(*ports)
    print(f"plug-in listening on {b.command_port} (commands) / {b.event_port} (events); Ctrl+C stops")
    try:
        while True:
            time.sleep(1)
    except KeyboardInterrupt:
        b.close()
