# htpc-config

Configuration for the Stremio kiosk HTPC, applied with Ansible.

The box is a laptop running **Debian 13**, wall-mounted behind a TV. It boots
straight into Stremio under Cage (Wayland), receives AirPlay, and takes input
from a phone over Unified Remote.

> This repo used to describe a NixOS system that was never installed — the box
> has always run Debian, so the config drifted and the repo could not be
> trusted. Ansible manages the box as it actually is. The old Nix files are in
> [`archive/nix/`](archive/nix/) for the knowledge in them, not for use.

## Applying it

```
ansible-playbook site.yml -K
```

`-K` prompts for the sudo password: apt and the uxplay install need root.
Needs only `ansible-core` — no collections, no vault, no group_vars.

It is idempotent, and a run against a correctly configured box reports
`changed=0`. **If a run wants to change something, work out which side is
wrong before letting it through** — the box has been the source of truth more
often than this repo has.

## Layout

```
site.yml            # everything: packages, uxplay, flatpak, the session files
inventory.ini       # one host, reached by the "htpc" alias in ~/.ssh/config
files/              # the scripts, copied to ~/bin and ~/.config
archive/            # the abandoned NixOS config, kept for reference
```

One flat playbook rather than roles. There is one host and one job.

## The session

`.bash_profile` starts Cage on tty1, which runs `kiosk-wayland.sh`. That script
puts Stremio in the foreground and everything else in background watchdog loops:
kanshi, uxplay, Unified Remote, the VNC pair, and the idle backstop.

**To restart the session, kill the `kiosk-wayland.sh` process tree** so Cage
exits on its own and `.bash_profile` respawns it:

```
ssh htpc 'pkill -f "bin/kiosk-wayland.sh"'
```

Do **not** `kill -9` Cage. Cage dies but its child script and every helper are
orphaned to `ppid 1` and keep running alongside the new session. That happened
once and went unnoticed for nine days, with two kanshi instances fighting over
the output config and two uxplay instances competing for AirPlay.

## Read the scripts

The non-obvious decisions are documented where they are made, not here — a
comment on the line is found by whoever next edits it. `kiosk-wayland.sh` in
particular explains why each helper exists and which of them are load-bearing.

Three that have cost real time:

- **AirPlay uses `glimagesink`, not `waylandsink`.** waylandsink passes video as
  `wl_shm` buffers and an iPhone mirror stream produces a stride wlroots
  rejects; a Wayland protocol error is fatal to the connection, so one bad
  buffer kills the display path for the life of the process. A Mac worked, the
  phone silently did not. Also: never `gtkwaylandsink`.
- **The TV no longer drops the HDMI link when powered off**, so `tv-off-hook.sh`
  can never fire. `idle-stop.sh` is the backstop that replaced it.
- **Cage exposes no layer-shell and no data-control**, so wallpaper daemons and
  the Wayland clipboard cannot work on this box at all.

## Not managed here

- **Unified Remote** (`/opt/urserver`) — third-party download with its own
  installer. The kiosk script starts and watchdogs it.
- **Wi-Fi credentials** — set once with `nmcli`. Don't commit secrets; this
  repo is public.
- **Stremio account and addons** — per-device login, synced via the account.

## VNC

`http://<the box's LAN IP>:6080/vnc.html` serves noVNC, bound to the wifi
address only so it never answers on tailscale. Deliberately unauthenticated:
anyone on the LAN who opens it gets full control of the session.
