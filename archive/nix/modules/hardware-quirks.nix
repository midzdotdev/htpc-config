{ config, pkgs, lib, ... }:

{
  # Dormant NVIDIA MX550. nouveau's GSP support for Turing is broken; any
  # process that opens /dev/dri/card1 (rustdesk, OBS, etc) triggers an
  # endless wake/fail loop that pegs the fan. Keep the dGPU invisible.
  boot.blacklistedKernelModules = [
    "nouveau"
    "nvidia"
    "nvidia_drm"
    "nvidia_modeset"

    # No Bluetooth use case on this box.
    "btusb"
    "btintel"
    "btbcm"
    "btrtl"
    "btmtk"
    "bluetooth"
  ];

  # Intel iGPU only.
  hardware.graphics = {
    enable = true;
    extraPackages = with pkgs; [
      intel-media-driver
      vaapiIntel
      vaapiVdpau
      libvdpau-va-gl
    ];
  };

  # Unified Remote injects keypresses through /dev/uinput. Both halves below
  # are load-bearing and neither is optional now the session is Wayland:
  # urserver detects Wayland, falls back from X11 XTEST to uinput, and if it
  # cannot open the device it logs "No input builder available" once per
  # keypress and does nothing — the phone connects fine and the remote just
  # silently does not work. The module is =m and nothing else pulls it in, and
  # default perms on the node are root-only, so the module load and the group
  # rule are both required.
  #
  # The PCI rule is about heat: with nouveau blacklisted nothing binds the
  # MX550, and the kernel leaves runtime PM at "on" for driverless devices —
  # so the card sat fully powered doing nothing. The fan ran at ~4750 RPM to
  # shift that heat even with the CPU 95% idle. Setting "auto" lets it reach
  # D3cold, after which the fan stops entirely.
  services.udev.extraRules = ''
    KERNEL=="uinput", MODE="0660", GROUP="input", TAG+="uaccess"
    ACTION=="add", SUBSYSTEM=="pci", ATTR{vendor}=="0x10de", ATTR{power/control}="auto"
  '';

  boot.kernelModules = [ "uinput" ];
}
