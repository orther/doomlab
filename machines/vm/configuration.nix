{
  config,
  lib,
  pkgs,
  inputs,
  outputs,
  ...
}: {
  imports = [
    ./hardware-configuration.nix
    ../../modules/nixos/base.nix
    inputs.home-manager.nixosModules.home-manager
  ];

  # System configuration
  networking.hostName = "doomlab-vm";
  time.timeZone = "America/Los_Angeles";

  # User configuration
  users.users.orther = {
    isNormalUser = true;
    extraGroups = ["wheel" "networkmanager"];
    openssh.authorizedKeys.keys = [
      # Add your SSH public key here
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIDvJx1pyQwQVPPdXlqhJEtUlKyVr4HbZvgbjZ96t75Re brandon@orther.dev"
    ];
  };

  # Enable root user with password for VM management
  users.users.root = {
    # Set this to your password hash generated with: mkpasswd -m sha-512
    hashedPassword = "$6$rounds=4096$6$FvLcGQCKcw9urvyq$Dzy29Kx7oklZV75QwWGgSpdqzQ74xgBi1mGAGB.WylKS1ogRSLrqNEMc0O.dYBp8SGp7IlddtV6WIklBMrMz61";
  };

  # SSH configuration
  services.openssh = {
    enable = true;
    settings.PasswordAuthentication = false;
    settings.PermitRootLogin = "no";
  };

  # Home Manager
  home-manager = {
    extraSpecialArgs = {inherit inputs outputs;};
    users.orther = import ../../modules/home-manager/nixos.nix;
  };

  system.stateVersion = "24.11";
}
