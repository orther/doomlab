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
