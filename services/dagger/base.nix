# NixOS Module Template for Dagger-managed Services
# Provides declarative integration between NixOS systemd and Dagger pipelines
# Maintains all existing functionality while adding Dagger orchestration capabilities

{ config, lib, pkgs, ... }:

with lib;

let
  cfg = config.services.dagger;
  
  # Dagger binary with proper configuration
  daggerBin = pkgs.dagger.overrideAttrs (old: {
    # Ensure Dagger uses the correct engine version
    buildInputs = old.buildInputs or [] ++ [ pkgs.buildah pkgs.podman ];
  });
  
  # Generate Dagger configuration from NixOS config
  daggerConfig = pkgs.writeText "dagger-config.json" (builtins.toJSON {
    # Bridge NixOS configuration to Dagger
    secrets = {
      cloudflare = {
        email = if cfg.secrets.cloudflare.email != null 
                then cfg.secrets.cloudflare.email 
                else "";
        apiKey = if cfg.secrets.cloudflare.apiKey != null
                then cfg.secrets.cloudflare.apiKey
                else "";
      };
      kopia = {
        repositoryToken = if cfg.secrets.kopia.repositoryToken != null
                        then cfg.secrets.kopia.repositoryToken
                        else "";
      };
    };
    network = cfg.network;
    storage = cfg.storage;
    ports = cfg.ports;
  });
  
  # Service management script that coordinates NixOS systemd with Dagger
  serviceManager = pkgs.writeShellScript "dagger-service-manager" ''
    #!/bin/bash
    set -euo pipefail
    
    ACTION="$1"
    SERVICE="$2"
    
    DAGGER_CONFIG="${daggerConfig}"
    DAGGER_DIR="${cfg.workingDirectory}"
    
    # Function to validate NFS mount availability
    validate_nfs_storage() {
      if [ -d "/mnt/docker-data" ]; then
        echo "Checking NFS mount availability..."
        
        # Test if NFS mount is accessible
        if mountpoint -q "/mnt/docker-data"; then
          echo "✓ NFS mount /mnt/docker-data is available"
          
          # Test write access
          if touch "/mnt/docker-data/.dagger-test" 2>/dev/null; then
            rm -f "/mnt/docker-data/.dagger-test"
            echo "✓ NFS mount is writable"
          else
            echo "✗ NFS mount is not writable"
            return 1
          fi
        else
          echo "✗ NFS mount /mnt/docker-data is not available"
          echo "Attempting to mount NFS..."
          mount "/mnt/docker-data" || {
            echo "✗ Failed to mount NFS, service may not function properly"
            return 1
          }
        fi
      fi
      return 0
    }
    
    # Validate storage before service operations
    case "$ACTION" in
      start|restart|build)
        validate_nfs_storage || {
          echo "Warning: NFS storage validation failed, continuing with degraded functionality"
        }
        ;;
    esac
    
    cd "$DAGGER_DIR"
    
    case "$ACTION" in
      start)
        echo "Starting Dagger-managed service: $SERVICE"
        ${daggerBin}/bin/dagger call services.$SERVICE.deploy \
          --config "$DAGGER_CONFIG"
        ;;
      stop) 
        echo "Stopping Dagger-managed service: $SERVICE"
        ${daggerBin}/bin/dagger call services.$SERVICE.stop \
          --config "$DAGGER_CONFIG"
        ;;
      restart)
        echo "Restarting Dagger-managed service: $SERVICE"
        $0 stop "$SERVICE" || true
        sleep 2
        $0 start "$SERVICE"
        ;;
      status)
        echo "Checking status of Dagger-managed service: $SERVICE"
        ${daggerBin}/bin/dagger call services.$SERVICE.health \
          --config "$DAGGER_CONFIG"
        ;;
      build)
        echo "Building Dagger-managed service: $SERVICE"
        ${daggerBin}/bin/dagger call services.$SERVICE.build \
          --config "$DAGGER_CONFIG"
        ;;
      *)
        echo "Usage: $0 {start|stop|restart|status|build} <service>"
        exit 1
        ;;
    esac
  '';

