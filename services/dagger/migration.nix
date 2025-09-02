# Nixarr Migration Compatibility Layer
# Provides side-by-side operation and migration utilities between
# existing nixarr systemd services and Dagger-enhanced services

{
  config,
  lib,
  pkgs,
  ...
}:

with lib;

let
  cfg = config.services.dagger.nixarr;
  legacyCfg = config.nixarr or {};
  
  # Migration state tracking
  migrationStateFile = "/var/lib/dagger/nixarr-migration-state.json";
  
  # Service mapping between legacy and dagger services
  serviceMapping = {
    sonarr = {
      legacy = "sonarr";
      dagger = "dagger-sonarr";
      port = cfg.sonarr.port or 8989;
      dataPath = "${cfg.storage.stateRoot}/nixarr/sonarr";
    };
    radarr = {
      legacy = "radarr";
      dagger = "dagger-radarr";
      port = cfg.radarr.port or 7878;
      dataPath = "${cfg.storage.stateRoot}/nixarr/radarr";
    };
    prowlarr = {
      legacy = "prowlarr";
      dagger = "dagger-prowlarr";
      port = cfg.prowlarr.port or 9696;
      dataPath = "${cfg.storage.stateRoot}/nixarr/prowlarr";
    };
    bazarr = {
      legacy = "bazarr";
      dagger = "dagger-bazarr";
      port = cfg.bazarr.port or 6767;
      dataPath = "${cfg.storage.stateRoot}/nixarr/bazarr";
    };
    transmission = {
      legacy = "transmission";
      dagger = "dagger-transmission";
      port = cfg.transmission.port or 9091;
      dataPath = "${cfg.storage.stateRoot}/nixarr/transmission";
    };
    jellyfin = {
      legacy = "jellyfin";
      dagger = "dagger-jellyfin";
      port = cfg.jellyfin.port or 8096;
      dataPath = "${cfg.storage.stateRoot}/nixarr/jellyfin";
    };
  };

  # Migration script generator
  mkMigrationScript = serviceName: serviceConfig: pkgs.writeShellScript "migrate-${serviceName}" ''
    set -euo pipefail
    
    echo "Starting migration for ${serviceName}..."
    
    # Check if legacy service exists and is running
    if systemctl is-active --quiet ${serviceConfig.legacy}.service 2>/dev/null; then
      echo "Legacy ${serviceName} service is running, stopping for migration..."
      systemctl stop ${serviceConfig.legacy}.service
      
      # Wait for graceful shutdown
      sleep 10
      
      # Backup current configuration
      if [ -d "${serviceConfig.dataPath}" ]; then
        backup_path="/var/lib/dagger/backups/${serviceName}-pre-migration-$(date +%Y%m%d-%H%M%S)"
        echo "Backing up ${serviceName} data to $backup_path..."
        mkdir -p "$(dirname "$backup_path")"
        cp -r "${serviceConfig.dataPath}" "$backup_path"
      fi
    fi
    
    # Disable legacy service to prevent conflicts
    systemctl disable ${serviceConfig.legacy}.service || true
    
    # Ensure data directory has correct permissions for Dagger
    if [ -d "${serviceConfig.dataPath}" ]; then
      echo "Setting permissions for ${serviceConfig.dataPath}..."
      chown -R dagger:dagger "${serviceConfig.dataPath}"
      chmod -R u+rw,g+rw "${serviceConfig.dataPath}"
    fi
    
    # Start Dagger service
    echo "Starting Dagger-managed ${serviceName} service..."
    systemctl enable ${serviceConfig.dagger}.service
    systemctl start ${serviceConfig.dagger}.service
    
    # Wait for service to be ready
    echo "Waiting for ${serviceName} to be ready on port ${toString serviceConfig.port}..."
    for i in {1..30}; do
      if curl -f -s --connect-timeout 5 "http://127.0.0.1:${toString serviceConfig.port}/ping" > /dev/null 2>&1; then
        echo "✓ ${serviceName} migration completed successfully"
        
        # Update migration state
        update_migration_state "${serviceName}" "completed"
        exit 0
      fi
      echo "  Waiting... ($i/30)"
      sleep 10
    done
    
    echo "✗ ${serviceName} migration failed - service not responding"
    update_migration_state "${serviceName}" "failed"
    exit 1
  '';

  # Rollback script generator
  mkRollbackScript = serviceName: serviceConfig: pkgs.writeShellScript "rollback-${serviceName}" ''
    set -euo pipefail
    
    echo "Starting rollback for ${serviceName}..."
    
    # Stop Dagger service
    if systemctl is-active --quiet ${serviceConfig.dagger}.service 2>/dev/null; then
      echo "Stopping Dagger ${serviceName} service..."
      systemctl stop ${serviceConfig.dagger}.service
      systemctl disable ${serviceConfig.dagger}.service
    fi
    
    # Find most recent backup
    latest_backup=$(find /var/lib/dagger/backups -name "${serviceName}-pre-migration-*" -type d | sort -r | head -n1 || echo "")
    
    if [ -n "$latest_backup" ] && [ -d "$latest_backup" ]; then
      echo "Restoring ${serviceName} data from $latest_backup..."
      
      # Remove current data if it exists
      if [ -d "${serviceConfig.dataPath}" ]; then
        rm -rf "${serviceConfig.dataPath}"
      fi
      
      # Restore from backup
      cp -r "$latest_backup" "${serviceConfig.dataPath}"
      
      # Fix permissions for legacy service
      chown -R nixarr:nixarr "${serviceConfig.dataPath}" || true
    else
      echo "Warning: No backup found for ${serviceName}"
    fi
    
    # Re-enable legacy service
    echo "Re-enabling legacy ${serviceName} service..."
    systemctl enable ${serviceConfig.legacy}.service
    systemctl start ${serviceConfig.legacy}.service
    
    # Wait for service to be ready
    echo "Waiting for legacy ${serviceName} to be ready..."
    for i in {1..30}; do
      if curl -f -s --connect-timeout 5 "http://127.0.0.1:${toString serviceConfig.port}/ping" > /dev/null 2>&1; then
        echo "✓ ${serviceName} rollback completed successfully"
        update_migration_state "${serviceName}" "rolled_back"
        exit 0
      fi
      echo "  Waiting... ($i/30)"
      sleep 10
    done
    
    echo "✗ ${serviceName} rollback failed - legacy service not responding"
    update_migration_state "${serviceName}" "rollback_failed"
    exit 1
  '';

  # Migration status checker
  migrationStatusScript = pkgs.writeShellScript "nixarr-migration-status" ''
    set -euo pipefail
    
    echo "Nixarr Migration Status Report"
    echo "=============================="
    echo
    
    if [ -f "${migrationStateFile}" ]; then
      echo "Migration state file found:"
      cat "${migrationStateFile}" | ${pkgs.jq}/bin/jq .
    else
      echo "No migration state file found"
    fi
    
    echo
    echo "Service Status:"
    echo "-------------"
    
    check_service_status() {
      local service_name=$1
      local legacy_service=$2
      local dagger_service=$3
      local port=$4
      
      echo -n "$service_name: "
      
      legacy_active=$(systemctl is-active $legacy_service.service 2>/dev/null || echo "inactive")
      dagger_active=$(systemctl is-active $dagger_service.service 2>/dev/null || echo "inactive")
      
      if [ "$legacy_active" = "active" ] && [ "$dagger_active" = "active" ]; then
        echo "⚠️  CONFLICT - Both legacy and Dagger services running!"
      elif [ "$dagger_active" = "active" ]; then
        if curl -f -s --connect-timeout 3 "http://127.0.0.1:$port/ping" > /dev/null 2>&1; then
          echo "✅ Dagger (healthy)"
        else
          echo "🔴 Dagger (unhealthy)"
        fi
      elif [ "$legacy_active" = "active" ]; then
        if curl -f -s --connect-timeout 3 "http://127.0.0.1:$port/ping" > /dev/null 2>&1; then
          echo "🟡 Legacy (healthy)"
        else
          echo "🔴 Legacy (unhealthy)"
        fi
      else
        echo "🔴 Not running"
      fi
    }
    
    ${concatStringsSep "\n    " (mapAttrsToList (name: config: 
      "check_service_status '${name}' '${config.legacy}' '${config.dagger}' '${toString config.port}'"
    ) serviceMapping)}
    
    echo
    echo "Port Usage:"
    echo "----------"
    ${pkgs.netstat}/bin/ss -tlnp | grep -E ':(8989|7878|9696|6767|9091|8096)\s' || echo "No nixarr ports in use"
  '';

