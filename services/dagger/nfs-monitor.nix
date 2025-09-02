# NFS Health Monitoring for Dagger Services
# Provides continuous monitoring and automatic recovery for NFS mount issues
# Integrates with Dagger-managed services to ensure storage dependencies

{ config, lib, pkgs, ... }:

with lib;

let
  cfg = config.services.dagger.nfsMonitor;
  
  # NFS monitoring and recovery script
  nfsMonitorScript = pkgs.writeShellScript "dagger-nfs-monitor" ''
    #!/bin/bash
    set -euo pipefail
    
    NFS_MOUNT="/mnt/docker-data"
    NFS_HOST="10.4.0.50"
    LOCK_FILE="/run/dagger-nfs-monitor.lock"
    LOG_FILE="/var/log/dagger-nfs-monitor.log"
    
    # Logging function
    log() {
      echo "$(date '+%Y-%m-%d %H:%M:%S') $*" | tee -a "$LOG_FILE"
    }
    
    # Check if already running
    if [ -f "$LOCK_FILE" ]; then
      pid=$(cat "$LOCK_FILE")
      if kill -0 "$pid" 2>/dev/null; then
        echo "NFS monitor already running (PID: $pid)"
        exit 0
      else
        rm -f "$LOCK_FILE"
      fi
    fi
    
    # Create lock file
    echo $$ > "$LOCK_FILE"
    trap 'rm -f "$LOCK_FILE"' EXIT
    
    log "Starting NFS monitoring for Dagger services..."
    
    # Skip if NFS not configured
    if [ ! -d "$NFS_MOUNT" ]; then
      log "NFS mount directory $NFS_MOUNT not found, exiting"
      exit 0
    fi
    
    # Function to check NFS health
    check_nfs_health() {
      local issues=0
      
      # Check if mounted
      if ! mountpoint -q "$NFS_MOUNT"; then
        log "ERROR: NFS mount $NFS_MOUNT is not mounted"
        issues=$((issues + 1))
      fi
      
      # Check server connectivity
      if ! timeout 5 ping -c 1 "$NFS_HOST" >/dev/null 2>&1; then
        log "ERROR: NFS server $NFS_HOST is not reachable"
        issues=$((issues + 1))
      fi
      
      # Check write access
      if mountpoint -q "$NFS_MOUNT"; then
        if ! timeout 10 touch "$NFS_MOUNT/.dagger-health-check" 2>/dev/null; then
          log "ERROR: Cannot write to NFS mount $NFS_MOUNT"
          issues=$((issues + 1))
        else
          rm -f "$NFS_MOUNT/.dagger-health-check"
        fi
      fi
      
      return $issues
    }
    
    # Function to attempt NFS recovery
    recover_nfs() {
      log "Attempting NFS recovery..."
      
      # Unmount if stale
      if mountpoint -q "$NFS_MOUNT"; then
        log "Unmounting stale NFS mount..."
        umount -f "$NFS_MOUNT" || umount -l "$NFS_MOUNT" || true
        sleep 2
      fi
      
      # Wait for network connectivity
      for i in {1..5}; do
        if timeout 5 ping -c 1 "$NFS_HOST" >/dev/null 2>&1; then
          log "Network connectivity to NFS server restored"
          break
        fi
        log "Waiting for network connectivity (attempt $i/5)..."
        sleep 10
      done
      
      # Attempt to mount
      if mount "$NFS_MOUNT" 2>/dev/null; then
        log "NFS mount recovered successfully"
        
        # Validate access
        if timeout 10 touch "$NFS_MOUNT/.dagger-recovery-test" 2>/dev/null; then
          rm -f "$NFS_MOUNT/.dagger-recovery-test"
          log "NFS mount is accessible after recovery"
          return 0
        else
          log "NFS mount recovered but not accessible"
          return 1
        fi
      else
        log "Failed to recover NFS mount"
        return 1
      fi
    }
    
    # Function to restart affected Dagger services
    restart_affected_services() {
      log "Restarting Dagger services that may be affected by NFS issues..."
      
      # List of services that depend on NFS
      local nfs_dependent_services=(
        "dagger-coordinator.service"
        "dagger-automation-homebridge.service"
        "dagger-nixarr-orchestrator.service"
      )
      
      for service in "''${nfs_dependent_services[@]}"; do
        if systemctl is-active "$service" >/dev/null 2>&1; then
          log "Restarting $service due to NFS recovery..."
          systemctl restart "$service" || log "Failed to restart $service"
        fi
      done
    }
    
    # Main monitoring loop
    failure_count=0
    recovery_attempts=0
    max_failures=${toString cfg.maxFailures}
    max_recovery_attempts=${toString cfg.maxRecoveryAttempts}
    
    while true; do
      if check_nfs_health; then
        log "NFS health check passed"
        failure_count=0
        recovery_attempts=0
      else
        failure_count=$((failure_count + 1))
        log "NFS health check failed (failure $failure_count/$max_failures)"
        
        if [ $failure_count -ge $max_failures ] && [ $recovery_attempts -lt $max_recovery_attempts ]; then
          recovery_attempts=$((recovery_attempts + 1))
          log "Attempting NFS recovery (attempt $recovery_attempts/$max_recovery_attempts)"
          
          if recover_nfs; then
            failure_count=0
            restart_affected_services
          else
            log "NFS recovery failed"
          fi
        fi
        
        if [ $recovery_attempts -ge $max_recovery_attempts ]; then
          log "Maximum recovery attempts reached, monitoring continues but no more recovery will be attempted"
        fi
      fi
      
      sleep ${toString cfg.checkInterval}
    done
  '';
  
  # Script to validate NFS configuration before starting services
  nfsValidateScript = pkgs.writeShellScript "dagger-nfs-validate" ''
    #!/bin/bash
    set -euo pipefail
    
    NFS_MOUNT="/mnt/docker-data"
    NFS_HOST="10.4.0.50"
    
    echo "Validating NFS configuration for Dagger services..."
    
    if [ ! -d "$NFS_MOUNT" ]; then
      echo "NFS mount directory not configured, skipping validation"
      exit 0
    fi
    
    # Check if NFS is in /etc/fstab
    if ! grep -q "$NFS_MOUNT" /etc/fstab 2>/dev/null; then
      echo "WARNING: NFS mount $NFS_MOUNT not found in /etc/fstab"
    fi
    
    # Check if already mounted
    if mountpoint -q "$NFS_MOUNT"; then
      echo "✓ NFS mount is active"
      
      # Test access
      if timeout 10 touch "$NFS_MOUNT/.dagger-startup-test" 2>/dev/null; then
        rm -f "$NFS_MOUNT/.dagger-startup-test"
        echo "✓ NFS mount is accessible"
      else
        echo "✗ NFS mount is not accessible"
        exit 1
      fi
    else
      echo "NFS mount not active, attempting to mount..."
      if mount "$NFS_MOUNT"; then
        echo "✓ NFS mount successful"
      else
        echo "✗ Failed to mount NFS"
        exit 1
      fi
    fi
    
    echo "NFS validation completed successfully"
  '';

