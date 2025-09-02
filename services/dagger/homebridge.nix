# Dagger-managed Homebridge Service
# Replaces the existing Podman OCI container with Dagger orchestration
# Maintains all existing functionality while adding enhanced CI/CD and monitoring

{ config, lib, pkgs, ... }:

with lib;

let
  cfg = config.services.dagger.homebridge;
  
in {
  options.services.dagger.homebridge = {
    enable = mkEnableOption "Dagger-managed Homebridge service";
    
    image = mkOption {
      type = types.str;
      default = "ghcr.io/homebridge/homebridge:latest";
      description = "Container image to use for Homebridge";
    };
    
    dataDir = mkOption {
      type = types.path;
      default = "/var/lib/homebridge";
      description = "Directory for Homebridge data";
    };
    
    port = mkOption {
      type = types.port;
      default = 8581;
      description = "Port for Homebridge web interface";
    };
    
    childBridgePorts = mkOption {
      type = types.listOf types.port;
      default = [ 50000 50001 50002 ];
      description = "Ports for Homebridge child bridges";
    };
    
    portRange = mkOption {
      type = types.attrs;
      default = { from = 50100; to = 50200; };
      description = "Port range for additional child bridges";
    };
    
    enableAutoUpdate = mkOption {
      type = types.bool;
      default = true;
      description = "Enable automatic container updates";
    };
    
    enableBackup = mkOption {
      type = types.bool;
      default = true;
      description = "Enable automatic backups via Kopia";
    };
    
    enableMonitoring = mkOption {
      type = types.bool;
      default = true;
      description = "Enable health monitoring and alerts";
    };
    
    network = mkOption {
      type = types.enum [ "host" "bridge" ];
      default = "host";
      description = "Container network mode";
    };
    
    extraDaggerConfig = mkOption {
      type = types.attrs;
      default = {};
      description = "Additional Dagger pipeline configuration";
    };
  };
  
  config = mkIf cfg.enable {
    
    # Ensure base Dagger service is enabled
    services.dagger = {
      enable = true;
      services = [ "automation.homebridge" ];
      enableBackupIntegration = cfg.enableBackup;
      enableMonitoring = cfg.enableMonitoring;
    };
    
    # Ensure SOPS secrets are available for backup
    services.dagger.secrets.enable = mkIf cfg.enableBackup true;
    
    # Create data directory
    systemd.tmpfiles.rules = [
      "d ${cfg.dataDir} 0755 root root"
    ];
    
    # Configure firewall (same as existing homebridge.nix)
    networking.firewall = {
      allowedTCPPorts = [ 5353 cfg.port ] ++ cfg.childBridgePorts;
      allowedUDPPorts = [ 5353 ];
      
      allowedTCPPortRanges = [
        cfg.portRange
      ];
    };
    
    # Nginx reverse proxy configuration (same as existing)
    services.nginx.virtualHosts."home.orther.dev" = {
      forceSSL = true;
      useACMEHost = "orther.dev";
      locations."/" = {
        recommendedProxySettings = true;
        proxyPass = "http://127.0.0.1:${toString cfg.port}";
      };
    };
    
    # Dagger-specific systemd service that replaces podman-homebridge
    systemd.services."dagger-automation-homebridge" = {
      description = "Dagger-managed Homebridge service";
      wantedBy = [ "multi-user.target" ];
      after = [ 
        "network.target" 
        "dagger-coordinator.service" 
        "dagger-secret-injection.service"
      ];
      requires = [ 
        "dagger-coordinator.service"
      ] ++ optional cfg.enableBackup "dagger-secret-injection.service";
      
      environment = {
        DAGGER_HOMEBRIDGE_IMAGE = cfg.image;
        DAGGER_HOMEBRIDGE_DATA_DIR = cfg.dataDir;
        DAGGER_HOMEBRIDGE_PORT = toString cfg.port;
        DAGGER_HOMEBRIDGE_NETWORK = cfg.network;
        DAGGER_HOMEBRIDGE_ENABLE_AUTOUPDATE = if cfg.enableAutoUpdate then "true" else "false";
        DAGGER_HOMEBRIDGE_ENABLE_BACKUP = if cfg.enableBackup then "true" else "false";
        DAGGER_HOMEBRIDGE_ENABLE_MONITORING = if cfg.enableMonitoring then "true" else "false";
      };
      
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
        WorkingDirectory = config.services.dagger.workingDirectory;
        User = "root";
        Group = "root";
        
        # Use Dagger to manage the container lifecycle
        ExecStart = pkgs.writeShellScript "start-dagger-homebridge" ''
          #!/bin/bash
          set -euo pipefail
          
          echo "Starting Dagger-managed Homebridge service..."
          
          # Navigate to Dagger project
          cd ${config.services.dagger.projectDirectory}
          
          # Deploy Homebridge via Dagger
          ${pkgs.dagger}/bin/dagger call services.automation.homebridge.deploy \
            --image="$DAGGER_HOMEBRIDGE_IMAGE" \
            --data-dir="$DAGGER_HOMEBRIDGE_DATA_DIR" \
            --port="$DAGGER_HOMEBRIDGE_PORT" \
            --network="$DAGGER_HOMEBRIDGE_NETWORK" \
            --enable-autoupdate="$DAGGER_HOMEBRIDGE_ENABLE_AUTOUPDATE" \
            --enable-backup="$DAGGER_HOMEBRIDGE_ENABLE_BACKUP"
          
          echo "Dagger-managed Homebridge started successfully"
        '';
        
        ExecStop = pkgs.writeShellScript "stop-dagger-homebridge" ''
          #!/bin/bash
          set -euo pipefail
          
          echo "Stopping Dagger-managed Homebridge service..."
          
          cd ${config.services.dagger.projectDirectory}
          
          # Stop Homebridge via Dagger
          ${pkgs.dagger}/bin/dagger call services.automation.homebridge.stop
          
          echo "Dagger-managed Homebridge stopped"
        '';
        
        ExecReload = pkgs.writeShellScript "reload-dagger-homebridge" ''
          #!/bin/bash
          set -euo pipefail
          
          echo "Reloading Dagger-managed Homebridge service..."
          
          cd ${config.services.dagger.projectDirectory}
          
          # Restart Homebridge via Dagger
          ${pkgs.dagger}/bin/dagger call services.automation.homebridge.restart
          
          echo "Dagger-managed Homebridge reloaded"
        '';
        
        # Resource limits (aligned with existing resource-limits.nix)
        MemoryMax = "1G";
        CPUQuota = "150%";
        TasksMax = "500";
        
        # Security settings
        NoNewPrivileges = true;
        ProtectSystem = "strict";
        ProtectHome = true;
        ReadWritePaths = [
          cfg.dataDir
          config.services.dagger.workingDirectory
        ];
        PrivateTmp = true;
      };
      
      # Health check integration  
      onFailure = mkIf cfg.enableMonitoring [ "dagger-homebridge-health-check.service" ];
    };
    
    # Health check service
    systemd.services."dagger-homebridge-health-check" = mkIf cfg.enableMonitoring {
      description = "Homebridge health check";
      serviceConfig = {
        Type = "oneshot";
        User = "root";
        Group = "root";
        ExecStart = pkgs.writeShellScript "homebridge-health-check" ''
          #!/bin/bash
          set -euo pipefail
          
          echo "Performing Homebridge health check..."
          
          # Check if service is responding
          if curl -f -s --connect-timeout 10 "http://127.0.0.1:${toString cfg.port}" > /dev/null; then
            echo "✓ Homebridge is responding"
          else
            echo "✗ Homebridge is not responding"
            exit 1
          fi
          
          # Check if container is running
          if podman ps --filter "name=homebridge" --format "{{.Names}}" | grep -q homebridge; then
            echo "✓ Homebridge container is running"
          else
            echo "✗ Homebridge container is not running"
            exit 1
          fi
          
          # Check HomeKit connectivity (if possible)
          # This would require more sophisticated HomeKit protocol checking
          
          echo "Homebridge health check completed successfully"
        '';
      };
    };
    
    # Backup service integration (enhanced version of existing backup)
    systemd.services."dagger-backup-homebridge" = mkIf cfg.enableBackup {
      description = "Backup Homebridge via Dagger pipeline";
      wantedBy = [ "default.target" ];
      after = [ "dagger-automation-homebridge.service" ];
      requisite = [ "sops-nix.service" ];
      
      serviceConfig = {
        Type = "oneshot";
        User = "root";
        Group = "root";
        WorkingDirectory = config.services.dagger.projectDirectory;
        
        ExecStart = pkgs.writeShellScript "dagger-backup-homebridge" ''
          #!/bin/bash
          set -euo pipefail
          
          echo "Starting Dagger-managed Homebridge backup..."
          
          # Run backup via Dagger pipeline
          ${pkgs.dagger}/bin/dagger call services.automation.homebridge.backup.backup \
            --service="homebridge" \
            --paths="${cfg.dataDir}"
          
          echo "Dagger-managed Homebridge backup completed"
        '';
        
        # Environment for secrets access
        EnvironmentFile = mkIf (config.sops.secrets ? "kopia-repository-token") 
          config.sops.secrets."kopia-repository-token".path;
      };
    };
    
    # Backup timer (same schedule as existing)
    systemd.timers."dagger-backup-homebridge" = mkIf cfg.enableBackup {
      description = "Backup Homebridge via Dagger";
      wantedBy = [ "timers.target" ];
      timerConfig = {
        OnCalendar = "*-*-* 4:00:00";
        RandomizedDelaySec = "1h";
        Persistent = true;
      };
    };
    
    # Auto-update timer (enhanced version)
    systemd.timers."dagger-autoupdate-homebridge" = mkIf cfg.enableAutoUpdate {
      description = "Auto-update Homebridge container via Dagger";
      wantedBy = [ "timers.target" ];
      timerConfig = {
        OnCalendar = "*-*-* 7:00:00";
        RandomizedDelaySec = "1h";
        Persistent = true;
      };
    };
    
    systemd.services."dagger-autoupdate-homebridge" = mkIf cfg.enableAutoUpdate {
      description = "Auto-update Homebridge container";
      serviceConfig = {
        Type = "oneshot";
        User = "root";
        Group = "root";
        WorkingDirectory = config.services.dagger.projectDirectory;
        
        ExecStart = pkgs.writeShellScript "dagger-autoupdate-homebridge" ''
          #!/bin/bash
          set -euo pipefail
          
          echo "Checking for Homebridge container updates..."
          
          # Update via Dagger pipeline
          ${pkgs.dagger}/bin/dagger call services.automation.homebridge.update \
            --check-only=false
          
          echo "Homebridge container update check completed"
        '';
      };
    };
    
    # Persistence configuration (same as existing)
    environment.persistence."/nix/persist" = mkIf config.environment.persistence."/nix/persist".enable {
      directories = [
        cfg.dataDir
      ];
    };
    
    # Assertions to ensure proper configuration
    assertions = [
      {
        assertion = cfg.port != 0;
        message = "Homebridge port must be specified";
      }
      {
        assertion = cfg.dataDir != "";
        message = "Homebridge data directory must be specified";
      }
      {
        assertion = config.services.dagger.enable;
        message = "Dagger service must be enabled for Dagger-managed Homebridge";
      }
      {
        assertion = !config.virtualisation.oci-containers.containers ? "homebridge";
        message = "Disable existing OCI Homebridge container before enabling Dagger-managed version";
      }
    ];
    
    # Migration warning
    warnings = optional (config.virtualisation.oci-containers.containers ? "homebridge") 
      "Existing OCI Homebridge container detected. Disable it before enabling Dagger-managed version to avoid conflicts.";
  };
}