{
  imports = [
    ./_packages.nix
  ];

  users.users.nixos = {
    isNormalUser = true;
    extraGroups = ["wheel"];
    openssh.authorizedKeys.keys = [
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIDvJx1pyQwQVPPdXlqhJEtUlKyVr4HbZvgbjZ96t75Re"
    ];
  };

  programs.bash.shellAliases = {
    install = "sudo bash -c '$(curl -fsSL https://raw.githubusercontent.com/orther/doomlab/main/install.sh)'";
  };

  security.sudo.wheelNeedsPassword = false;

  nix.settings.experimental-features = ["nix-command" "flakes"];

  services.openssh = {
    enable = true;
  };

  # Keep minimal bootloader configuration - the base ISO handles most of this
  # Enhanced bootloader configuration for better Ventoy compatibility
  boot.loader.grub = {
    # Ensure proper EFI support for Ventoy
    efiSupport = true;
    efiInstallAsRemovable = true;
    # Explicit device settings for hybrid boot
    device = "nodev";
  };

  # ISO image configuration optimized for Ventoy
  isoImage = {
    # Ensure both EFI and USB boot methods work
    makeEfiBootable = true;
    makeUsbBootable = true;
    
    # Explicitly enable hybrid boot for maximum compatibility
    appendToMenuLabel = " (x86_64)";
    
    # Ensure proper boot sectors for Ventoy
    volumeID = "nixos-doomlab";
  };

  # https://nixos.wiki/wiki/FAQ/When_do_I_update_stateVersion
  system.stateVersion = "23.11";
}