in {
  options.services.dagger.nfsMonitor = {
    enable = mkEnableOption "NFS health monitoring for Dagger services";
    
    checkInterval = mkOption {
      type = types.int;
      default = 30;
      description = "Health check interval in seconds";
    };
    
    maxFailures = mkOption {
      type = types.int;
      default = 3;
      description = "Maximum consecutive failures before attempting recovery";
    };
    
    maxRecoveryAttempts = mkOption {
      type = types.int;
      default = 3;
      description = "Maximum NFS recovery attempts";
    };
    
    enableServiceRestart = mkOption {
      type = types.bool;
      default = true;
      description = "Restart affected services after NFS recovery";
    };
    
    logLevel = mkOption {
      type = types.enum [ "debug" "info" "warn" "error" ];
      default = "info";
      description = "Logging level for NFS monitor";
    };
  };
  
  config = mkIf cfg.enable {
    
    # NFS validation service - runs before Dagger services start
    systemd.services."dagger-nfs-validate" = {
      description = "Validate NFS storage for Dagger services";
      wantedBy = [ "multi-user.target" ];
      before = [ "dagger-coordinator.service" ];
      after = [ "network.target" ];
      
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
        ExecStart = toString nfsValidateScript;
        User = "root";
        Group = "root";
        TimeoutStartSec = "60s";
      };
      
      # Only run if NFS mount directory exists
      unitConfig.ConditionPathExists = "/mnt/docker-data";
    };
    
    # NFS health monitoring service
    systemd.services."dagger-nfs-monitor" = {
      description = "NFS health monitoring for Dagger services";
      wantedBy = [ "multi-user.target" ];
      after = [ "network.target" "dagger-nfs-validate.service" ];
      wants = [ "dagger-nfs-validate.service" ];
      
      serviceConfig = {
        Type = "simple";
        ExecStart = toString nfsMonitorScript;
        Restart = "always";
        RestartSec = "10s";
        User = "root";
        Group = "root";
        
        # Logging configuration
        StandardOutput = "journal";
        StandardError = "journal";
        
        # Security settings
        NoNewPrivileges = true;
        ProtectSystem = "strict";
        ProtectHome = true;
        ReadWritePaths = [
          "/mnt/docker-data"
          "/var/log"
          "/run"
        ];
        PrivateTmp = true;
        
        # Resource limits
        MemoryMax = "128M";
        CPUQuota = "10%";
        TasksMax = "10";
      };
      
      # Only run if NFS mount directory exists
      unitConfig.ConditionPathExists = "/mnt/docker-data";
    };
    
    # Log rotation for NFS monitor
    services.logrotate.extraConfig = ''
      /var/log/dagger-nfs-monitor.log {
        daily
        missingok
        rotate 7
        compress
        delaycompress
        notifempty
        copytruncate
      }
    '';
    
    # Add NFS monitoring dependencies to key Dagger services
    systemd.services = {
      "dagger-coordinator".after = mkIf (config.systemd.services ? "dagger-coordinator")
        ([ "dagger-nfs-validate.service" ]);
      "dagger-coordinator".wants = mkIf (config.systemd.services ? "dagger-coordinator")
        ([ "dagger-nfs-validate.service" ]);
    };
    
    # Environment for debugging
    environment.systemPackages = with pkgs; [
      nfs-utils  # For debugging NFS issues
    ];
    
    # Assertions to ensure proper configuration
    assertions = [
      {
        assertion = cfg.checkInterval > 0;
        message = "NFS monitor check interval must be greater than 0";
      }
      {
        assertion = cfg.maxFailures > 0;
        message = "Maximum failures must be greater than 0";
      }
      {
        assertion = cfg.maxRecoveryAttempts > 0;
        message = "Maximum recovery attempts must be greater than 0";
      }
    ];
  };
}