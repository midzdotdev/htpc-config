{ config, pkgs, lib, ... }:

{
  # Autologin htpc on tty1 → ~/.bash_profile starts Cage → kiosk-wayland.sh
  # runs Stremio with uxplay and urserver behind it.
  #
  # No X server: Stremio v5's WebView fails to start under X11 on this
  # hardware (upstream stremio-bugs#2634, reproduced on both the flatpak and
  # the native build), so the session is Wayland-only. Text consoles are
  # unaffected — Ctrl+Alt+F2 is a kernel VT served by getty.
  services.getty.autologinUser = "htpc";
  console.keyMap = "uk";

  # HTPC always-on: never sleep/suspend, regardless of lid state or idleness.
  # This is a bedside media box — closing the laptop lid should be a no-op,
  # and the screen must never blank while Stremio is showing.
  services.logind = {
    lidSwitch = "ignore";
    lidSwitchDocked = "ignore";
    lidSwitchExternalPower = "ignore";
    extraConfig = ''
      IdleAction=ignore
    '';
  };

  # A desktop portal must be present even in a bare kiosk: without one,
  # libadwaita blocks for 25s per settings lookup (colour-scheme, contrast,
  # high-contrast) before giving up, which added roughly 100s to every
  # Stremio launch.
  xdg.portal = {
    enable = true;
    extraPortals = [ pkgs.xdg-desktop-portal-gtk ];
    config.common.default = "gtk";
  };

  # Sound stack.
  services.pipewire = {
    enable = true;
    alsa.enable = true;
    alsa.support32Bit = true;
    pulse.enable = true;
    wireplumber.enable = true;
  };
  security.rtkit.enable = true;

  # The kiosk is launched from ~/.bash_profile (home/files/bash_profile) so
  # that it only fires on tty1 and never on SSH logins.

  environment.systemPackages = with pkgs; [
    # Wayland kiosk: Cage is the compositor, kanshi owns the output layout
    # (see home/files/kanshi-config — it must re-apply on hotplug, which a
    # one-shot wlr-randr cannot). wlr-randr is kept for interactive poking.
    # grim is for grabbing the screen over SSH when debugging remotely.
    cage
    kanshi
    wlr-randr
    grim

    # Media / kiosk apps
    stremio
    uxplay

    # Diagnostics (we use these constantly when poking at the box)
    htop
    iotop
    pciutils
    usbutils
    lm_sensors
    strace
    socat
    sshpass
    git
    vim
    curl
    jq
  ];
}
