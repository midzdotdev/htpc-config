# htpc-config

Ansible configuration for the Stremio kiosk HTPC.

The box is a laptop running Debian 13, wall-mounted behind a TV. It boots
straight into Stremio under Cage (Wayland), receives AirPlay, and takes input
from a phone over Unified Remote.

There is no Nix here. The repo used to hold a NixOS config for a machine that
was never installed, so nothing enforced it and the box drifted away from it.
Do not add Nix back unless you also reinstall the OS.

## Applying it

```
ansible-playbook site.yml -K
```

`-K` prompts for the sudo password. apt and the uxplay install need root.
Nothing else is required: no collections, no vault, no group_vars, just
ansible-core.

A run against a correctly configured box reports `changed=0`. If a run wants to
change something, work out which side is wrong before you let it through. The
box has been right more often than this repo has.

## Layout

```
site.yml            packages, uxplay, flatpak, system config, session files
inventory.ini       one host, reached by the "htpc" alias in ~/.ssh/config
files/              scripts copied to ~/bin and ~/.config
files/system/       units, udev rules and modprobe config copied to /etc
```

One flat playbook, no roles. There is one host and one job.

## The session

`.bash_profile` starts Cage on tty1, which runs `kiosk-wayland.sh`. That script
puts Stremio in the foreground and everything else into background watchdog
loops: kanshi, uxplay, Unified Remote, the VNC pair and the idle backstop.

To restart the session, kill the `kiosk-wayland.sh` process tree so Cage exits
on its own and `.bash_profile` starts a fresh one:

```
ssh htpc 'pkill -f "bin/kiosk-wayland.sh"'
```

Never `kill -9` Cage. Cage dies, but its child script and every helper survive
as orphans on `ppid 1` and keep running alongside the new session. That happened
once and went unnoticed for nine days, with two kanshi instances fighting over
the output config and two uxplay instances competing for AirPlay.

## Things that have cost real time

The reasoning for each decision sits next to the decision, in the script or
config file that makes it. Read `kiosk-wayland.sh` before changing the session.
Three worth knowing before you start:

AirPlay uses `glimagesink`, not `waylandsink`. waylandsink passes video as
`wl_shm` buffers, and an iPhone mirror stream produces a stride that wlroots
rejects. A Wayland protocol error kills the client connection, so one bad buffer
takes out the display path for the life of the process. A Mac worked and the
phone silently did not. Do not try `gtkwaylandsink` either: it opens its window
when the pipeline starts rather than when video arrives, so a failed session
leaves a blank white window sitting over Stremio.

The TV no longer drops the HDMI link when it is powered off, so `tv-connected`
always reports a display and `tv-off-hook.sh` can never fire. `idle-stop.sh` is
the backstop that covers it, driven by swayidle.

Cage exposes no layer-shell and no data-control. Wallpaper daemons and the
Wayland clipboard cannot work on this box at all.

## Not managed here

Unified Remote (`/opt/urserver`) is closed source and ships as a tarball with no
apt package, so install it by hand. `site.yml` prints the download path and the
version-pinning trap when it runs.

Wi-Fi credentials are set once with `nmcli`. Do not commit them; this repo is
public.

The Stremio account is per-device state, and its addon list syncs through the
account.

## VNC

`http://<the box's LAN IP>:6080/vnc.html` serves noVNC, bound to the wifi
address so it never answers on tailscale. It is deliberately unauthenticated.
Anyone on the LAN who opens it gets full control of the session.
