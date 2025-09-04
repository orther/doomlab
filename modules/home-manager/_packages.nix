{
  pkgs,
  osConfig,
  ...
}: {
  home = {
    packages = with pkgs;
      [
        bat
        btop
        htop
        tree
      ]
      # Development tools for working with this repo (excluded from servers)
      ++ (
        if builtins.substring 0 3 osConfig.networking.hostName != "svr"
        then [
          alejandra    # nix formatter
          just         # justfile commands
          nil          # nix LSP
          nixos-rebuild # needed for macOS
          sops         # secrets management
        ]
        else []
      );
  };
}
