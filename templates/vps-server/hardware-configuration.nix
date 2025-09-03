# VPS hardware configuration
# Most VPS providers use virtualized hardware, so this is typically simpler
# Generate with: nixos-generate-config --show-hardware-config > hardware-configuration.nix

{ config, lib, pkgs, modulesPath, ... }:

{
  imports = [
    (modulesPath + "/profiles/qemu-guest.nix") # Common for VPS providers
  ];

  # EXAMPLE - Replace with your actual VPS configuration
  boot.initrd.availableKernelModules = [ "ata_piix" "uhci_hcd" "virtio_pci" "virtio_scsi" "sd_mod" "sr_mod" ];
  boot.initrd.kernelModules = [ ];
  boot.kernelModules = [ ];
  boot.extraModulePackages = [ ];

  # EXAMPLE - Replace with your actual filesystem configuration
  fileSystems."/" = {
    device = "/dev/disk/by-uuid/CHANGEME-ROOT-UUID";
    fsType = "ext4";
  };

  fileSystems."/boot" = {
    device = "/dev/disk/by-uuid/CHANGEME-BOOT-UUID";
    fsType = "vfat";
  };

  # Persistent storage for server applications
  fileSystems."/nix/persist" = {
    device = "/dev/disk/by-uuid/CHANGEME-PERSIST-UUID";
    fsType = "ext4";
    neededForBoot = true;
  };

  # VPS typically benefit from swap
  swapDevices = [
    { device = "/swapfile"; size = 2048; } # 2GB swap file
  ];

  networking.useDHCP = lib.mkDefault true;

  nixpkgs.hostPlatform = lib.mkDefault "x86_64-linux";

  # VPS optimizations
  boot.loader.grub = {
    enable = true;
    device = "nodev"; # UEFI systems
    efiSupport = true;
    efiInstallAsRemovable = true; # Common for VPS
  };

  # Optimize for virtualized environment
  services.qemuGuest.enable = true;
}