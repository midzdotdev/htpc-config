#!/bin/bash
# Kiosk session under Cage (Wayland). Stremio v5 (the 1.x shell) fails to
# start its WebView on X11 — "TypeError: undefined is not a function",
# upstream stremio-bugs#2634 — in both the flatpak and native builds, so the
# whole session runs on Wayland instead. Wayland also gives per-output vsync,
# which X11 could not do while both the TV and the laptop panel were active.
#
# Cage runs exactly one client, so this wrapper starts the helpers in the
# background and leaves Stremio in the foreground: when Stremio exits, the
# session ends and the respawn loop in .bash_profile starts a fresh one.
#
# "One client" is about which surface is shown, not about who may connect —
# grim, wlr-randr and kanshi all attach fine. But anything needing *focus* does
# not work here, because focus never leaves Stremio. The clipboard is the one
# that bites: wl-copy can never take the selection, and Cage creates no
# data-control manager either, so wl-paste reads nothing. Do not build anything
# on the Wayland clipboard on this box — it fails silently and returns empty
# rather than erroring.

export XDG_RUNTIME_DIR=${XDG_RUNTIME_DIR:-/run/user/$(id -u)}

# A fresh session must never start suppressed. swayidle clears the idle
# backstop's inhibit on exit, but only if it had actually gone idle first — a
# SIGKILL or a crash skips that, and the flag lives in XDG_RUNTIME_DIR, which
# survives a session restart even though it does not survive a reboot. Without
# this line that leaves the loop below refusing to start Stremio, with a black
# TV and no clue why, until someone happens to press a button.
rm -f "$XDG_RUNTIME_DIR/kiosk-idle-stop"

# Output layout (which outputs are on, and the 125% scale) lives in
# ~/.config/kanshi/config. kanshi rather than a one-shot wlr-randr because the
# TV hotplugs: switching it off or changing its input disconnects HDMI, and
# wlroots then recreates the output with default settings. Cage keeps running
# throughout, so nothing re-ran the old wlr-randr block and the UI silently
# dropped back to 100%. kanshi watches for output changes and re-applies.
(
  while :; do
    kanshi 2>&1 | logger -t kanshi
    sleep 5
  done
) &

# Audio out over HDMI. The profile can read as "unavailable" until the TV's
# ELD arrives, so retry rather than assuming the first attempt sticks.
(
  for _ in $(seq 1 15); do
    pactl set-card-profile alsa_card.pci-0000_00_1f.3 output:hdmi-stereo 2>/dev/null &&
      pactl set-default-sink alsa_output.pci-0000_00_1f.3.hdmi-stereo 2>/dev/null &&
      break
    sleep 1
  done
) &

# Unified Remote — phone as keyboard/D-pad. Injects via /dev/uinput, which is
# kernel-level and needs no display server. Watchdog: it dies silently every
# few days, and its own start script refuses to run while a stale pidfile
# points at any live PID.
(
  while :; do
    if ! ss -tln 2>/dev/null | grep -q ':9512 '; then
      rm -f "$HOME/.urserver/urserver.pid"
      /opt/urserver/urserver-start --no-manager --no-notify >/dev/null 2>&1
    fi
    sleep 30
  done
) &

# urserver emits a tap as BTN_LEFT down+up inside one evdev frame, which
# libinput collapses to nothing: taps do nothing while hold-to-drag works.
# This replays those collapsed clicks properly framed. It re-attaches on its
# own when urserver restarts, so it only needs the outer respawn for crashes.
(
  while :; do
    "$HOME/bin/urclick-fix.py" 2>&1 | logger -t urclick-fix
    sleep 5
  done
) &

# AirPlay receiver. glimagesink, NOT waylandsink -- this was changed back after
# iPhone mirroring was found to be silently broken while a Mac worked fine.
#
# waylandsink hands video to the compositor as wl_shm buffers. An iPhone mirror
# stream produces a geometry wlroots rejects:
#
#     [destroyed object]: error 1: Invalid stride (1496)
#
# A Wayland protocol error is FATAL to the client connection, so that single
# rejected buffer kills waylandsink's link to the compositor for the life of the
# uxplay process. Nothing displays afterwards, and rotating the phone or
# reconnecting does not recover it -- the phone still reports "mirroring" while
# the TV sits on Stremio. A Mac's landscape desktop produces buffers that are
# accepted, which is why only the phone appeared broken.
#
# glimagesink uploads through OpenGL/EGL instead, so wl_shm's stride validation
# is never reached. Verified: iPhone mirroring displays, and the log is free of
# the "Invalid stride" and "gst_wl_window_ensure_fullscreen" errors waylandsink
# logged on every session.
#
# Do NOT switch to gtkwaylandsink. It creates its GTK window as soon as the
# pipeline starts rather than when video arrives, so a failed session leaves a
# blank white window parked on top of Stremio until the session is restarted.
# glimagesink was checked for this specifically and parks nothing while idle.
#
# -hls is deliberately NOT used. It made uxplay advertise AirPlay video support
# (feature bits 0 and 4), so iOS routed Safari/WebKit video at the HLS path.
# uxplay only implements HLS for the YouTube app and aborts on anything else,
# crashing the whole server mid-session:
#
#   airplay_video.c:790 adjust_master_playlist: Assertion byte_count == new_len
#   http_handlers.h:471 http_handler_action: Assertion airplay_video failed
#   WARNING: Unsupported HLS streaming format: clientProcName com.apple.WebKit.GPU
#            not found in supported list: YouTube      (then SIGSEGV)
#
# It never made Safari's per-video AirPlay button work either: upstream says
# browser AirPlay is unsupported. Mirroring is the only path that works.
#
# stdbuf -oL because uxplay's stdout is block-buffered when piped into logger,
# so lines only reached the journal in 4KB bursts. Sessions and crashes were
# invisible, which cost real debugging time more than once.
(
  while :; do
    stdbuf -oL -eL /usr/local/bin/uxplay -n HTPC -nh -fs -ca -nofreeze -vs glimagesink 2>&1 | logger -t uxplay
    sleep 2
  done
) &

