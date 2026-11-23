#!/usr/bin/env python3
"""QEMU harness for FUNForth.

Boots kernel.img on a QEMU raspi machine, pipes a FORTH script over the serial
console (PL011 -> stdio), captures the transcript, and optionally diffs it
against a golden file (make test).

Locating QEMU, in order: $QEMU_SYSTEM_ARM, PATH, ~/qemu-root (local deb
extraction with LD_LIBRARY_PATH set).
"""
import argparse
import difflib
import os
import select
import shutil
import socket
import subprocess
import sys
import tempfile
import time


def find_qemu():
    env = os.environ.get("QEMU_SYSTEM_ARM")
    if env and os.path.exists(env):
        return [env], None
    w = shutil.which("qemu-system-arm")
    if w:
        return [w], None
    root = os.path.expanduser("~/qemu-root")
    p = os.path.join(root, "usr/bin/qemu-system-arm")
    if os.path.exists(p):
        libs = [os.path.join(root, "usr/lib/x86_64-linux-gnu"),
                os.path.join(root, "lib/x86_64-linux-gnu")]
        env = dict(os.environ)
        env["LD_LIBRARY_PATH"] = ":".join(libs + [env.get("LD_LIBRARY_PATH", "")])
        return [p], env
    sys.exit("error: qemu-system-arm not found (set QEMU_SYSTEM_ARM)")


def norm(s):
    return s.replace("\r\n", "\n").replace("\r", "\n").rstrip()


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--kernel", required=True)
    ap.add_argument("--machine", default="raspi0")
    ap.add_argument("--script", help="FORTH script piped over the serial console")
    ap.add_argument("--expected", help="golden transcript to diff against")
    ap.add_argument("--run", action="store_true", help="interactive run (stdio passthrough)")
    ap.add_argument("--wait-for", default="", help="wait for this marker before sending the script")
    ap.add_argument("--timeout", type=float, default=10.0, help="max seconds to capture")
    ap.add_argument("--idle", type=float, default=2.0, help="stop after this many idle seconds")
    args = ap.parse_args()

    cmd, env = find_qemu()
    if args.run:
        cmd += ["-M", args.machine, "-kernel", args.kernel,
                "-serial", "stdio", "-display", "none", "-monitor", "none"]
        os.execvpe(cmd[0], cmd, env or os.environ)

    # serial via a unix socket (stdio chardev misbehaves with piped stdin)
    sock_path = os.path.join(tempfile.mkdtemp(prefix="funforth-"), "serial.sock")
    cmd += ["-M", args.machine, "-kernel", args.kernel,
            "-serial", "unix:%s,server" % sock_path,
            "-display", "none", "-monitor", "none"]

    script = b""
    if args.script and os.path.exists(args.script):
        with open(args.script, "rb") as f:
            script = f.read()

    p = subprocess.Popen(cmd, stdin=subprocess.DEVNULL, stdout=subprocess.DEVNULL,
                         stderr=subprocess.PIPE, env=env)

    ser = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
    deadline = time.time() + 5
    while True:
        try:
            ser.connect(sock_path)
            break
        except OSError:
            if time.time() > deadline or p.poll() is not None:
                sys.exit("error: cannot connect to QEMU serial socket")
            time.sleep(0.05)

    out = b""
    start = last = time.time()

    def pump(duration):
        nonlocal out, last
        end = time.time() + duration
        while time.time() < end:
            r, _, _ = select.select([ser], [], [], 0.1)
            if r:
                chunk = ser.recv(4096)
                if not chunk:
                    return False
                out += chunk
                last = time.time()
            if p.poll() is not None:
                return False
        return True

    if script and args.wait_for:
        marker = args.wait_for.encode()
        while marker not in out:
            if not pump(0.2) or time.time() - start > args.timeout:
                break
    if script:
        ser.sendall(script)

    while True:
        if not pump(0.2):
            break
        if time.time() - start > 1.0 and time.time() - last > args.idle:
            break
        if time.time() - start > args.timeout:
            break
    p.terminate()
    try:
        p.wait(timeout=3)
    except subprocess.TimeoutExpired:
        p.kill()
    ser.close()
    transcript = out.decode("utf-8", "replace")

    if args.expected:
        with open(args.expected, encoding="utf-8") as f:
            expected = norm(f.read())
        got = norm(transcript)
        if got == expected:
            print("PASS: transcript matches %s" % args.expected)
            return 0
        print("FAIL: transcript mismatch (expected vs got)")
        for line in difflib.unified_diff(expected.splitlines(), got.splitlines(),
                                         "expected", "got", lineterm=""):
            print(line)
        return 1
    sys.stdout.write(transcript)
    return 0


if __name__ == "__main__":
    sys.exit(main())
