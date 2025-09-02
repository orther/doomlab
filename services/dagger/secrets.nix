# SOPS Secrets Bridge for Dagger Integration  
# Provides secure secret injection from SOPS-nix into Dagger containers
# Maintains existing security patterns while enabling Dagger workflows

{ config, lib, pkgs, ... }:

with lib;

let
  cfg = config.services.dagger.secrets;
  
  # Secret injection script that reads from SOPS and provides to Dagger
  secretInjector = pkgs.writeShellScript "dagger-secret-injector" ''
    #!/bin/bash
    set -euo pipefail
    
    SECRET_NAME="$1"
    SECRET_PATH="$2"
    OUTPUT_PATH="$3"
    
    if [ ! -f "$SECRET_PATH" ]; then
      echo "Error: Secret file $SECRET_PATH not found"
      exit 1
    fi
    
    # Create output directory if it doesn't exist
    mkdir -p "$(dirname "$OUTPUT_PATH")"
    
    # Copy secret with proper permissions
    cp "$SECRET_PATH" "$OUTPUT_PATH"
    chmod 600 "$OUTPUT_PATH"
    
    echo "Secret $SECRET_NAME injected to $OUTPUT_PATH"
  '';
  
  # Dagger secrets configuration generator
  secretsConfig = pkgs.writeText "dagger-secrets.json" (builtins.toJSON {
    secrets = {
      # Map SOPS secrets to Dagger-accessible paths
      cloudflare_email = "${cfg.runtime.secretsDir}/cloudflare-email";
      cloudflare_api_key = "${cfg.runtime.secretsDir}/cloudflare-api-key";
      kopia_repository_token = "${cfg.runtime.secretsDir}/kopia-repository-token";
      transmission_rpc_password = "${cfg.runtime.secretsDir}/transmission-rpc-password";
    };
  });
  
  # Secret mounting service for Dagger containers
  secretMounter = pkgs.writeShellScript "dagger-secret-mounter" ''
    #!/bin/bash
    set -euo pipefail
    
    CONTAINER_NAME="$1"
    
    echo "Mounting secrets for container: $CONTAINER_NAME"
    
    # Create secrets directory structure
    mkdir -p "${cfg.runtime.secretsDir}"
    chmod 700 "${cfg.runtime.secretsDir}"
    
    # Inject secrets based on availability
    ${optionalString (config.sops.secrets ? "cloudflare-api-email") ''
      ${secretInjector} "cloudflare-email" \
        "${config.sops.secrets."cloudflare-api-email".path}" \
        "${cfg.runtime.secretsDir}/cloudflare-email"
    ''}
    
    ${optionalString (config.sops.secrets ? "cloudflare-api-key") ''
      ${secretInjector} "cloudflare-api-key" \
        "${config.sops.secrets."cloudflare-api-key".path}" \
        "${cfg.runtime.secretsDir}/cloudflare-api-key"
    ''}
    
    ${optionalString (config.sops.secrets ? "kopia-repository-token") ''
      ${secretInjector} "kopia-repository-token" \
        "${config.sops.secrets."kopia-repository-token".path}" \
        "${cfg.runtime.secretsDir}/kopia-repository-token"
    ''}
    
    # Handle transmission password if available (currently hardcoded)
    # TODO: Move transmission password to SOPS when migrated
    echo "{7d827abfb09b77e45fe9e72d97956ab8fb53acafoPNV1MpJ" > "${cfg.runtime.secretsDir}/transmission-rpc-password"
    chmod 600 "${cfg.runtime.secretsDir}/transmission-rpc-password"
    
    echo "Secret mounting completed for $CONTAINER_NAME"
  '';

