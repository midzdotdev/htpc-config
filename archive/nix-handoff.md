# HTPC — session handoff

_Written 2026-07-31._

**This file is disposable. The hard-won details live in comments next to the
code they govern** — if something here contradicts a comment, the comment wins.
What belongs here is only the stuff with no code to attach to: current state,
what is planned next, and what is still outstanding.

## Current state: working

Stremio 1.1.3 fullscreen on the TV under a Wayland kiosk at 125% UI scale, fan
silent, Unified Remote working from the phone, Torrentio installed, and Stremio
stopped automatically whenever the TV is off. Verified across a reboot.

| | |
|---|---|
| Reach it | `ssh htpc` (key auth, passwordless; `htpc`/`htpc` for sudo) |
| Network | Home / `192.168.0.220`; profiles saved for `SKY6DZKK`, the Huawei 5 GHz, and Cornwall Lodge — switch with `sudo nmtui` |
| Session | Cage (Wayland) → Stremio + uxplay + urserver + urclick-fix + kanshi, all self-respawning |
| Fan / temp | 0 RPM idle, ~52 °C package |
| Config repo | **On the Mac** at `~/code/htpc-nix-config` → https://github.com/midzdotdev/htpc-nix-config |

The box itself is **not** managed by the flake yet — it is a hand-configured
Debian trixie install. The flake is written and buildable in principle, but
applying it is a separate project.

## Where the gotchas are recorded

Every one of these is a trap that cost real time and looks like a tidy-up
opportunity to anyone who does not know the story. They are documented at the
code, not here:

| Gotcha | Lives in |
|---|---|
| Stremio v5 cannot run under X11 — Wayland is not a preference | `modules/kiosk.nix`, `home/files/bash_profile` |
| The dormant MX550 was the fan; runtime PM must be forced to `auto` | `modules/hardware-quirks.nix` |
| Unified Remote's taps need the uinput module, the udev rule *and* the shim | `modules/hardware-quirks.nix`, `home/files/urclick-fix.py` |
| Driving the UI synthetically: pointer accel, and undeclared key codes | `home/files/urclick-fix.py` |
| The TV hotplugs, so output config must be re-applied, not set once | `home/files/kanshi-config` |
| Stremio pegs a core if left in the player with no TV | `home/files/tv-off-hook.sh` |
| `ps -o pcpu` and `hwmon*/temp1_input` both lie when chasing a fan complaint | `home/files/tv-off-hook.sh` |
| Why the TV-off logic is level-triggered, and must stay that way | `home/files/tv-off-hook.sh` |
| The scheme assumes the TV drops the HDMI link when off | `home/files/tv-connected` |
| Cage gives the selection only to the focused client, so the clipboard is unusable | `home/files/kiosk-wayland.sh` |
| urserver's download URL shape, and that upstream deletes old builds | `modules/services.nix` |

## What changed most recently

- **AIOStreams removed, and the container runtime with it.** It had served zero
  requests in 70 days and no Stremio profile referenced the addon. Nothing else
  wanted docker, so all seven packages, `/var/lib/docker`, the apt repo, the
  group and the bridge went too — 2.04 GB reclaimed.
- **UI scale to 125%**, owned by kanshi.
- **Unified Remote fixed** — taps had never worked under Wayland.
- **urserver pin corrected** — the old URL 404'd and could never have built.
- **Torrentio installed** with quality/size filters.
- **Stremio is stopped while no TV is attached**, after a 60 s debounce.

Measured idle states, kept here because the decision was a trade-off rather
than a fact about the code. All three are **fan-silent**, so stopping Stremio
is about the memory and the runaway, not noise:

| State | CPU | Fan | Package | RAM used |
|---|---|---|---|---|
| Runaway (the fault) | 100% of a core | 4201 rpm | 85 °C | — |
| Stremio idle on dashboard | 1.4% | 0 rpm | 52 °C | 4295 MB |
| Stremio stopped (chosen) | 0.0% | 0 rpm | 48 °C | 710 MB |
| Whole session stopped | 0.0% | 0 rpm | 48 °C | 623 MB |

Stopping the whole session was rejected on those numbers: 87 MB more, at the
cost of the compositor, uxplay and the planned wayvnc service — which is wanted
precisely when the TV is off.