in {
  options.services.dagger = {
    enable = mkEnableOption "Dagger service orchestration";
    
    workingDirectory = mkOption {
      type = types.path;
      default = "/var/lib/dagger";
      description = "Working directory for Dagger operations";
    };
    
    projectDirectory = mkOption {
      type = types.path;
      default = "${config.users.users.orther.home}/git/doomlab-corrupted/dagger";
      description = "Path to Dagger project directory with CUE files";
    };
    
    # Configuration that bridges to existing NixOS setup
    secrets = {
      cloudflare = {
        email = mkOption {
          type = types.nullOr types.str;
          default = if config.sops.secrets ? "cloudflare-api-email" 
                   then config.sops.secrets."cloudflare-api-email".path 
                   else null;
          description = "Path to Cloudflare API email secret";
        };
        
        apiKey = mkOption {
          type = types.nullOr types.str;
          default = if config.sops.secrets ? "cloudflare-api-key"
                   then config.sops.secrets."cloudflare-api-key".path
                   else null;
          description = "Path to Cloudflare API key secret";
        };
      };
      
      kopia = {
        repositoryToken = mkOption {
          type = types.nullOr types.str;
          default = if config.sops.secrets ? "kopia-repository-token"
                   then config.sops.secrets."kopia-repository-token".path
                   else null;
          description = "Path to Kopia repository token secret";
        };
      };
    };
    
    network = mkOption {
      type = types.attrs;
      default = {
        domain = "orther.dev";
        tailscaleNetwork = "100.64.0.0/10";
        localNetwork = "10.0.10.0/24";
        dns = {
          primary = "1.1.1.1";
          secondary = "1.0.0.1";
        };
      };
      description = "Network configuration for Dagger services";
    };
    
    storage = mkOption {
      type = types.attrs;
      default = {
        persistRoot = "/nix/persist";
        mediaRoot = "/fun";
        stateRoot = "/var/lib";
      };
      description = "Storage paths for Dagger services";
    };
    
    ports = mkOption {
      type = types.attrs;
      default = {
        jellyfin = 8096;
        prowlarr = 9696;
        radarr = 7878;
        sonarr = 8989;
        transmission = 9091;
        homebridge = 8581;
        scrypted = 10443;
      };
      description = "Service port mappings";
    };
    
    services = mkOption {
      type = types.listOf types.str;
      default = [];
      description = "List of Dagger-managed services to enable";
      example = [ "automation.homebridge" "automation.scrypted" "media.transcoding" ];
    };
    
    enableSystemdIntegration = mkOption {
      type = types.bool;
      default = true;
      description = "Enable systemd service integration for Dagger workflows";
    };
    
    enableBackupIntegration = mkOption {
      type = types.bool; 
      default = true;
      description = "Enable integration with existing Kopia backup system";
    };
    
    enableMonitoring = mkOption {
      type = types.bool;
      default = true;
      description = "Enable monitoring and health checks for Dagger services";
    };
  };
  
  config = mkIf cfg.enable {
    
    # Ensure required packages are available
    environment.systemPackages = with pkgs; [
      daggerBin
      jq
      curl
      kopia  # For backup integration
    ];
    
    # Ensure Podman is configured for Dagger
    virtualisation.podman = {
      enable = true;
      dockerCompat = true;
      autoPrune.enable = true;
      defaultNetwork.settings.dns_enabled = true;
    };
    
    # Create working directory and setup
    systemd.tmpfiles.rules = [
      "d ${cfg.workingDirectory} 0755 root root"
      "L+ ${cfg.workingDirectory}/dagger - - - - ${cfg.projectDirectory}"
    ];
    
    # Systemd services for each Dagger-managed service
    systemd.services = mkMerge [
      # Main Dagger coordinator service
      {
        "dagger-coordinator" = {
          description = "Dagger Service Coordinator";
          wantedBy = [ "multi-user.target" ];
          after = [ "podman.service" "network.target" ] ++ 
                  (optional (config.fileSystems ? "/mnt/docker-data") "mnt-docker-data.mount");
          requires = [ "podman.service" ] ++
                    (optional (config.fileSystems ? "/mnt/docker-data") "mnt-docker-data.mount");
          
          environment = {
            DAGGER_CACHE_DIR = "${cfg.workingDirectory}/cache";
            DAGGER_CONFIG_FILE = toString daggerConfig;
          };
          
          serviceConfig = {
            Type = "oneshot";
            RemainAfterExit = true;
            ExecStart = "${pkgs.bash}/bin/bash -c 'echo Dagger coordinator initialized'";
            ExecReload = "${serviceManager} restart all";
            WorkingDirectory = cfg.workingDirectory;
            User = "root";
            Group = "root";
          };
          
          # Ensure secrets are available
          requisite = mkIf (cfg.secrets.kopia.repositoryToken != null) [ 
            "sops-nix.service" 
          ];
        };
      }
      
      # Individual service management
      (mkMerge (map (service: 
        let 
          serviceName = "dagger-${builtins.replaceStrings ["."] ["-"] service}";
          serviceCategory = builtins.head (lib.splitString "." service);
          servicePart = builtins.elemAt (lib.splitString "." service) 1;
        in {
          "${serviceName}" = {
            description = "Dagger-managed ${service} service";
            wantedBy = [ "multi-user.target" ];
            after = [ "dagger-coordinator.service" ] ++ 
                    (optional (config.fileSystems ? "/mnt/docker-data") "mnt-docker-data.mount");
            requires = [ "dagger-coordinator.service" ] ++
                      (optional (config.fileSystems ? "/mnt/docker-data") "mnt-docker-data.mount");
            
            serviceConfig = {
              Type = "oneshot";
              RemainAfterExit = true;
              ExecStart = "${serviceManager} start ${service}";
              ExecStop = "${serviceManager} stop ${service}";
              ExecReload = "${serviceManager} restart ${service}";
              WorkingDirectory = cfg.workingDirectory;
              User = "root";
              Group = "root";
              
              # Resource limits aligned with existing resource-limits.nix
              MemoryMax = "2G";
              CPUQuota = "200%";
              TasksMax = "1000";
            };
            
            # Health check integration
            onFailure = mkIf cfg.enableMonitoring [ "dagger-health-${serviceName}.service" ];
          };
          
          # Health check service
          "dagger-health-${serviceName}" = mkIf cfg.enableMonitoring {
            description = "Health check for Dagger-managed ${service}";
            serviceConfig = {
              Type = "oneshot";
              ExecStart = "${serviceManager} status ${service}";
              User = "root";
              Group = "root";
            };
          };
        }
      ) cfg.services))
    ];
    
    # Systemd timers for automated operations
    systemd.timers = mkMerge [
      # Health monitoring timer
      (mkIf cfg.enableMonitoring {
        "dagger-health-check" = {
          description = "Periodic health check for Dagger services";
          wantedBy = [ "timers.target" ];
          timerConfig = {
            OnCalendar = "*:0/15"; # Every 15 minutes
            Persistent = true;
            RandomizedDelaySec = "1m";
          };
        };
      })
      
      # Backup coordination timer
      (mkIf cfg.enableBackupIntegration {
        "dagger-backup-coordination" = {
          description = "Coordinate backups for Dagger services";
          wantedBy = [ "timers.target" ];
          timerConfig = {
            OnCalendar = "*-*-* 03:00:00";
            Persistent = true;
            RandomizedDelaySec = "30m";
          };
        };
      })
    ];
    
    # Corresponding timer services
    systemd.services = mkMerge [
      (mkIf cfg.enableMonitoring {
        "dagger-health-check" = {
          description = "Health check all Dagger services";
          serviceConfig = {
            Type = "oneshot";
            ExecStart = pkgs.writeShellScript "dagger-health-check-all" ''
              #!/bin/bash
              set -euo pipefail
              
              echo "Running health checks for all Dagger services..."
              
              services=(${lib.concatStringsSep " " (map (s: "\"${s}\"") cfg.services)})
              failed_services=()
              
              for service in "''${services[@]}"; do
                echo "Checking $service..."
                if ! ${serviceManager} status "$service"; then
                  failed_services+=("$service")
                fi
              done
              
              if [ ''${#failed_services[@]} -gt 0 ]; then
                echo "Failed services: ''${failed_services[*]}"
                exit 1
              fi
              
              echo "All Dagger services are healthy"
            '';
            User = "root";
            Group = "root";
          };
        };
      })
      
      (mkIf cfg.enableBackupIntegration {
        "dagger-backup-coordination" = {
          description = "Coordinate backups for Dagger services";  
          serviceConfig = {
            Type = "oneshot";
            ExecStart = "${daggerBin}/bin/dagger call pipeline.backup --config ${daggerConfig}";
            WorkingDirectory = cfg.workingDirectory;
            User = "root";
            Group = "root";
          };
          
          # Ensure this runs after other backup services
          after = [ "backup-homebridge.service" "backup-scrypted.service" ];
        };
      })
    ];
    
    # Persistence configuration 
    environment.persistence."/nix/persist" = mkIf config.environment.persistence."/nix/persist".enable {
      directories = [
        cfg.workingDirectory
        "/var/lib/containers" # Shared with existing container services
      ];
    };
    
    # Firewall configuration for Dagger services
    networking.firewall = {
      # Allow necessary ports for Dagger engine communication
      allowedTCPPorts = [ 
        # Add any additional ports needed by Dagger services
      ];
      
      # Maintain existing firewall rules for services
      extraCommands = mkIf (elem "automation.homebridge" cfg.services || elem "automation.scrypted" cfg.services) ''
        # Homekit and automation device access (from existing configuration)
        iptables -A nixos-fw -p tcp --source ${cfg.network.localNetwork} -j nixos-fw-accept
        iptables -A nixos-fw -p udp --source ${cfg.network.localNetwork} -j nixos-fw-accept
      '';
      
      extraStopCommands = mkIf (elem "automation.homebridge" cfg.services || elem "automation.scrypted" cfg.services) ''
        iptables -D nixos-fw -p tcp --source ${cfg.network.localNetwork} -j nixos-fw-accept || true
        iptables -D nixos-fw -p udp --source ${cfg.network.localNetwork} -j nixos-fw-accept || true
      '';
    };
    
    # Assertions to ensure proper configuration
    assertions = [
      {
        assertion = cfg.workingDirectory != cfg.projectDirectory;
        message = "Dagger working directory must be different from project directory";
      }
      {
        assertion = config.virtualisation.podman.enable;
        message = "Podman must be enabled for Dagger service management";
      }
      {
        assertion = all (service: 
          elem (builtins.head (lib.splitString "." service)) ["automation" "media" "infrastructure"]
        ) cfg.services;
        message = "All Dagger services must be in a valid category (automation, media, infrastructure)";
      }
    ];
  };
}