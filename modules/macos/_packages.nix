{
  config,
  inputs,
  ...
}: {
  imports = [
    inputs.nix-homebrew.darwinModules.nix-homebrew
  ];

  nix-homebrew = {
    enable = true;
    # NOTE: Disabled this until I migrate M1 Ultra to use Nix
    # enableRosetta = true;
    enableRosetta = false;
    user = "orther";
    mutableTaps = false;
    taps = {
      "homebrew/homebrew-bundle" = inputs.homebrew-bundle;
      "homebrew/homebrew-cask" = inputs.homebrew-cask;
      "homebrew/homebrew-core" = inputs.homebrew-core;
    };
    autoMigrate = true;
  };

  homebrew = {
    enable = true;
    global = {
      autoUpdate = true;
    };
    onActivation = {
      autoUpdate = false;
      upgrade = false;
      cleanup = "zap";
    };
    brews = [
      "trash"
    ];
    taps = builtins.attrNames config.nix-homebrew.taps;
    casks = [
      "1password-cli"
      "1password"
      "discord"
      "obsidian"
      "raycast"
      "visual-studio-code"
    ];
    masApps = {
      "Tailscale" = 1475387142;
    };
  };
}
