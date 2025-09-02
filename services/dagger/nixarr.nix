# Dagger-Enhanced Nixarr Services
# NixOS module that provides enhanced nixarr services via Dagger containers
# Maintains compatibility with existing configuration while adding Dagger capabilities

{
  config,
  lib,
  pkgs,
  ...
}:

with lib;

let
  cfg = config.services.dagger.nixarr;

  # Port definitions that match existing nixarr configuration
  defaultPorts = {
    sonarr = 8989;
    radarr = 7878;
    prowlarr = 9696;
    bazarr = 6767;
    transmission = 9091;
    jellyfin = 8096;
  };

  # Service definition helper
  mkDaggerService = name: serviceConfig: {
    description = "Dagger-managed ${name} service";
    after = ["network.target" "dagger-secrets.service"] ++ 
            (optional (config.fileSystems ? "/mnt/docker-data") "mnt-docker-data.mount");
    wants = ["dagger-secrets.service"];
    wantedBy = ["multi-user.target"];
    requires = optional (config.fileSystems ? "/mnt/docker-data") ["mnt-docker-data.mount"];

    environment = {
      DAGGER_CACHE_DIR = "/var/cache/dagger";
      DAGGER_CONFIG_DIR = "/etc/dagger";
    };

    serviceConfig = {
      Type = "exec";
      User = "dagger";
      Group = "dagger";
      Restart = "always";
      RestartSec = "10s";
      TimeoutStopSec = "60s";
      
      # Security settings
      NoNewPrivileges = true;
      ProtectSystem = "strict";
      ProtectHome = true;
      ReadWritePaths = [
        "/var/lib/nixarr"
        "/var/cache/dagger"
        "/tmp"
        config.services.dagger.nixarr.storage.mediaRoot
      ];
      
      ExecStart = "${pkgs.dagger}/bin/dagger call services nixarr ${name} container run";
      ExecStop = "${pkgs.dagger}/bin/dagger call services nixarr ${name} container stop";
      
      # Health check
      ExecStartPost = pkgs.writeShellScript "wait-for-${name}" ''
        for i in {1..30}; do
          if ${pkgs.curl}/bin/curl -f -s --connect-timeout 5 "http://127.0.0.1:${toString serviceConfig.port}/ping" > /dev/null 2>&1; then
            echo "${name} is ready"
            exit 0
          fi
          echo "Waiting for ${name}... ($i/30)"
          sleep 10
        done
        echo "${name} failed to start within 5 minutes"
        exit 1
      '';
    };

    # Dependency management
    requisite = serviceConfig.requires or [];
    wants = serviceConfig.wants or [];
  };

  # SOPS secrets configuration for nixarr services
  nixarrSecrets = {
    "nixarr/sonarr/api-key" = {
      owner = "dagger";
      group = "dagger";
      mode = "0440";
    };
    "nixarr/radarr/api-key" = {
      owner = "dagger";
      group = "dagger";
      mode = "0440";
    };
    "nixarr/prowlarr/api-key" = {
      owner = "dagger";
      group = "dagger";
      mode = "0440";
    };
    "nixarr/bazarr/api-key" = {
      owner = "dagger";
      group = "dagger";
      mode = "0440";
    };
    "nixarr/transmission/rpc-password" = {
      owner = "dagger";
      group = "dagger";
      mode = "0440";
    };
    "nixarr/jellyfin/api-key" = {
      owner = "dagger";
      group = "dagger";
      mode = "0440";
    };
  };
in

