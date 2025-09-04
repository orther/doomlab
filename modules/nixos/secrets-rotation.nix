{
  config,
  pkgs,
  lib,
  ...
}: 

with lib;

{
  options.services.secrets-rotation = {
    enable = mkEnableOption "Automated secrets rotation service";
    
    interval = mkOption {
      type = types.str;
      default = "monthly";
      description = "How often to rotate secrets (systemd timer format)";
    };
    
    rotateAgeKeys = mkOption {
      type = types.bool;
      default = true;
      description = "Whether to rotate SOPS age keys";
    };
    
    notificationEmail = mkOption {
      type = types.nullOr types.str;
      default = null;
      description = "Email address to notify on rotation events";
    };
  };

  config = mkIf config.services.secrets-rotation.enable {
    # Create the secrets rotation script

    systemd.services.secrets-rotation = {
      description = "Automated secrets rotation service";
      serviceConfig = {
        Type = "oneshot";
        User = "root";
        Group = "root";
        ExecStart = pkgs.writeScript "secrets-rotation" ''
          #!/bin/sh
          set -e
          
          LOG_FILE="/var/log/secrets-rotation.log"
          DATE=$(date -Iseconds)
          
          log() {
            echo "[$DATE] $1" | tee -a "$LOG_FILE"
          }
          
          log "Starting secrets rotation..."
          
          # Backup current keys
          BACKUP_DIR="/var/backup/secrets/$(date +%Y%m%d_%H%M%S)"
          mkdir -p "$BACKUP_DIR"
          
          ${optionalString config.services.secrets-rotation.rotateAgeKeys ''
            # Rotate age keys
            log "Rotating SOPS age keys..."
            
            # Backup current age key
            if [ -f "/nix/secret/age-key" ]; then
              cp "/nix/secret/age-key" "$BACKUP_DIR/age-key.backup"
              log "Backed up current age key"
            fi
            
            # Generate new age key from current SSH host key
            ${pkgs.ssh-to-age}/bin/ssh-to-age -private-key -i /etc/ssh/ssh_host_ed25519_key > /tmp/new-age-key
            
            # Verify the new key was generated
            if [ -s /tmp/new-age-key ]; then
              # Update the age key
              mkdir -p /nix/secret
              mv /tmp/new-age-key /nix/secret/age-key
              chmod 600 /nix/secret/age-key
              log "Successfully rotated age key"
            else
              log "ERROR: Failed to generate new age key"
              exit 1
            fi
          ''}
          
          # Log rotation completion
          log "Secrets rotation completed successfully"
          
          # Optional: Send notification email
          ${optionalString (config.services.secrets-rotation.notificationEmail != null) ''
            # Send notification (requires mail system configured)
            echo "Secrets rotation completed on $(hostname) at $DATE" | \
              ${pkgs.mailutils}/bin/mail -s "Secrets Rotation Complete" \
                ${config.services.secrets-rotation.notificationEmail} || true
          ''}
        '';
        
        # Security hardening
        PrivateTmp = true;
        ProtectSystem = "strict";
        ProtectHome = true;
        ReadWritePaths = [
          "/var/log"
          "/var/backup"
          "/nix/secret"
        ];
        NoNewPrivileges = true;
        MemoryDenyWriteExecute = false; # Needed for shell scripts
      };
      
      # Only run if secrets rotation is needed
      unitConfig = {
        ConditionPathExists = "/etc/ssh/ssh_host_ed25519_key";
      };
    };

    # Timer for automatic rotation
    systemd.timers.secrets-rotation = {
      description = "Automated secrets rotation timer";
      wantedBy = [ "timers.target" ];
      timerConfig = {
        OnCalendar = config.services.secrets-rotation.interval;
        Persistent = true;
        RandomizedDelaySec = "1h"; # Add some randomization
      };
    };

    # Create backup directory structure
    systemd.tmpfiles.rules = [
      "d /var/backup/secrets 0700 root root -"
      "f /var/log/secrets-rotation.log 0644 root root -"
    ];

    # Add manual rotation command and required packages
    environment.systemPackages = with pkgs; [
      sops
      ssh-to-age
      age
      (writeShellScriptBin "secrets-rotate-manual" ''
        echo "🔄 Manually triggering secrets rotation..."
        systemctl start secrets-rotation.service
        echo "✅ Secrets rotation initiated. Check logs: journalctl -u secrets-rotation"
      '')
    ];

    # Persist rotation logs and backups
    environment.persistence."/nix/persist" = lib.mkIf (config ? environment.persistence) {
      directories = [
        {
          directory = "/var/backup/secrets";
          mode = "0700";
        }
      ];
      files = [
        "/var/log/secrets-rotation.log"
      ];
    };
  };
}