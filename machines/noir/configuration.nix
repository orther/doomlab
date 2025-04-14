{
  inputs,
  outputs,
  pkgs, # Ensure pkgs is passed
  lib,  # Ensure lib is passed for mkIf etc.
  ...
}: {
  imports = [
    inputs.impermanence.nixosModules.impermanence
    inputs.home-manager.nixosModules.home-manager
    #inputs.nixarr.nixosModules.default # Keep commented if not used

    ./hardware-configuration.nix

    ./../../modules/nixos/base.nix
    ./../../modules/nixos/remote-unlock.nix
    ./../../modules/nixos/auto-update.nix

    ./../../services/nas.nix
    ./../../services/tailscale.nix
    #./../../services/netdata.nix # Keep commented if not used
    #./../../services/nextcloud.nix # Keep commented if not used
    #./../../services/nixarr.nix # Keep commented if not used
  ];

  home-manager = {
    extraSpecialArgs = {inherit inputs outputs;};
    useGlobalPkgs = true;
    useUserPackages = true;
    users = {
      orther = {
        imports = [
          ./../../modules/home-manager/base.nix
          # Correctly import the nixCats home-manager module
          inputs.nixCats-nvim.homeModules.default
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

        # Configure nixCats using the home-manager module options
        # See :h nixCats.module
        nixCats = {
          enable = true;
          # Add overlays, including the one for auto-detecting plugins from inputs
          addOverlays = [
            (inputs.nixCats-nvim.utils.standardPluginOverlay inputs)
            # Add other overlays if needed
          ];
          # Point to the Lua config directory (relative to this file)
          luaPath = ./nvim-config;

          # Define the Neovim package(s)
          # Note: packageDefinitions is now directly under nixCats, not nested
          # Also needs to be nested under .replace or .merge
          packageDefinitions.replace = {
            # Name of the package, e.g., 'nvim-dev'
            nvim-dev = { pkgs, ... }: { # Ensure pkgs is available here
              settings = {
                aliases = ["nvim" "vim"];
              };
              categories = {
                core = true;
                lsp = true;
                ui = true;
                treesitter = true;
                telescope = true;
                gitsigns = true;
              };
            };
          };

          # Default package to install and use for aliases like 'nvim'
          defaultPackageName = "nvim-dev";
          # Which packages defined above should be installed for this user
          packageNames = [ "nvim-dev" ];

          # Define plugin categories
          # Note: categoryDefinitions is now directly under nixCats, not nested
          # Needs to be nested under a merge strategy like .replace or .merge
          categoryDefinitions.replace = { pkgs, ... }: { # Ensure pkgs is available here
            startupPlugins = {
              core = [
                pkgs.vimPlugins.lazy-nvim # Correct dependency
                pkgs.vimPlugins.which-key-nvim
              ];
              ui = [
                pkgs.vimPlugins.tokyonight-nvim
              ];
              treesitter = [
                pkgs.vimPlugins.nvim-treesitter.withAllGrammars
              ];
              telescope = [
                pkgs.vimPlugins.telescope-nvim
                pkgs.vimPlugins.telescope-fzf-native-nvim
                pkgs.vimPlugins.plenary-nvim
              ];
              gitsigns = [
                pkgs.vimPlugins.gitsigns-nvim
              ];
              lsp = [
                # Mason plugins removed - handled in Lua
                pkgs.vimPlugins.nvim-lspconfig
                pkgs.vimPlugins.nvim-cmp
                pkgs.vimPlugins.cmp-nvim-lsp
                pkgs.vimPlugins.cmp-buffer
                pkgs.vimPlugins.cmp-path
                pkgs.vimPlugins.cmp_luasnip
                pkgs.vimPlugins.luasnip
                pkgs.vimPlugins.friendly-snippets
              ];
            };
            optionalPlugins = {}; # Keep empty if lazy.nvim handles all loading
            lspsAndRuntimeDeps = {
              lsp = with pkgs; [
                nil # Nix LSP
                lua-language-server
                bash-language-server
                alejandra # Nix formatter
                stylua # Lua formatter
                shellcheck # Bash linter
                make # For telescope-fzf-native build
              ];
            };
          };
        };
      };
    };
  };

  networking.hostName = "noir";
  # Keep network settings as they were
}