{
  options.services.dagger.nixarr = {
    enable = mkEnableOption "Enhanced nixarr services via Dagger";

    # Compatibility options that mirror existing nixarr module
    mediaDir = mkOption {
      type = types.str;
      default = "/fun";
      description = "Root directory for media files (movies, TV shows, etc.)";
    };

    stateDir = mkOption {
      type = types.str;
      default = "/var/lib/nixarr";
      description = "Directory for service configuration and databases";
    };

    storage = {
      mediaRoot = mkOption {
        type = types.str;
        default = cfg.mediaDir;
        description = "Media storage root directory";
      };
      
      stateRoot = mkOption {
        type = types.str;
        default = cfg.stateDir;
        description = "Service state root directory";
      };
      
      persistRoot = mkOption {
        type = types.str;
        default = "/nix/persist";
        description = "Persistence root directory";
      };
    };

    # Network configuration
    network = {
      domain = mkOption {
        type = types.str;
        default = "orther.dev";
        description = "Primary domain for services";
      };
      
      ports = mkOption {
        type = types.attrsOf types.port;
        default = defaultPorts;
        description = "Port assignments for services";
      };
    };

    # Service-specific enablement (matching existing nixarr)
    sonarr = {
      enable = mkEnableOption "Dagger-enhanced Sonarr service";
      
      port = mkOption {
        type = types.port;
        default = cfg.network.ports.sonarr;
        description = "Sonarr web interface port";
      };
      
      enhancedFeatures = mkOption {
        type = types.bool;
        default = true;
        description = "Enable Dagger-specific enhancements (health monitoring, backup integration)";
      };
    };

    radarr = {
      enable = mkEnableOption "Dagger-enhanced Radarr service";
      
      port = mkOption {
        type = types.port;
        default = cfg.network.ports.radarr;
        description = "Radarr web interface port";
      };
      
      enhancedFeatures = mkOption {
        type = types.bool;
        default = true;
        description = "Enable Dagger-specific enhancements";
      };
    };

    prowlarr = {
      enable = mkEnableOption "Dagger-enhanced Prowlarr service";
      
      port = mkOption {
        type = types.port;
        default = cfg.network.ports.prowlarr;
        description = "Prowlarr web interface port";
      };
      
      enhancedFeatures = mkOption {
        type = types.bool;
        default = true;
        description = "Enable Dagger-specific enhancements";
      };
    };

    bazarr = {
      enable = mkEnableOption "Dagger-enhanced Bazarr service";
      
      port = mkOption {
        type = types.port;
        default = cfg.network.ports.bazarr;
        description = "Bazarr web interface port";
      };
      
      enhancedFeatures = mkOption {
        type = types.bool;
        default = true;
        description = "Enable Dagger-specific enhancements";
      };
    };

    transmission = {
      enable = mkEnableOption "Dagger-enhanced Transmission service";
      
      port = mkOption {
        type = types.port;
        default = cfg.network.ports.transmission;
        description = "Transmission web interface port";
      };
      
      peerPort = mkOption {
        type = types.port;
        default = 46634;
        description = "Transmission peer communication port";
      };
      
      username = mkOption {
        type = types.str;
        default = "orther";
        description = "Transmission RPC username";
      };
      
      enhancedFeatures = mkOption {
        type = types.bool;
        default = true;
        description = "Enable Dagger-specific enhancements";
      };
    };

    jellyfin = {
      enable = mkEnableOption "Dagger-enhanced Jellyfin service";
      
      port = mkOption {
        type = types.port;
        default = cfg.network.ports.jellyfin;
        description = "Jellyfin web interface port";
      };
      
      hardwareAcceleration = mkOption {
        type = types.bool;
        default = false;
        description = "Enable hardware acceleration for transcoding";
      };
      
      enhancedFeatures = mkOption {
        type = types.bool;
        default = true;
        description = "Enable Dagger-specific enhancements";
      };
    };

    # Migration and compatibility settings
    migration = {
      enableCompatibilityMode = mkOption {
        type = types.bool;
        default = true;
        description = "Enable side-by-side operation with existing nixarr services";
      };
      
      dataImportPath = mkOption {
        type = types.nullOr types.str;
        default = null;
        description = "Path to import existing nixarr data from";
      };
      
      backupBeforeMigration = mkOption {
        type = types.bool;
        default = true;
        description = "Create backup before migrating to Dagger services";
      };
    };

    # Enhanced features
    monitoring = {
      enable = mkEnableOption "Enhanced monitoring and health checks";
      
      healthCheckInterval = mkOption {
        type = types.str;
        default = "5m";
        description = "Health check interval";
      };
      
      alerting = mkOption {
        type = types.bool;
        default = false;
        description = "Enable alerting for service failures";
      };
    };

    backup = {
      enable = mkEnableOption "Enhanced backup integration";
      
      schedule = mkOption {
        type = types.str;
        default = "daily";
        description = "Backup schedule (systemd timer format)";
      };
      
      retention = mkOption {
        type = types.str;
        default = "30d";
        description = "Backup retention period";
      };
    };
  };

  config = mkIf cfg.enable {
    # Ensure dagger is available
    environment.systemPackages = [pkgs.dagger];

    # Create dagger user and group
    users.groups.dagger = {};
    users.users.dagger = {
      isSystemUser = true;
      group = "dagger";
      extraGroups = ["docker" "podman"];  # For container management
      home = "/var/lib/dagger";
      createHome = true;
    };

    # SOPS secrets configuration
    sops.secrets = mkIf config.sops.secrets != {} nixarrSecrets;

    # Create required directories
    systemd.tmpfiles.rules = [
      # Service state directories
      "d ${cfg.storage.stateRoot} 0755 dagger dagger -"
      "d ${cfg.storage.stateRoot}/nixarr 0755 dagger dagger -"
      "d ${cfg.storage.stateRoot}/nixarr/sonarr 0755 dagger dagger -"
      "d ${cfg.storage.stateRoot}/nixarr/radarr 0755 dagger dagger -"
      "d ${cfg.storage.stateRoot}/nixarr/prowlarr 0755 dagger dagger -"
      "d ${cfg.storage.stateRoot}/nixarr/bazarr 0755 dagger dagger -"
      "d ${cfg.storage.stateRoot}/nixarr/transmission 0755 dagger dagger -"
      "d ${cfg.storage.stateRoot}/nixarr/jellyfin 0755 dagger dagger -"
      
      # Media directories
      "d ${cfg.storage.mediaRoot} 0755 dagger dagger -"
      "d ${cfg.storage.mediaRoot}/tv 0755 dagger dagger -"
      "d ${cfg.storage.mediaRoot}/movies 0755 dagger dagger -"
      "d ${cfg.storage.mediaRoot}/downloads 0755 dagger dagger -"
      "d ${cfg.storage.mediaRoot}/watch 0755 dagger dagger -"
      
      # Dagger cache and config
      "d /var/cache/dagger 0755 dagger dagger -"
      "d /etc/dagger 0755 root root -"
      
      # Secrets directory for Dagger
      "d /run/dagger-secrets 0750 dagger dagger -"
      "d /run/dagger-secrets/sonarr 0750 dagger dagger -"
      "d /run/dagger-secrets/radarr 0750 dagger dagger -"
      "d /run/dagger-secrets/prowlarr 0750 dagger dagger -"
      "d /run/dagger-secrets/bazarr 0750 dagger dagger -"
      "d /run/dagger-secrets/transmission 0750 dagger dagger -"
      "d /run/dagger-secrets/jellyfin 0750 dagger dagger -"
    ];

    # Secrets bridge service - copies SOPS secrets to dagger-accessible location
    systemd.services.dagger-secrets = {
      description = "Bridge SOPS secrets to Dagger services";
      after = ["sops-nix.service"];
      wants = ["sops-nix.service"];
      wantedBy = ["multi-user.target"];

      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
        User = "root";
        Group = "root";
      };

      script = ''
        echo "Bridging SOPS secrets to Dagger..."
        
        # Function to safely copy secret if it exists
        copy_secret_if_exists() {
          local sops_path=$1
          local target_path=$2
          
          if [ -f "$sops_path" ]; then
            echo "Copying secret: $sops_path -> $target_path"
            cp "$sops_path" "$target_path"
            chown dagger:dagger "$target_path"
            chmod 0440 "$target_path"
          else
            echo "Warning: Secret not found: $sops_path"
            # Create empty file so service doesn't fail
            touch "$target_path"
            chown dagger:dagger "$target_path"
            chmod 0440 "$target_path"
          fi
        }

        # Copy each service secret if SOPS is configured
        ${optionalString (config.sops.secrets != {}) ''
        copy_secret_if_exists "${config.sops.secrets."nixarr/sonarr/api-key".path or "/dev/null"}" "/run/dagger-secrets/sonarr/api-key"
        copy_secret_if_exists "${config.sops.secrets."nixarr/radarr/api-key".path or "/dev/null"}" "/run/dagger-secrets/radarr/api-key"
        copy_secret_if_exists "${config.sops.secrets."nixarr/prowlarr/api-key".path or "/dev/null"}" "/run/dagger-secrets/prowlarr/api-key"
        copy_secret_if_exists "${config.sops.secrets."nixarr/bazarr/api-key".path or "/dev/null"}" "/run/dagger-secrets/bazarr/api-key"
        copy_secret_if_exists "${config.sops.secrets."nixarr/transmission/rpc-password".path or "/dev/null"}" "/run/dagger-secrets/transmission/rpc-password"
        copy_secret_if_exists "${config.sops.secrets."nixarr/jellyfin/api-key".path or "/dev/null"}" "/run/dagger-secrets/jellyfin/api-key"
        ''}

        echo "Secret bridging completed"
      '';
    };

    # Dagger configuration file
    environment.etc."dagger/config.cue" = {
      text = ''
        package main

        // Configuration that mirrors NixOS settings
        _config: #NixOSConfig & {
          network: {
            domain: "${cfg.network.domain}"
          }
          storage: {
            mediaRoot: "${cfg.storage.mediaRoot}"
            stateRoot: "${cfg.storage.stateRoot}"
            persistRoot: "${cfg.storage.persistRoot}"
          }
          ports: {
            sonarr: ${toString cfg.sonarr.port}
            radarr: ${toString cfg.radarr.port}
            prowlarr: ${toString cfg.prowlarr.port}
            bazarr: ${toString cfg.bazarr.port}
            transmission: ${toString cfg.transmission.port}
            jellyfin: ${toString cfg.jellyfin.port}
          }
        }
      '';
      mode = "0644";
    };

    # Individual service definitions
    systemd.services = 
      # Sonarr service
      (mkIf cfg.sonarr.enable {
        dagger-sonarr = mkDaggerService "sonarr" {
          port = cfg.sonarr.port;
          wants = ["dagger-prowlarr.service"];  # Depends on indexer
        };
      }) //
      
      # Radarr service  
      (mkIf cfg.radarr.enable {
        dagger-radarr = mkDaggerService "radarr" {
          port = cfg.radarr.port;
          wants = ["dagger-prowlarr.service"];  # Depends on indexer
        };
      }) //
      
      # Prowlarr service
      (mkIf cfg.prowlarr.enable {
        dagger-prowlarr = mkDaggerService "prowlarr" {
          port = cfg.prowlarr.port;
        };
      }) //
      
      # Bazarr service
      (mkIf cfg.bazarr.enable {
        dagger-bazarr = mkDaggerService "bazarr" {
          port = cfg.bazarr.port;
          wants = ["dagger-sonarr.service" "dagger-radarr.service"];  # Depends on media managers
        };
      }) //
      
      # Transmission service
      (mkIf cfg.transmission.enable {
        dagger-transmission = mkDaggerService "transmission" {
          port = cfg.transmission.port;
        };
      }) //
      
      # Jellyfin service
      (mkIf cfg.jellyfin.enable {
        dagger-jellyfin = mkDaggerService "jellyfin" {
          port = cfg.jellyfin.port;
        };
      });

    # Service orchestration
    systemd.services.nixarr-orchestrator = mkIf (cfg.sonarr.enable || cfg.radarr.enable || cfg.prowlarr.enable) {
      description = "Nixarr services orchestration";
      after = ["network.target" "dagger-secrets.service"];
      wants = ["dagger-secrets.service"];

      serviceConfig = {
        Type = "oneshot";
        User = "dagger";
        Group = "dagger";
        RemainAfterExit = true;
      };

      script = ''
        echo "Starting nixarr services orchestration..."
        ${pkgs.dagger}/bin/dagger call services nixarr orchestration startup
        echo "Nixarr orchestration completed"
      '';
    };

    # Enhanced monitoring service
    systemd.services.nixarr-monitor = mkIf cfg.monitoring.enable {
      description = "Nixarr services health monitoring";
      after = ["nixarr-orchestrator.service"];

      serviceConfig = {
        Type = "simple";
        User = "dagger";
        Group = "dagger";
        Restart = "always";
        RestartSec = "30s";
      };

      script = ''
        while true; do
          echo "Running nixarr health monitoring..."
          ${pkgs.dagger}/bin/dagger call services nixarr orchestration monitor || {
            echo "Health check failed, alerting..."
            # Add alerting logic here
          }
          sleep ${cfg.monitoring.healthCheckInterval}
        done
      '';
    };

    # Enhanced backup service
    systemd.services.nixarr-backup = mkIf cfg.backup.enable {
      description = "Enhanced nixarr backup via Dagger";
      
      serviceConfig = {
        Type = "oneshot";
        User = "dagger";
        Group = "dagger";
      };

      script = ''
        echo "Starting enhanced nixarr backup..."
        ${pkgs.dagger}/bin/dagger call services nixarr backup backup_all
        echo "Nixarr backup completed"
      '';
    };

    systemd.timers.nixarr-backup = mkIf cfg.backup.enable {
      description = "Enhanced nixarr backup timer";
      wantedBy = ["timers.target"];

      timerConfig = {
        OnCalendar = cfg.backup.schedule;
        RandomizedDelaySec = "1h";
        Persistent = true;
      };
    };

    # Network firewall rules (same as existing nixarr)
    networking.firewall.allowedTCPPorts = 
      (optional cfg.sonarr.enable cfg.sonarr.port) ++
      (optional cfg.radarr.enable cfg.radarr.port) ++
      (optional cfg.prowlarr.enable cfg.prowlarr.port) ++
      (optional cfg.bazarr.enable cfg.bazarr.port) ++
      (optional cfg.transmission.enable cfg.transmission.port) ++
      (optional cfg.jellyfin.enable cfg.jellyfin.port) ++
      (optional cfg.transmission.enable cfg.transmission.peerPort);

    networking.firewall.allowedUDPPorts = 
      (optional cfg.transmission.enable cfg.transmission.peerPort);

    # Persistence configuration (matches existing pattern)
    environment.persistence."/nix/persist" = mkIf config.environment.persistence ? "/nix/persist" {
      directories = [
        "/var/lib/dagger"
        "/var/cache/dagger"
        cfg.storage.stateRoot
      ];
    };
  };
}