# Remote control from a browser on the LAN: http://<lan-ip>:6080/vnc.html
#
# wayvnc stays on loopback and websockify is the only LAN-facing part, so there
# is exactly one reachable port. It binds to the wifi address explicitly rather
# than 0.0.0.0 so this never answers on tailscale0 — remote access here is
# deliberately LAN-only. The address is resolved each time round the loop, not
# hardcoded, because the connection is DHCP and .220 is not a reserved lease.
#
# Deliberately UNAUTHENTICATED, by request: anyone on the LAN who opens that
# URL gets full keyboard and mouse control of this session.
#
# Input works because Cage does create the virtual-pointer and virtual-keyboard
# managers. The clipboard does not — see the note at the top of this file; Cage
# creates no data-control manager, and that is exactly the protocol wayvnc uses
# for copy/paste, so the VNC clipboard is silently inert too.
(
  while :; do
    wayvnc 127.0.0.1 5900 2>&1 | logger -t wayvnc
    sleep 5
  done
) &

(
  while :; do
    lan=$(ip -4 -o addr show wlp0s20f3 2>/dev/null | awk '{print $4}' | cut -d/ -f1)
    if [ -n "$lan" ]; then
      websockify --web=/usr/share/novnc "$lan:6080" 127.0.0.1:5900 2>&1 | logger -t novnc
    fi
    sleep 5
  done
) &

# Idle backstop. tv-off-hook.sh only fires when the TV drops the HDMI link, and
# this TV stopped doing that — see the header of idle-stop.sh. swayidle watches
# the compositor seat (so it sees VNC's virtual input too, which /dev/input
# would not) and stops Stremio once nothing has happened for TV_IDLE_STOP.
#
# 45 minutes is deliberately long. The failure being prevented is measured in
# days, and the one case this can misjudge is a fully-buffered film playing with
# no download activity and nobody touching the remote — so the threshold sits
# well past any plausible pause-and-return.
#
# `resume` also runs when swayidle itself exits, which is what clears the
# inhibit on a session restart instead of leaving Stremio suppressed.
(
  while :; do
    swayidle -w \
      timeout "${TV_IDLE_STOP:-2700}" "$HOME/bin/idle-stop.sh" \
      resume "$HOME/bin/idle-stop.sh --clear" 2>&1 | logger -t swayidle
    sleep 5
  done
) &

# Stremio in the foreground, respawned in place. Cage exits when its client
# exits, so looping here (rather than exec'ing) keeps the compositor and the
# helpers above alive across a Stremio crash instead of rebuilding the whole
# session. The outer loop in .bash_profile covers Cage itself dying.
#
# --no-window-decorations drops the GTK headerbar, so the UI fills the TV.
# Stremio's own fullscreen toggle is not remembered between launches, which
# is why this flag rather than the in-app button.
#
# Only run Stremio while a TV is attached. With no TV there is nothing to
# display and a left-open player has pegged a core for days, so the box is
# better off idle — tv-off-hook.sh stops Stremio when HDMI goes away, and this
# gate keeps the loop from immediately starting it again. Polling rather than
# waiting on an event so that a TV coming back is picked up within a few
# seconds even if the hook missed a transition.
#
# The second gate is the idle backstop's inhibit file. Without it, stopping
# Stremio would achieve nothing: this loop polls every 3s and tv-connected still
# reads "connected" with the TV off, so it would restart Stremio immediately.
# Any seat activity clears the file (idle-stop.sh --clear) and playback resumes
# on the next pass.
while :; do
  if "$HOME/bin/tv-connected" && ! [ -e "${XDG_RUNTIME_DIR:-/tmp}/kiosk-idle-stop" ]; then
    flatpak run com.stremio.Stremio --no-window-decorations >>/tmp/stremio.log 2>&1
  fi
  sleep 3
done
