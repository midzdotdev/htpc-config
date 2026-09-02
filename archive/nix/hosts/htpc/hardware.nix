{ config, lib, pkgs, modulesPath, ... }:

# Placeholder. On first install, replace this entire file with the output of:
#   nixos-generate-config --no-filesystems --show-hardware-config
# run on the target box (gives you the right kernel modules, fileSystems, boot loader, etc).

{
  imports = [
    (modulesPath + "/installer/scan/not-detected.nix")
  ];

  boot.initrd.availableKernelModules = [ "xhci_pci" "nvme" "usb_storage" "sd_mod" ];
  boot.kernelModules = [ "kvm-intel" ];

  hardware.enableRedistributableFirmware = true;
  hardware.cpu.intel.updateMicrocode = true;

  # Fill these in after running nixos-generate-config on the box:
  # fileSystems."/" = { device = "/dev/disk/by-uuid/..."; fsType = "ext4"; };
  # fileSystems."/boot" = { device = "/dev/disk/by-uuid/..."; fsType = "vfat"; };
  # boot.loader.systemd-boot.enable = true;
  # boot.loader.efi.canTouchEfiVariables = true;
}
