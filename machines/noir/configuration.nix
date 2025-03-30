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

    ./../../services/nas.nix
    ./../../services/tailscale.nix
    #./../../services/netdata.nix
    #./../../services/nextcloud.nix
    #./../../services/nixarr.nix
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

  # networking.hostName = "noir";
  networking = {
    hostName = "noir";
    useDHCP = false;
    interfaces.enp2s0.useDHCP = true;
    useNetworkd = true;
  };
}