in

{
  options.services.dagger.nixarr.migration = {
    # Already defined in main module, extending here
    
    # Additional migration-specific options
    
    enableStatusMonitoring = mkOption {
      type = types.bool;
      default = true;
      description = "Enable migration status monitoring and reporting";
    };
    
    conflictDetection = mkOption {
      type = types.bool;
      default = true;
      description = "Enable detection and alerting for service conflicts";
    };
    
    autoRollbackOnFailure = mkOption {
      type = types.bool;
      default = false;
      description = "Automatically rollback to legacy services if Dagger migration fails";
    };
    
    preserveLegacyServices = mkOption {
      type = types.bool;
      default = true;
      description = "Keep legacy service definitions available for rollback";
    };
  };

  config = mkIf (cfg.enable && cfg.migration.enableCompatibilityMode) {
    
    # Migration utility scripts
    environment.systemPackages = [
      # Main migration control script
      (pkgs.writeShellScriptBin "nixarr-migrate" ''
        set -euo pipefail
        
        function update_migration_state() {
          local service=$1
          local status=$2
          local timestamp=$(date -Iseconds)
          
          mkdir -p "$(dirname "${migrationStateFile}")"
          
          if [ -f "${migrationStateFile}" ]; then
            ${pkgs.jq}/bin/jq --arg service "$service" --arg status "$status" --arg timestamp "$timestamp" \
              '.services[$service] = {status: $status, timestamp: $timestamp}' \
              "${migrationStateFile}" > "${migrationStateFile}.tmp"
          else
            echo '{}' | ${pkgs.jq}/bin/jq --arg service "$service" --arg status "$status" --arg timestamp "$timestamp" \
              '{services: {($service): {status: $status, timestamp: $timestamp}}}' > "${migrationStateFile}.tmp"
          fi
          
          mv "${migrationStateFile}.tmp" "${migrationStateFile}"
          chmod 644 "${migrationStateFile}"
        }
        
        case "$1" in
          "status")
            ${migrationStatusScript}
            ;;
          "migrate")
            if [ $# -lt 2 ]; then
              echo "Usage: nixarr-migrate migrate <service>"
              echo "Services: ${concatStringsSep ", " (attrNames serviceMapping)}"
              exit 1
            fi
            
            service="$2"
            case "$service" in
              ${concatStringsSep "\n              " (mapAttrsToList (name: config:
                ''${name}) ${mkMigrationScript name config} ;;''
              ) serviceMapping)}
              "all")
                echo "Migrating all enabled services..."
                ${concatStringsSep "\n                " (mapAttrsToList (name: config:
                  ''echo "Migrating ${name}..."; ${mkMigrationScript name config} || echo "❌ ${name} migration failed"''
                ) serviceMapping)}
                echo "All migrations completed"
                ;;
              *)
                echo "Unknown service: $service"
                exit 1
                ;;
            esac
            ;;
          "rollback")
            if [ $# -lt 2 ]; then
              echo "Usage: nixarr-migrate rollback <service>"
              exit 1
            fi
            
            service="$2"
            case "$service" in
              ${concatStringsSep "\n              " (mapAttrsToList (name: config:
                ''${name}) ${mkRollbackScript name config} ;;''
              ) serviceMapping)}
              "all")
                echo "Rolling back all services..."
                ${concatStringsSep "\n                " (mapAttrsToList (name: config:
                  ''echo "Rolling back ${name}..."; ${mkRollbackScript name config} || echo "❌ ${name} rollback failed"''
                ) serviceMapping)}
                echo "All rollbacks completed"
                ;;
              *)
                echo "Unknown service: $service"
                exit 1
                ;;
            esac
            ;;
          *)
            echo "Usage: nixarr-migrate {status|migrate|rollback} [service]"
            echo ""
            echo "Commands:"
            echo "  status         - Show migration status for all services"
            echo "  migrate <svc>  - Migrate service from legacy to Dagger"
            echo "  rollback <svc> - Rollback service from Dagger to legacy"
            echo ""
            echo "Services: ${concatStringsSep ", " (attrNames serviceMapping)}, all"
            exit 1
            ;;
        esac
      '')
      
      # Status monitoring script
      (pkgs.writeShellScriptBin "nixarr-migration-status" migrationStatusScript)
    ];

    # Migration state directory
    systemd.tmpfiles.rules = [
      "d /var/lib/dagger/backups 0755 dagger dagger -"
      "d /var/lib/dagger/migration 0755 dagger dagger -"
    ];

    # Conflict detection service
    systemd.services.nixarr-conflict-detector = mkIf cfg.migration.conflictDetection {
      description = "Nixarr service conflict detection";
      after = ["network.target"];
      
      serviceConfig = {
        Type = "simple";
        User = "dagger";
        Group = "dagger";
        Restart = "always";
        RestartSec = "60s";
      };

      script = ''
        while true; do
          conflicts_found=false
          
          # Check for port conflicts
          ${concatStringsSep "\n          " (mapAttrsToList (name: config: ''
            if systemctl is-active --quiet ${config.legacy}.service 2>/dev/null && \
               systemctl is-active --quiet ${config.dagger}.service 2>/dev/null; then
              echo "CONFLICT: Both ${config.legacy} and ${config.dagger} are running"
              conflicts_found=true
            fi
          '') serviceMapping)}
          
          if [ "$conflicts_found" = true ]; then
            echo "Service conflicts detected!"
            # Could integrate with alerting system here
            ${optionalString cfg.migration.autoRollbackOnFailure ''
            echo "Auto-rollback enabled, stopping Dagger services..."
            nixarr-migrate rollback all
            ''}
          fi
          
          sleep 60
        done
      '';
    };

    # Pre-migration backup service
    systemd.services.nixarr-pre-migration-backup = mkIf cfg.migration.backupBeforeMigration {
      description = "Pre-migration backup for nixarr services";
      
      serviceConfig = {
        Type = "oneshot";
        User = "root";
        Group = "root";
      };

      script = ''
        echo "Creating pre-migration backup..."
        
        backup_root="/var/lib/dagger/pre-migration-backup-$(date +%Y%m%d-%H%M%S)"
        mkdir -p "$backup_root"
        
        # Backup existing nixarr data
        if [ -d "${cfg.storage.stateRoot}/nixarr" ]; then
          echo "Backing up nixarr state data..."
          cp -r "${cfg.storage.stateRoot}/nixarr" "$backup_root/"
          
          # Create manifest
          echo "Pre-migration backup created on $(date)" > "$backup_root/BACKUP_MANIFEST"
          echo "Original path: ${cfg.storage.stateRoot}/nixarr" >> "$backup_root/BACKUP_MANIFEST"
          
          # List service states
          echo "=== Service States ===" >> "$backup_root/BACKUP_MANIFEST"
          ${concatStringsSep "\n          " (mapAttrsToList (name: config: ''
            echo "${name}: $(systemctl is-active ${config.legacy}.service 2>/dev/null || echo inactive)" >> "$backup_root/BACKUP_MANIFEST"
          '') serviceMapping)}
          
          echo "Pre-migration backup completed: $backup_root"
          chown -R dagger:dagger "$backup_root"
        else
          echo "No existing nixarr data found to backup"
        fi
      '';
    };

    # Import existing configuration if specified
    systemd.services.nixarr-import-config = mkIf (cfg.migration.dataImportPath != null) {
      description = "Import existing nixarr configuration";
      after = ["dagger-secrets.service"];
      wants = ["dagger-secrets.service"];
      
      serviceConfig = {
        Type = "oneshot";
        User = "dagger";
        Group = "dagger";
        RemainAfterExit = true;
      };

      script = ''
        echo "Importing nixarr configuration from ${cfg.migration.dataImportPath}..."
        
        if [ -d "${cfg.migration.dataImportPath}" ]; then
          # Create destination directory
          mkdir -p "${cfg.storage.stateRoot}/nixarr"
          
          # Copy configuration data
          cp -r "${cfg.migration.dataImportPath}"/* "${cfg.storage.stateRoot}/nixarr/" || true
          
          # Fix permissions
          chown -R dagger:dagger "${cfg.storage.stateRoot}/nixarr"
          chmod -R u+rw,g+rw "${cfg.storage.stateRoot}/nixarr"
          
          echo "Configuration import completed"
        else
          echo "Import path not found: ${cfg.migration.dataImportPath}"
          exit 1
        fi
      '';
    };
  };
}