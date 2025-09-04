{
  inputs,
  config,
  pkgs,
  lib,
  ...
}: {
  imports = [
    inputs.sops-nix.nixosModules.sops

    ./_packages.nix
    ./secrets-rotation.nix
    ./resource-limits.nix
  ];

  boot.loader = {
    systemd-boot = {
      enable = true;
      configurationLimit = 5;
    };
    efi.canTouchEfiVariables = true;
    timeout = 10;
  };

  nixpkgs.config.allowUnfree = true;
  nix = {
    gc = {
      automatic = true;
      dates = "weekly";
      options = "--delete-older-than 7d";
    };
    settings = {
      experimental-features = "nix-command flakes";
      auto-optimise-store = true;
      
      # Configure binary caches for faster builds
      substituters = [
        "https://cache.nixos.org/"
        "https://nix-community.cachix.org"
        "https://devenv.cachix.org"
        "https://nixpkgs-unfree.cachix.org"
      ];
      trusted-public-keys = [
        "cache.nixos.org-1:6NCHdD59X431o0gWypbMrAURkbJ16ZPMQFGspcDShjY="
        "nix-community.cachix.org-1:mB9FSh9qf2dCimDSUo8Zy7bkq5CX+/rkCWyvRCYg3Fs="
        "devenv.cachix.org-1:w1cLUi8dv3hnoSPGAuibQv+f9TZLr6cv/Hm9XgU50cw="
        "nixpkgs-unfree.cachix.org-1:hqvoInulhbV4nJ9yJOEr+4wxhDV4xq2d1DK7S6Nqlt4="
      ];
      
      # Build optimization settings
      builders-use-substitutes = true;
      max-jobs = "auto";  # Use all available CPU cores
      cores = 0;  # Use all available CPU cores per job
      
      # Increase parallel downloads for faster cache fetching
      max-substitution-jobs = 16;
      http-connections = 25;
      
      # Enable distributed builds if remote builders are available
      # builders = "@/etc/nix/machines";
      
      # Trust binary caches from these users (for remote builds)
      trusted-users = [ "root" "@wheel" ];
    };
    
    # Optimize build performance
    extraOptions = ''
      # Keep build dependencies for faster rebuilds
      keep-outputs = true
      keep-derivations = true
      
      # Enable parallel building
      build-cores = 0
      
      # Increase timeout for large builds
      stalled-download-timeout = 300
      
      # Enable compression for network transfers
      compress-build-log = true
    '';
  };

  sops = {
    defaultSopsFile = ./../../secrets/secrets.yaml;
    age.sshKeyPaths = ["/nix/secret/initrd/ssh_host_ed25519_key"];
    secrets."user-password".neededForUsers = true;
    secrets."user-password" = {};
    # inspo: https://github.com/Mic92/sops-nix/issues/427
    gnupg.sshKeyPaths = [];
  };

  users.mutableUsers = false;
  users.users.orther = {
    isNormalUser = true;
    description = "orther";
    extraGroups = ["networkmanager" "wheel"];
    openssh.authorizedKeys.keys = [
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIDvJx1pyQwQVPPdXlqhJEtUlKyVr4HbZvgbjZ96t75Re"
    ];
    shell = pkgs.zsh;
    hashedPasswordFile = config.sops.secrets."user-password".path;
  };

  services = {
    openssh = {
      enable = true;
      settings = {
        PermitRootLogin = "no";
        PasswordAuthentication = false;
      };
      openFirewall = true;
    };
    fstrim.enable = true;
  };

  networking = {
    firewall.enable = true;
    networkmanager.enable = true;
  };

  # Disable wait-online services to speed up boot (allow override)
  # See: https://github.com/NixOS/nixpkgs/issues/180175#issuecomment-1658731959
  systemd.services.NetworkManager-wait-online.enable = lib.mkDefault false;
  systemd.services.systemd-networkd-wait-online.enable = lib.mkDefault false;

  programs.zsh.enable = true;
  
  # Implement granular sudo rules instead of passwordless access
  security.sudo = {
    wheelNeedsPassword = true;  # Require passwords by default
    extraRules = [{
      users = ["orther"];
      commands = [
        # Allow passwordless system management commands
        { command = "${pkgs.systemd}/bin/systemctl restart *"; options = ["NOPASSWD"]; }
        { command = "${pkgs.systemd}/bin/systemctl start *"; options = ["NOPASSWD"]; }
        { command = "${pkgs.systemd}/bin/systemctl stop *"; options = ["NOPASSWD"]; }
        { command = "${pkgs.systemd}/bin/systemctl status *"; options = ["NOPASSWD"]; }
        { command = "${pkgs.nixos-rebuild}/bin/nixos-rebuild switch*"; options = ["NOPASSWD"]; }
        { command = "${pkgs.nixos-rebuild}/bin/nixos-rebuild dry-build*"; options = ["NOPASSWD"]; }
        { command = "${pkgs.nix}/bin/nix-collect-garbage*"; options = ["NOPASSWD"]; }
      ];
    }];
  };
  
  # Enable resource limits and monitoring
  services.resource-limits.enable = true;
  
  time.timeZone = "America/Los_Angeles";
  zramSwap.enable = true;

  # Input validation assertions
  assertions = [
    {
      assertion = config.networking.hostName != "";
      message = "networking.hostName must be set for proper system identification";
    }
    {
      assertion = builtins.length config.users.users.orther.openssh.authorizedKeys.keys > 0;
      message = "At least one SSH key must be configured for user orther";
    }
    {
      assertion = config.services.openssh.enable;
      message = "SSH service must be enabled for remote access";
    }
    {
      assertion = config.networking.firewall.enable;
      message = "Firewall must be enabled for security";
    }
  ];

  environment.persistence."/nix/persist" = {
    # Hide these mounts from the sidebar of file managers
    hideMounts = true;

    directories = [
      "/var/log"
      # inspo: https://github.com/nix-community/impermanence/issues/178
      "/var/lib/nixos"
      # Persist network manager connections if needed
      # "/etc/NetworkManager/system-connections"
    ];

    files = [
      "/etc/machine-id"
      "/etc/ssh/ssh_host_ed25519_key.pub"
      "/etc/ssh/ssh_host_ed25519_key"
      "/etc/ssh/ssh_host_rsa_key.pub"
      "/etc/ssh/ssh_host_rsa_key"
    ];

    users."orther" = {
      directories = [
        "git" # Persists /home/orther/git -> /nix/persist/home/orther/git

        ".cache"
        ".config"
        ".config/nvim" # Persist Neovim config
        ".local"
        {
          directory = ".gnupg";
          mode = "0700";
        }
        {
          directory = ".ssh";
          mode = "0700";
        }
      ];
      files = [
        ".zsh_history"
        #".zshrc" # Managed by home-manager
      ];
    };
  };

  # https://nixos.wiki/wiki/FAQ/When_do_I_update_stateVersion
  system.stateVersion = "23.11"; # Keep this consistent unless intentionally upgrading state
}