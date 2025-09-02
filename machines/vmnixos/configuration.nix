{
  inputs,
  outputs,
  ...
}: {
  imports = [
    inputs.home-manager.nixosModules.home-manager

    ./hardware-configuration.nix
    ./../../modules/nixos/base.nix
    
    # Optional services - uncomment as needed:
    # ./../../services/tailscale.nix
    # ./../../services/nextcloud.nix
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

  networking.hostName = "vmnixos";
}
