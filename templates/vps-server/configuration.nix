{
  inputs,
  outputs,
  ...
}: {
  imports = [
    inputs.impermanence.nixosModules.impermanence
    inputs.home-manager.nixosModules.home-manager

    ./hardware-configuration.nix

    ./../../modules/nixos/base.nix
    ./../../modules/nixos/auto-update.nix

    # Common VPS services
    ./../../services/tailscale.nix
  ];

  home-manager = {
    extraSpecialArgs = {inherit inputs outputs;};
    useGlobalPkgs = true;
    useUserPackages = true;
    users = {
      orther = {
        imports = [
          ./../../modules/home-manager/base.nix
        ];

        programs.git = {
          enable = true;
          userName = "Brandon Orther";
          userEmail = "brandon@orther.dev";
        };

        programs.ssh = {
          enable = true;
          matchBlocks = {
            "github.com" = {
              hostname = "github.com";
              identityFile = "~/.ssh/id_ed25519";
              user = "git";
            };
          };
        };
      };
    };
  };

  networking = {
    hostName = "CHANGEME"; # Change this to your hostname
    # VPS typically use DHCP
    useDHCP = true;
    useNetworkd = true;
  };

  # VPS-specific security hardening
  services.openssh.settings = {
    PermitRootLogin = "no";
    PasswordAuthentication = false;
    # Change default SSH port for additional security (optional)
    # Port = 2222;
  };

  # Enable unattended upgrades for VPS security
  system.autoUpgrade = {
    enable = true;
    flake = "github:yourusername/yourrepo"; # Replace with your repo
    flags = [
      "--update-input"
      "nixpkgs"
    ];
  };

  # VPS resource optimizations
  zramSwap.enable = true;
  services.logrotate.enable = true;
}