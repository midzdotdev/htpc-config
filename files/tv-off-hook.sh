#!/bin/bash
# Run by kanshi when the "panel" profile is applied — i.e. the TV disconnected.
#
# Stremio is stopped rather than left running. Left alone with no TV, a paused
# player pegged a core for days: 46 hours of accumulated CPU time, one core at
# 100%, package at 85 C and the fan at 4200 rpm, with the box otherwise idle.
# A restart cleared it instantly. The kiosk loop will not start Stremio again
# until a TV is back (see tv-connected), so the box drops to ~0% CPU and 710 MB.
#
# Measured, so nobody has to re-derive it: idling on the dashboard with no TV
# costs 1.4% CPU / 52 C / 4295 MB, and stopping Stremio gives 0.0% / 48 C /
# 710 MB. Both are fan-silent. The reason to stop it is the 3.6 GB and the
# runaway, not noise. Stopping the whole session instead saves a further 87 MB
# and nothing else, while killing uxplay and anything else living in the
# compositor, so it was rejected. (It does not even stop urserver, which
# daemonises out of the session cgroup.)
#
# If you are ever chasing a fan complaint on this box, two instruments lie:
#
# * `ps -o pcpu` is an average over the whole process lifetime, not a current
#   reading. On a box up for days it barely moves, so a process pegging a core
#   shows the same number before and after you fix it, and `ps --sort=-pcpu`
#   ranks by accumulated time rather than present load. Use `top -bn2` and read
#   the *second* iteration, or diff utime+stime from /proc/<pid>/stat.
# * /sys/class/hwmon/hwmon*/temp1_input is not the CPU. The first glob match
#   here reads ~30 C below the package, which shows you 54 C beside a 4200 rpm
#   fan and makes the cooling look broken while it is working correctly. Read
#   coretemp's "Package id 0", dell_ddv's "CPU", or the x86_pkg_temp zone.
#
# Debounce first: changing the TV's input drops HDMI briefly too, and that
# should not cost you your place in an episode.

DEBOUNCE=${TV_OFF_DEBOUNCE:-60}

# kanshi applies a profile more than once per transition — observed twice in
# the same second — so this really does get invoked concurrently. Without the
# lock, two debounce timers would race to stop Stremio.
exec 9>"${XDG_RUNTIME_DIR:-/tmp}/tv-off-hook.lock"
flock -n 9 || exit 0

sleep "$DEBOUNCE"

# Decide on the state of the world *now*, not on the transition that woke us.
# That is what makes this converge instead of latching, and it is the reason a
# trigger lost to the lock above is harmless: whichever hook is already waiting
# re-reads the live state and covers it. Verified with off/on/off and on/off/on
# sequences fast enough that the middle transition is swallowed — both settle
# to match where the TV actually ended up. Do not "simplify" this into acting
# on the edge that triggered it.
if "$HOME/bin/tv-connected"; then
	logger -t tv-off-hook "TV back within ${DEBOUNCE}s — leaving Stremio running"
	exit 0
fi

logger -t tv-off-hook "TV still gone after ${DEBOUNCE}s — stopping Stremio"

# Already stopped is the target state, not a failure: kanshi applies a profile
# more than once per transition, so this legitimately runs against a Stremio
# that is already gone. Without this the hook would exit non-zero and log
# "error: ... is not running" every time it succeeded at doing nothing.
flatpak kill com.stremio.Stremio 2>/dev/null || true
