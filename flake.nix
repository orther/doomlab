{
  description = "doomlab";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-24.11";
    impermanence.url = "github:nix-community/impermanence";

    home-manager = {
      url = "github:nix-community/home-manager/release-24.11";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    nix-darwin = {
      url = "github:LnL7/nix-darwin/nix-darwin-24.11";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    sops-nix = {
      url = "github:Mic92/sops-nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    nixarr = {
      url = "github:rasmus-kirk/nixarr";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    nix-homebrew = {
      url = "github:zhaofengli-wip/nix-homebrew";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    homebrew-bundle = {
      url = "github:homebrew/homebrew-bundle";
      flake = false;
    };

    homebrew-core = {
      url = "github:homebrew/homebrew-core";
      flake = false;
    };

    homebrew-cask = {
      url = "github:homebrew/homebrew-cask";
      flake = false;
    };

    nixos-wsl = {
      url = "github:nix-community/NixOS-WSL/main";
      inputs.nixpkgs.follows = "nixpkgs";
    };

  };

  outputs = {
    self,
    nixpkgs,
    nix-darwin,
    ...
  } @ inputs: let
    inherit (self) outputs;

    systems = [
      "x86_64-linux"
      "aarch64-darwin"
      # Add x86_64-darwin if needed for mair
      "x86_64-darwin"
    ];

    forAllSystems = nixpkgs.lib.genAttrs systems;
  in {
    # Enables `nix fmt` at root of repo to format all nix files
    formatter = forAllSystems (system: nixpkgs.legacyPackages.${system}.alejandra);

    # Development shells with Dagger CLI and utilities
    devShells = forAllSystems (system: let
      pkgs = nixpkgs.legacyPackages.${system};
    in {
      default = pkgs.mkShell {
        name = "doomlab-dev";
        packages = with pkgs; [
          # Core development tools
          git
          gh
          jq
          curl
          
          # Container and orchestration tools
          dagger
          podman
          podman-compose
          buildah
          skopeo
          
          # Backup and storage tools
          kopia
          rclone
          
          # Monitoring and debugging
          dig
          netcat
          htop
          
          # Nix development
          alejandra
          nix-prefetch-git
          nix-tree
        ];
        
        shellHook = ''
          echo "🚀 doomlab-corrupted development environment"
          echo "   Dagger: $(${pkgs.dagger}/bin/dagger version)"
          echo "   Available commands:"
          echo "     - dagger: Container orchestration"
          echo "     - nixarr-migrate: Service migration utilities"
          echo "     - dagger-nixarr-summary: Integration status"
          echo ""
          echo "   Quick start:"
          echo "     1. nixos-rebuild switch --flake ."
          echo "     2. nixarr-migrate status"
          echo "     3. dagger call --help"
        '';
      };
    });

    # Packages exported by this flake
    packages = forAllSystems (system: let
      pkgs = nixpkgs.legacyPackages.${system};
    in {
      # Dagger CLI with proper configuration
      dagger = pkgs.dagger;
      
      # Utility scripts for migration and management
      nixarr-migration-tools = pkgs.writeShellApplication {
        name = "nixarr-migration-tools";
        runtimeInputs = [ pkgs.dagger pkgs.curl pkgs.jq pkgs.systemd ];
        text = builtins.readFile ./scripts/migration-tools.sh;
      };
    });

    darwinConfigurations = {
      mair = nix-darwin.lib.darwinSystem {
        system = "x86_64-darwin"; # Specify system for mair
        specialArgs = {inherit inputs outputs;};
        modules = [./machines/mair/configuration.nix];
      };
      mac1chng = nix-darwin.lib.darwinSystem {
        system = "aarch64-darwin"; # Specify system for mac1chng
        specialArgs = {inherit inputs outputs;};
        modules = [./machines/mac1chng/configuration.nix];
      };
    };

    nixosConfigurations = {
      workchng = nixpkgs.lib.nixosSystem {
        system = "x86_64-linux";
        specialArgs = {inherit inputs outputs;};
        modules = [./machines/workchng/configuration.nix];
      };

      dsk1chng = nixpkgs.lib.nixosSystem {
        system = "x86_64-linux";
        specialArgs = {inherit inputs outputs;};
        modules = [./machines/dsk1chng/configuration.nix];
      };

      iso1chng = nixpkgs.lib.nixosSystem {
        system = "x86_64-linux";
        specialArgs = {inherit inputs outputs;};
        modules = [
          (nixpkgs + "/nixos/modules/installer/cd-dvd/installation-cd-minimal.nix")
          ./machines/iso1chng/configuration.nix
        ];
      };

      svr1chng = nixpkgs.lib.nixosSystem {
        system = "x86_64-linux";
        specialArgs = {inherit inputs outputs;};
        modules = [./machines/svr1chng/configuration.nix];
      };

      svr2chng = nixpkgs.lib.nixosSystem {
        system = "x86_64-linux";
        specialArgs = {inherit inputs outputs;};
        modules = [./machines/svr2chng/configuration.nix];
      };

      svr3chng = nixpkgs.lib.nixosSystem {
        system = "x86_64-linux";
        specialArgs = {inherit inputs outputs;};
        modules = [./machines/svr3chng/configuration.nix];
      };

      noir = nixpkgs.lib.nixosSystem {
        system = "x86_64-linux";
        specialArgs = {inherit inputs outputs;};
        modules = [./machines/noir/configuration.nix];
      };

      zinc = nixpkgs.lib.nixosSystem {
        system = "x86_64-linux";
        specialArgs = {inherit inputs outputs;};
        modules = [./machines/zinc/configuration.nix];
      };

      # Add vmnixos configuration
      vmnixos = nixpkgs.lib.nixosSystem {
        system = "x86_64-linux";
        specialArgs = { inherit inputs outputs; };
        modules = [ ./machines/vmnixos/configuration.nix ];
      };
    };
  };
}