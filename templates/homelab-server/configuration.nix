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

    # Services commonly used on homelab servers
    ./../../services/tailscale.nix
    # Optional services - uncomment as needed:
    # ./../../services/nas.nix
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
    # Static IP configuration for servers
    useDHCP = false;
    interfaces.CHANGEME.useDHCP = true; # Replace CHANGEME with your interface name (e.g., eth0, enp1s0)
    useNetworkd = true;
  };
}