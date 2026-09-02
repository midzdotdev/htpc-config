#!/usr/bin/env python3
"""Move the pointer without clicking.

ui.py's `tap` presses BTN_TOUCH, which would toggle playback. This emits
absolute motion only, so the compositor and the focused client see a pointer
move and nothing else — enough for an app to re-apply its own cursor policy.
"""
import fcntl
import os
import struct
import sys
import time

UI_SET_EVBIT, UI_SET_KEYBIT = 0x40045564, 0x40045565
UI_SET_ABSBIT, UI_SET_PROPBIT = 0x40045567, 0x4004556E
UI_DEV_CREATE, UI_DEV_DESTROY = 0x5501, 0x5502
EV_SYN, EV_KEY, EV_ABS = 0, 1, 3
SYN_REPORT, ABS_X, ABS_Y = 0, 0, 1
BTN_TOUCH, INPUT_PROP_DIRECT = 0x14A, 0x01
W, H = 1536, 864

x = int(sys.argv[1]) if len(sys.argv) > 1 else W - 2
y = int(sys.argv[2]) if len(sys.argv) > 2 else H - 2

fd = os.open("/dev/uinput", os.O_WRONLY | os.O_NONBLOCK)
for ev in (EV_KEY, EV_ABS, EV_SYN):
    fcntl.ioctl(fd, UI_SET_EVBIT, ev)
fcntl.ioctl(fd, UI_SET_KEYBIT, BTN_TOUCH)
for axis in (ABS_X, ABS_Y):
    fcntl.ioctl(fd, UI_SET_ABSBIT, axis)
fcntl.ioctl(fd, UI_SET_PROPBIT, INPUT_PROP_DIRECT)
absmax = [0] * 64
absmax[ABS_X], absmax[ABS_Y] = W - 1, H - 1
os.write(fd, struct.pack("80sHHHHI", b"pointer-nudge", 3, 0xC1AD, 4, 1, 0)
         + struct.pack("64i", *absmax) + struct.pack("64i", *([0] * 64)) * 3)
fcntl.ioctl(fd, UI_DEV_CREATE)
time.sleep(2.0)


def emit(t, c, v):
    os.write(fd, struct.pack("llHHi", 0, 0, t, c, v))


# a couple of distinct positions so it reads as real movement, never a click
for pos in ((x - 40, y - 40), (x, y)):
    emit(EV_ABS, ABS_X, max(0, pos[0]))
    emit(EV_ABS, ABS_Y, max(0, pos[1]))
    emit(EV_SYN, SYN_REPORT, 0)
    time.sleep(0.25)

time.sleep(0.5)
fcntl.ioctl(fd, UI_DEV_DESTROY)
os.close(fd)
print(f"pointer moved to ({x}, {y}) with no click")
