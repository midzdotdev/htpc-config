{ config, pkgs, lib, ... }:

{
  home.username = "htpc";
  home.homeDirectory = "/home/htpc";
  home.stateVersion = "25.05";

  programs.home-manager.enable = true;

  # Managed dotfiles. Source files live next to this one so they can be
  # edited and diff'd as plain text.
  home.file = {
    # Login entry point: starts the Cage (Wayland) kiosk on tty1.
    ".bash_profile".source = ./files/bash_profile;

    # The Wayland session: Stremio + uxplay + urserver under Cage.
    "bin/kiosk-wayland.sh" = {
      source = ./files/kiosk-wayland.sh;
      executable = true;
    };

    # Works around urserver emitting tap clicks in a single evdev frame, which
    # libinput drops. See the header in the script.
    "bin/urclick-fix.py" = {
      source = ./files/urclick-fix.py;
      executable = true;
    };

    # Is a TV attached? Shared by the kiosk loop and the kanshi hook so the two
    # cannot drift apart.
    "bin/tv-connected" = {
      source = ./files/tv-connected;
      executable = true;
    };

    # Stops Stremio when the TV goes away, after a debounce.
    "bin/tv-off-hook.sh" = {
      source = ./files/tv-off-hook.sh;
      executable = true;
    };

    # Output layout + the 125% UI scale, re-applied on TV hotplug.
    # Idle backstop: stops Stremio when nothing has happened for a while.
    # Needed because this TV stopped dropping the HDMI link when powered off,
    # so tv-off-hook.sh can no longer fire. See the header of idle-stop.sh.
    "bin/idle-stop.sh" = {
      source = ./files/idle-stop.sh;
      executable = true;
    };

    # Renders the "Stremio is paused" still that idle-stop.sh puts on the TV,
    # so a stopped session does not look like a broken box.
    "bin/make-idle-splash.py" = {
      source = ./files/make-idle-splash.py;
      executable = true;
    };

    # Moves the pointer without clicking, so the cursor can be nudged after
    # another client has held the display. A click here would toggle playback.
    "bin/move-pointer.py" = {
      source = ./files/move-pointer.py;
      executable = true;
    };

    ".config/kanshi/config".source = ./files/kanshi-config;

  };
}
