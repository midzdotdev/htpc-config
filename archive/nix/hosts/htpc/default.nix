{ config, pkgs, lib, ... }:

{
  imports = [
    ./hardware.nix
    ../../modules/kiosk.nix
    ../../modules/services.nix
    ../../modules/hardware-quirks.nix
  ];

  networking.hostName = "htpc";
  networking.networkmanager.enable = true;

  time.timeZone = "Europe/London";
  i18n.defaultLocale = "en_GB.UTF-8";

  users.users.htpc = {
    isNormalUser = true;
    description = "HTPC kiosk";
    extraGroups = [ "wheel" "networkmanager" "input" "video" "audio" ];
    initialPassword = "htpc";
    openssh.authorizedKeys.keys = [
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAINp8YWPvHlEeSNjiI0INmOq71E7C82+zpS4Ox/tqYeZ+ james@James-MBP.local"
    ];
  };

  security.sudo.wheelNeedsPassword = false;

  services.openssh = {
    enable = true;
    settings.PasswordAuthentication = true;
    settings.PermitRootLogin = "no";
  };

  services.avahi = {
    enable = true;
    nssmdns4 = true;
    publish = {
      enable = true;
      addresses = true;
      domain = true;
      workstation = true;
    };
  };

  nix.settings = {
    experimental-features = [ "nix-command" "flakes" ];
    auto-optimise-store = true;
  };

  nixpkgs.config.allowUnfree = true;

  system.stateVersion = "25.05";
}
