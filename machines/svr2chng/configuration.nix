{
  inputs,
  outputs,
  ...
}: {
  imports = [
    inputs.impermanence.nixosModules.impermanence
    inputs.home-manager.nixosModules.home-manager
    inputs.nixarr.nixosModules.default

    ./hardware-configuration.nix

    ./../../modules/nixos/base.nix
    ./../../modules/nixos/remote-unlock.nix
    ./../../modules/nixos/auto-update.nix

    ./../../services/tailscale.nix
    ./../../services/nixarr.nix
    
    # Optional services - uncomment as needed:
    # ./../../services/netdata.nix
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
      };
    };
  };

  networking.hostName = "svr2chng";
}
