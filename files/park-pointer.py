#!/usr/bin/env python3
"""Park the pointer in the bottom-right corner, without clicking.

The AirPlay window (GStreamer's glimagesink) never sets a cursor of its own,
and Cage has no hide-cursor option, so whatever cursor was last drawn stays on
top of the video. A cursor parked in the corner shows one pixel of its tip.

Relative motion from a throwaway uinput mouse: Cage clamps the pointer to the
screen, so overshooting lands exactly in the corner at any resolution or scale.
Adding and removing the device also makes Cage fall back to its default arrow,
whose hotspot is its tip, which is what leaves only that one pixel visible.
"""
import fcntl
import os
import struct
import sys
import time

UI_SET_EVBIT, UI_SET_KEYBIT, UI_SET_RELBIT = 0x40045564, 0x40045565, 0x40045566
UI_DEV_CREATE, UI_DEV_DESTROY = 0x5501, 0x5502
EV_SYN, EV_KEY, EV_REL = 0, 1, 2
SYN_REPORT, REL_X, REL_Y, BTN_LEFT = 0, 0, 1, 0x110

fd = os.open("/dev/uinput", os.O_WRONLY | os.O_NONBLOCK)
for ev in (EV_KEY, EV_REL, EV_SYN):
    fcntl.ioctl(fd, UI_SET_EVBIT, ev)
# libinput only treats a relative device as a mouse if it has a button
fcntl.ioctl(fd, UI_SET_KEYBIT, BTN_LEFT)
for axis in (REL_X, REL_Y):
    fcntl.ioctl(fd, UI_SET_RELBIT, axis)
os.write(fd, struct.pack("80sHHHHI", b"pointer-park", 3, 0xC1AD, 5, 1, 0)
         + struct.pack("64i", *([0] * 64)) * 4)
fcntl.ioctl(fd, UI_DEV_CREATE)
time.sleep(1.0)  # let libinput and the compositor pick the device up


def emit(t, c, v):
    os.write(fd, struct.pack("llHHi", 0, 0, t, c, v))


# optional "dx dy" per step, only so the parking can be undone when testing
dx, dy = (int(sys.argv[1]), int(sys.argv[2])) if len(sys.argv) > 2 else (200, 200)
for _ in range(40):
    emit(EV_REL, REL_X, dx)
    emit(EV_REL, REL_Y, dy)
    emit(EV_SYN, SYN_REPORT, 0)
    time.sleep(0.01)

time.sleep(0.3)
fcntl.ioctl(fd, UI_DEV_DESTROY)
os.close(fd)
