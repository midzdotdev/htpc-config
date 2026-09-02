#!/usr/bin/env python3
"""Repair Unified Remote's tap clicks under Wayland.

urserver emits a tap as BTN_* down *and* up inside a single evdev frame: both
carry an identical timestamp and there is no SYN_REPORT between them. libinput
coalesces that frame to a no-op, so taps from the phone do nothing at all,
while hold-to-drag works because holding necessarily straddles two frames.
Captured from urserver 3.14.0.2574:

    1785005165.154258 EV_KEY BTN_LEFT   v=1
    1785005165.154258 EV_KEY BTN_LEFT   v=0     <- same frame, no SYN between
    1785005165.154258 EV_SYN SYN_REPORT v=0

urserver is closed source, and upstream's answer to Wayland is "use X11"
(help.unifiedremote.com/article/89) which is not available here: X11 is what
breaks Stremio v5's WebView. So instead of grabbing and proxying the whole
device, this watches it read-only and replays any same-frame click as a
properly framed one on its own uinput device. The original frame is a genuine
no-op, so replaying it cannot produce a double click.

Motion, scrolling and keystrokes are untouched — they already work, and are
left to flow through urserver's own device.

Two traps if you ever drive this box's UI from a synthetic device — there is no
keyboard or mouse attached, so sooner or later someone will:

* Relative motion cannot target anything precisely. libinput applies pointer
  acceleration, so the delta you emit is not the delta applied, and "move to
  0,0 then move x,y" lands somewhere else entirely. Register an absolute device
  instead (ABS_X/ABS_Y + INPUT_PROP_DIRECT), which libinput maps 1:1 onto the
  output.
* The kernel silently discards events for any key code not declared with
  UI_SET_KEYBIT before UI_DEV_CREATE. A device that declares a handful of keys
  types only those characters and drops the rest, with no error from the write,
  no error in the compositor, and nothing in any log — it just looks as though
  most of your keystrokes vanished.
"""

import fcntl
import os
import re
import struct
import sys
import time

UI_SET_EVBIT, UI_SET_KEYBIT, UI_SET_RELBIT = 0x40045564, 0x40045565, 0x40045566
UI_DEV_CREATE, UI_DEV_DESTROY = 0x5501, 0x5502
EV_SYN, EV_KEY, EV_REL = 0, 1, 2
SYN_REPORT, REL_X, REL_Y = 0, 0, 1
BUTTONS = {0x110: "BTN_LEFT", 0x111: "BTN_RIGHT", 0x112: "BTN_MIDDLE"}

EVENT_FMT = "llHHi"
EVENT_SIZE = struct.calcsize(EVENT_FMT)

# Long enough for GTK/WebKit to see a distinct press and release, short enough
# that it still feels like a tap rather than a drag.
DWELL = 0.030

WATCH_NAME = sys.argv[1] if len(sys.argv) > 1 else "uinput-unifiedremote"


def log(msg):
    print("%s urclick-fix: %s" % (time.strftime("%H:%M:%S"), msg), flush=True)


def find_device(name):
    """Resolve a device's event node by its advertised name."""
    try:
        with open("/proc/bus/input/devices") as fh:
            blocks = fh.read().split("\n\n")
    except OSError:
        return None
    for block in blocks:
        if 'Name="%s"' % name in block:
            match = re.search(r"(event\d+)", block)
            if match:
                return "/dev/input/" + match.group(1)
    return None


def make_emitter():
    """A pointer device we own, used only to replay clicks."""
    fd = os.open("/dev/uinput", os.O_WRONLY | os.O_NONBLOCK)
    for ev in (EV_KEY, EV_REL, EV_SYN):
        fcntl.ioctl(fd, UI_SET_EVBIT, ev)
    for btn in BUTTONS:
        fcntl.ioctl(fd, UI_SET_KEYBIT, btn)
    # REL_X/REL_Y are declared but never emitted: libinput needs relative axes
    # to classify this as a pointer, and a buttons-only device is ignored.
    for rel in (REL_X, REL_Y):
        fcntl.ioctl(fd, UI_SET_RELBIT, rel)
    setup = struct.pack("80sHHHHI", b"urclick-fix", 0x03, 0x1D6B, 0x0001, 1, 0)
    os.write(fd, setup + b"\x00" * 1024)
    fcntl.ioctl(fd, UI_DEV_CREATE)
    return fd


def replay(fd, button):
    def emit(t, c, v):
        os.write(fd, struct.pack(EVENT_FMT, 0, 0, t, c, v))

    emit(EV_KEY, button, 1)
    emit(EV_SYN, SYN_REPORT, 0)
    time.sleep(DWELL)
    emit(EV_KEY, button, 0)
    emit(EV_SYN, SYN_REPORT, 0)


def watch(path, emitter):
    """Read frames until the device goes away, replaying collapsed clicks."""
    frame = []
    with open(path, "rb", buffering=0) as src:
        while True:
            data = src.read(EVENT_SIZE)
            if not data or len(data) < EVENT_SIZE:
                return
            _, _, etype, code, value = struct.unpack(EVENT_FMT, data)
            if etype == EV_SYN and code == SYN_REPORT:
                # A button that goes down *and* up inside one frame is the bug.
                for button in BUTTONS:
                    if (button, 1) in frame and (button, 0) in frame:
                        replay(emitter, button)
                        log("replayed %s" % BUTTONS[button])
                frame = []
            elif etype == EV_KEY and code in BUTTONS:
                frame.append((code, value))
            elif len(frame) > 64:
                frame = []  # runaway frame, should not happen


def main():
    emitter = make_emitter()
    log("watching for %r, emitting as 'urclick-fix'" % WATCH_NAME)
    current = None
    try:
        while True:
            path = find_device(WATCH_NAME)
            if path is None:
                current = None
                time.sleep(2)
                continue
            if path != current:
                log("attached to %s" % path)
                current = path
            try:
                watch(path, emitter)
            except OSError as exc:
                log("read ended (%s), will re-attach" % exc)
            current = None
            time.sleep(1)
    finally:
        fcntl.ioctl(emitter, UI_DEV_DESTROY)
        os.close(emitter)


if __name__ == "__main__":
    main()