## Next project: control the display from the laptop in a browser

Unified Remote's web UI is janky. The goal is a web service reachable from the
laptop that shows the screen and drives it.

### Recommendation: wayvnc + noVNC

wayvnc is the wlroots-native VNC server; noVNC (via websockify) puts it in a
browser so no VNC client is needed. **The feasibility question is already
settled** — the usual blocker is a kiosk compositor not exposing the protocols
a VNC server needs, and Cage creates all of them:

```
wlr_screencopy_manager_v1_create        # screen capture
wlr_virtual_keyboard_manager_v1_create  # keyboard injection
wlr_virtual_pointer_manager_v1_create   # pointer injection
```

so it should get both view *and* input with no custom code. All packaged in
Debian trixie (`wayvnc 0.9.1-1`, `novnc 1:1.6.0-2`, `websockify 0.12.0`) and
present in nixpkgs for when the flake goes live.

Rough shape:

1. `wayvnc` bound to localhost on 5900, started from `kiosk-wayland.sh` as
   another watchdogged helper (it needs `WAYLAND_DISPLAY`, like `grim`).
2. `websockify` serving noVNC on 6080 → `http://htpc.local:6080/vnc.html`.
3. Open 6080 in the firewall (5900 only if a native client is wanted).
4. Mirror into the flake: packages, the kiosk script, firewall ports.

Things to decide or watch:

- **Auth.** wayvnc supports TLS and username/password but needs a cert and a
  credentials file. This grants full control of the box, so it should not be
  open even on the LAN — and the secret belongs in agenix, not the repo.
- **Performance.** Fine for driving the UI; not for watching video through.
  Consider capping the frame rate.
- **Injection is independent of `urclick-fix`** — wayvnc injects at the
  compositor level, not through `/dev/uinput`, so the two cannot conflict.
- **Do not rely on the clipboard** for laptop↔box copy/paste; see the note in
  `kiosk-wayland.sh`. noVNC's own clipboard panel goes over the VNC protocol
  and may work, but is untested.

### Alternatives considered

| Option | Verdict |
|---|---|
| **wayvnc + noVNC** | Recommended. Standard, packaged, browser-native, view + input, no custom code. |
| Custom web pad over `/dev/uinput` | Viable fallback and very light — a control pad plus periodic `grim` screenshots. Only worth it if wayvnc's input path disappoints. The uinput approach is proven on this box. |
| Sunshine + Moonlight | Built for game streaming. Better video, but not browser-based and far more than this needs. |
| `wlrctl` / a thin HTTP wrapper | Simplest possible, but gives no view of the screen — which is most of the point. |

## Operating it

- Text console: **Ctrl+Alt+F2** (kernel VT). **Ctrl+Alt+F1** returns to the kiosk.
- Screenshot remotely:
  `ssh htpc "XDG_RUNTIME_DIR=/run/user/1000 WAYLAND_DISPLAY=wayland-0 grim /tmp/s.png"`
  then `scp htpc:/tmp/s.png .`
- Logs: `/tmp/stremio.log`, `/tmp/cage.log`, `journalctl -t uxplay`,
  `journalctl -t urclick-fix`, `journalctl -t kanshi`,
  `journalctl -t tv-off-hook`, `~/.urserver/urserver.log`
- Restart the kiosk: `sudo systemctl restart getty@tty1`
- Unified Remote: iOS app, or `http://htpc.local:9530/client/`
- Force a TV hotplug for testing: `echo off` then `echo detect` into
  `/sys/class/drm/*-HDMI-*/status` (blanks the TV briefly).

## Known risks / open items

- **The flake is still not applied.** `hosts/htpc/hardware.nix` is a
  placeholder, so it cannot be installed as-is. The urserver derivation should
  now build, but has not been — no x86_64-linux machine to try it on.
- **The runaway can still happen with the TV on.** The TV-off hook only covers
  the TV-off case. If it recurs on a live TV, that is the signal a different
  guard is needed — but a CPU-threshold watchdog risks killing real playback,
  so wait for evidence before adding one.
- **The Stremio flatpak auto-updates**, and a release could regress. The
  session self-respawns, so a bad update shows as a black or missing UI rather
  than a crash loop.
- **Wi-Fi credentials** are still not codified — agenix, or a one-time `nmcli`
  after install.
