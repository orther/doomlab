{
  inputs,
  outputs,
  ...
}: {
  imports = [
    inputs.home-manager.darwinModules.home-manager

    ./hardware-configuration.nix

    ./../../modules/macos/base.nix
  ];

  home-manager = {
    extraSpecialArgs = {inherit inputs outputs;};
    useGlobalPkgs = true;
    useUserPackages = true;
    users = {
      orther = {
        imports = [
          ./../../modules/home-manager/base.nix
          ./../../modules/home-manager/fonts.nix
          ./../../modules/home-manager/alacritty.nix
          ./../../modules/home-manager/1password.nix
        ];
      };
    };
  };

  networking = {
    hostName = "stud";
    computerName = "stud";
    localHostName = "stud";
  };
}