in {
  options.services.dagger.secrets = {
    enable = mkEnableOption "Dagger secrets bridge";
    
    runtime = {
      secretsDir = mkOption {
        type = types.path;
        default = "/run/dagger-secrets";
        description = "Runtime directory for Dagger-accessible secrets";
      };
      
      mountMode = mkOption {
        type = types.enum [ "bind" "tmpfs" ];
        default = "tmpfs";
        description = "How to mount secrets in containers (bind mounts or tmpfs)";
      };
    };
    
    backup = {
      excludeFromBackup = mkOption {
        type = types.bool;
        default = true;
        description = "Exclude secrets directory from backups";
      };
    };
    
    rotation = {
      enable = mkOption {
        type = types.bool;
        default = true;
        description = "Enable automatic secret rotation detection and container restart";
      };
      
      checkInterval = mkOption {
        type = types.str;
        default = "1h";
        description = "Interval to check for secret rotation";
      };
    };
  };
  
  config = mkIf cfg.enable {
    
    # Ensure runtime secrets directory exists
    systemd.tmpfiles.rules = [
      "d ${cfg.runtime.secretsDir} 0700 root root"
    ];
    
    # Secret injection service that runs before Dagger services
    systemd.services."dagger-secret-injection" = {
      description = "Inject SOPS secrets for Dagger services";
      before = [ "dagger-coordinator.service" ];
      wantedBy = [ "multi-user.target" ];
      requisite = [ "sops-nix.service" ];
      
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
        ExecStart = "${secretMounter} dagger-coordinator";
        ExecReload = "${secretMounter} dagger-coordinator";
        User = "root";
        Group = "root";
        
        # Security hardening
        NoNewPrivileges = true;
        ProtectSystem = "strict";
        ProtectHome = true;
        ReadWritePaths = [ cfg.runtime.secretsDir ];
        PrivateTmp = true;
        ProtectKernelTunables = true;
        ProtectKernelModules = true;
        ProtectControlGroups = true;
      };
      
      # Restart when SOPS secrets change
      onFailure = [ "dagger-secret-rotation.service" ];
    };
    
    # Secret rotation monitoring service
    systemd.services."dagger-secret-rotation" = mkIf cfg.rotation.enable {
      description = "Monitor SOPS secret rotation and restart Dagger services";
      serviceConfig = {
        Type = "oneshot";
        ExecStart = pkgs.writeShellScript "dagger-secret-rotation-handler" ''
          #!/bin/bash
          set -euo pipefail
          
          echo "Handling secret rotation for Dagger services..."
          
          # Re-inject updated secrets
          systemctl reload dagger-secret-injection.service
          
          # Restart affected Dagger services
          affected_services=($(systemctl list-units --state=active --plain dagger-*.service | awk '{print $1}'))
          
          for service in "''${affected_services[@]}"; do
            if [[ "$service" != "dagger-secret-injection.service" ]] && [[ "$service" != "dagger-coordinator.service" ]]; then
              echo "Restarting $service due to secret rotation..."
              systemctl restart "$service"
            fi
          done
          
          echo "Secret rotation handling completed"
        '';
        User = "root";
        Group = "root";
      };
    };
    
    # Timer for periodic secret rotation checking
    systemd.timers."dagger-secret-rotation-check" = mkIf cfg.rotation.enable {
      description = "Check for SOPS secret rotation";
      wantedBy = [ "timers.target" ];
      timerConfig = {
        OnUnitActiveSec = cfg.rotation.checkInterval;
        OnBootSec = cfg.rotation.checkInterval;
        Persistent = true;
      };
    };
    
    systemd.services."dagger-secret-rotation-check" = mkIf cfg.rotation.enable {
      description = "Check for SOPS secret rotation";
      serviceConfig = {
        Type = "oneshot";
        ExecStart = pkgs.writeShellScript "check-secret-rotation" ''
          #!/bin/bash
          set -euo pipefail
          
          # Check if any SOPS secrets have been updated since last injection
          secrets_dir="${cfg.runtime.secretsDir}"
          rotation_needed=false
          
          ${optionalString (config.sops.secrets ? "cloudflare-api-email") ''
            sops_file="${config.sops.secrets."cloudflare-api-email".path}"
            dagger_file="$secrets_dir/cloudflare-email"
            
            if [[ "$sops_file" -nt "$dagger_file" ]]; then
              echo "Cloudflare email secret has been rotated"
              rotation_needed=true
            fi
          ''}
          
          ${optionalString (config.sops.secrets ? "cloudflare-api-key") ''
            sops_file="${config.sops.secrets."cloudflare-api-key".path}"
            dagger_file="$secrets_dir/cloudflare-api-key"
            
            if [[ "$sops_file" -nt "$dagger_file" ]]; then
              echo "Cloudflare API key secret has been rotated"
              rotation_needed=true
            fi
          ''}
          
          ${optionalString (config.sops.secrets ? "kopia-repository-token") ''
            sops_file="${config.sops.secrets."kopia-repository-token".path}"
            dagger_file="$secrets_dir/kopia-repository-token"
            
            if [[ "$sops_file" -nt "$dagger_file" ]]; then
              echo "Kopia repository token has been rotated"
              rotation_needed=true
            fi
          ''}
          
          if [ "$rotation_needed" = true ]; then
            echo "Secret rotation detected, triggering rotation handler..."
            systemctl start dagger-secret-rotation.service
          else
            echo "No secret rotation detected"
          fi
        '';
        User = "root";
        Group = "root";
      };
    };
    
    # Environment variables for Dagger services to access secrets
    environment.variables = {
      DAGGER_SECRETS_DIR = cfg.runtime.secretsDir;
      DAGGER_SECRETS_CONFIG = toString secretsConfig;
    };
    
    # Exclude secrets from persistence if requested
    environment.persistence."/nix/persist" = mkIf (!cfg.backup.excludeFromBackup) {
      directories = [
        {
          directory = cfg.runtime.secretsDir;
          mode = "0700";
        }
      ];
    };
    
    # Security assertions
    assertions = [
      {
        assertion = cfg.runtime.secretsDir != "/";
        message = "Dagger secrets directory cannot be root filesystem";
      }
      {
        assertion = hasPrefix "/run" cfg.runtime.secretsDir || hasPrefix "/tmp" cfg.runtime.secretsDir;
        message = "Dagger secrets directory should be in /run or /tmp for security";
      }
      {
        assertion = config.services.dagger.enable;
        message = "Dagger service must be enabled to use secrets bridge";
      }
    ];
    
    # Warnings for missing secrets
    warnings = 
      (optional (!config.sops.secrets ? "cloudflare-api-email") 
        "Cloudflare email secret not configured - SSL certificate management may be affected") ++
      (optional (!config.sops.secrets ? "cloudflare-api-key")
        "Cloudflare API key secret not configured - SSL certificate management may be affected") ++
      (optional (!config.sops.secrets ? "kopia-repository-token")
        "Kopia repository token not configured - backup functionality may be limited");
  };
}