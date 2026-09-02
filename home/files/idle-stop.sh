#!/bin/bash
# Backstop for when tv-off-hook.sh cannot fire.
#
# tv-off-hook.sh depends on the TV dropping the HDMI link when powered off.
# tv-connected documents that as a hardware assumption rather than a guarantee,
# and on 2026-08-09 it stopped holding: with the TV off, the connector still
# reads status=connected, dpms=On, enabled, with a full 256-byte EDID. There is
# no software-visible difference between the TV being on and off any more, and
# this box has no /dev/cec* node to ask over CEC either. The panel profile never
# applies, the hook never runs, and Stremio sat on the playback screen for nine
# days pegging a core — 100% CPU, package at 85 C.
#
# So this stops Stremio on *idleness* instead, which needs no cooperation from
# the TV. It does not replace the HDMI hook: that stays as the fast path (60s)
# for when the link does drop. This is the slow path for when it does not.
#
# Idle comes from swayidle over the compositor's seat, deliberately NOT from
# /dev/input. VNC arrives through the virtual-pointer and virtual-keyboard
# Wayland protocols, which never touch evdev, so an evdev-based timer would not
# see someone driving the box over VNC and would kill Stremio underneath them.
# Cage exposes wlr_idle_notifier_v1, and swayidle sees both real and virtual
# input through it. Verified: no phantom activity over 65s of genuine idle, so
# this does not flap.

FLAG="${XDG_RUNTIME_DIR:-/tmp}/kiosk-idle-stop"
LOCK="${XDG_RUNTIME_DIR:-/tmp}/idle-stop.lock"
SERVER="http://127.0.0.1:11470/stats.json"
SPLASH="$HOME/.local/share/kiosk-idle.png"

# Set so the script also works when invoked by hand over ssh, not just from
# swayidle inside the session (which would inherit it).
export WAYLAND_DISPLAY="${WAYLAND_DISPLAY:-wayland-0}"

# A stopped Stremio leaves a black screen with no explanation, which reads as a
# broken box. Show a still telling whoever turned the TV on what to do.
#
# It has to be a normal xdg-shell client: Cage implements no layer-shell, so
# swaybg and the other wallpaper daemons cannot attach at all. imv is fine as
# the sole surface here precisely because Stremio has just been killed — Cage
# shows one client, and this is it until the kiosk loop starts Stremio again.
show_splash() {
	pkill -x imv-wayland 2>/dev/null
	[ -f "$SPLASH" ] || python3 "$HOME/bin/make-idle-splash.py" >/dev/null 2>&1
	setsid imv-wayland -f "$SPLASH" >/dev/null 2>&1 &
}

hide_splash() {
	pkill -x imv-wayland 2>/dev/null
	# Nudge the pointer into a corner after handing the display back.
	#
	# Cage draws the default arrow until a client sets its own cursor, and a
	# client only does that when it receives a pointer event. Stremio hides the
	# cursor during playback with cursor:none, but the remote sends clicks and
	# key presses through uinput and no pointer *motion* — so once something
	# else has held the surface (imv here), nothing ever prompts Stremio to
	# re-apply it and the arrow sits on top of the film indefinitely.
	#
	# Motion only, never a click: a click here would toggle playback.
	"$HOME/bin/move-pointer.py" 1534 862 >/dev/null 2>&1 || true
}

# swayidle's `resume` runs this on any seat activity — and also once when
# swayidle itself exits, which is why a session restart clears the flag rather
# than leaving Stremio suppressed until someone presses a button.
if [ "$1" = "--clear" ]; then
	# Take the splash down BEFORE clearing the flag. The kiosk loop polls every
	# 3s, so clearing first would race it into starting Stremio while imv still
	# holds a surface, and Cage would have two toplevels fighting over the TV.
	hide_splash
	if [ -e "$FLAG" ]; then
		rm -f "$FLAG"
		logger -t idle-stop "activity — inhibit cleared, kiosk loop may start Stremio"
	fi
	exit 0
fi

exec 9>"$LOCK"
flock -n 9 || exit 0

# Decide on the state of the world *now*, not on the edge that woke us — the
# same reason tv-off-hook.sh re-reads rather than latching.
#
# An open stream keeps an entry in the streaming server's stats. Treat it as
# in-use only when something is actually moving (peers or download speed): the
# entries linger for stalled torrents that never connected a single peer, and
# those are exactly the dead swarms the whole Comet setup is fighting, so a
# stale entry must not be allowed to inhibit this forever.
#
# An unreachable server counts as NOT playing, on purpose. If the streaming
# server has died, Stremio is wedged, and wedged is precisely the state worth
# restarting out of.
active=$(python3 - "$SERVER" <<'PY' 2>/dev/null || echo no
import json, sys, urllib.request
try:
    d = json.load(urllib.request.urlopen(sys.argv[1], timeout=5))
except Exception:
    print("no")           # server down -> Stremio is wedged -> let it be stopped
    sys.exit()
for v in (d or {}).values():
    if (v.get("downloadSpeed") or 0) > 0 or (v.get("peers") or 0) > 0:
        print("yes")
        break
else:
    print("no")
PY
)

if [ "$active" = "yes" ]; then
	logger -t idle-stop "idle, but a stream is still moving — leaving Stremio running"
	exit 0
fi

# Set the inhibit before killing. The kiosk loop polls every few seconds and
# gates on this file as well as tv-connected; without it the loop would simply
# start Stremio again on its next pass and nothing would ever be saved.
: >"$FLAG"
logger -t idle-stop "idle with nothing playing — stopping Stremio"

# Already stopped is the target state, not a failure.
flatpak kill com.stremio.Stremio 2>/dev/null || true

# Only after Stremio is gone, so imv is the sole surface Cage has to show.
show_splash
