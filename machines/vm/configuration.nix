
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
    ./../../modules/nixos/remote-unlock.nix
    ./../../modules/nixos/auto-update.nix

    # ./../../services/tailscale.nix
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
          # Signing config remains the same if needed
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
    hostName = "vm";
    useDHCP = false;
    interfaces.enp1s0.useDHCP = true;
    useNetworkd = true;
  };
}
