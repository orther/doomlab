# Dagger-Nixarr Integration Module
# Complete integration module that enables Dagger-enhanced nixarr services
# alongside the existing NixOS configuration

{
  config,
  lib,
  pkgs,
  ...
}:

with lib;

{
  imports = [
    ./base.nix
    ./secrets.nix
    ./nixarr.nix
    ./homebridge.nix
    ./pihole.nix
    ./portainer.nix
    ./unpackerr.nix
    ./infrastructure.nix
    ./validation.nix
    ./migration.nix
  ];

  options.services.dagger.nixarr.integration = {
    enable = mkEnableOption "Complete Dagger-Nixarr integration";
    
    replaceExistingServices = mkOption {
      type = types.bool;
      default = false;
      description = "Replace existing nixarr services with Dagger-enhanced versions";
    };
    
    enhanceExistingServices = mkOption {
      type = types.bool;
      default = true;
      description = "Enhance existing nixarr services with Dagger capabilities while keeping them running";
    };
    
    enableAllServices = mkOption {
      type = types.bool;
      default = false;
      description = "Enable all nixarr services (Sonarr, Radarr, Prowlarr, Bazarr, Transmission, Jellyfin)";
    };
  };

  config = mkIf config.services.dagger.nixarr.integration.enable {
    # Enable the base Dagger integration
    services.dagger.nixarr.enable = true;
    
    # Auto-enable all services if requested
    services.dagger.nixarr = mkIf config.services.dagger.nixarr.integration.enableAllServices {
      sonarr.enable = mkDefault true;
      radarr.enable = mkDefault true;
      prowlarr.enable = mkDefault true;
      bazarr.enable = mkDefault true;
      transmission.enable = mkDefault true;
      jellyfin.enable = mkDefault true;
    };

    # Enhanced monitoring and backup by default
    services.dagger.nixarr.monitoring.enable = mkDefault true;
    services.dagger.nixarr.backup.enable = mkDefault true;

    # Migration compatibility enabled by default unless replacing services
    services.dagger.nixarr.migration.enableCompatibilityMode = mkDefault (!config.services.dagger.nixarr.integration.replaceExistingServices);

    # If replacing existing services, disable them
    nixarr = mkIf config.services.dagger.nixarr.integration.replaceExistingServices {
      enable = mkForce false;
    };

    # Enhanced nginx configuration for Dagger services
    services.nginx.virtualHosts = let
      cfg = config.services.dagger.nixarr;
      domain = cfg.network.domain;
    in mkIf config.services.nginx.enable {
      # Sonarr with enhanced headers
      "sonarr.${domain}" = mkIf cfg.sonarr.enable {
        forceSSL = true;
        useACMEHost = domain;
        locations."/" = {
          recommendedProxySettings = true;
          proxyPass = "http://127.0.0.1:${toString cfg.sonarr.port}";
          extraConfig = ''
            # Enhanced security headers
            proxy_set_header X-Forwarded-Proto $scheme;
            proxy_set_header X-Forwarded-Host $host;
            proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
            
            # Dagger-specific health check bypass
            location /dagger-health {
              return 200 "healthy";
              add_header Content-Type text/plain;
            }
          '';
        };
      };

      # Radarr with enhanced headers
      "radarr.${domain}" = mkIf cfg.radarr.enable {
        forceSSL = true;
        useACMEHost = domain;
        locations."/" = {
          recommendedProxySettings = true;
          proxyPass = "http://127.0.0.1:${toString cfg.radarr.port}";
          extraConfig = ''
            proxy_set_header X-Forwarded-Proto $scheme;
            proxy_set_header X-Forwarded-Host $host;
            proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
            
            location /dagger-health {
              return 200 "healthy";
              add_header Content-Type text/plain;
            }
          '';
        };
      };

      # Prowlarr with enhanced headers
      "prowlarr.${domain}" = mkIf cfg.prowlarr.enable {
        forceSSL = true;
        useACMEHost = domain;
        locations."/" = {
          recommendedProxySettings = true;
          proxyPass = "http://127.0.0.1:${toString cfg.prowlarr.port}";
          extraConfig = ''
            proxy_set_header X-Forwarded-Proto $scheme;
            proxy_set_header X-Forwarded-Host $host;
            proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
            
            location /dagger-health {
              return 200 "healthy";
              add_header Content-Type text/plain;
            }
          '';
        };
      };

      # Bazarr configuration
      "bazarr.${domain}" = mkIf cfg.bazarr.enable {
        forceSSL = true;
        useACMEHost = domain;
        locations."/" = {
          recommendedProxySettings = true;
          proxyPass = "http://127.0.0.1:${toString cfg.bazarr.port}";
          extraConfig = ''
            proxy_set_header X-Forwarded-Proto $scheme;
            proxy_set_header X-Forwarded-Host $host;
            proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
          '';
        };
      };

      # Transmission with enhanced security
      "transmission.${domain}" = mkIf cfg.transmission.enable {
        forceSSL = true;
        useACMEHost = domain;
        locations."/" = {
          proxyPass = "http://127.0.0.1:${toString cfg.transmission.port}";
          extraConfig = ''
            proxy_set_header X-Forwarded-Proto $scheme;
            proxy_set_header X-Forwarded-Host $host;
            proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
            
            # Enhanced authentication for transmission
            proxy_set_header X-Real-IP $remote_addr;
          '';
        };
      };

      # Jellyfin with streaming optimizations
      "watch.${domain}" = mkIf cfg.jellyfin.enable {
        forceSSL = true;
        useACMEHost = domain;
        locations."/" = {
          recommendedProxySettings = true;
          proxyPass = "http://127.0.0.1:${toString cfg.jellyfin.port}";
          extraConfig = ''
            # Jellyfin-specific optimizations
            proxy_set_header X-Forwarded-Proto $scheme;
            proxy_set_header X-Forwarded-Host $host;
            proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
            
            # Streaming optimizations
            proxy_buffering off;
            proxy_request_buffering off;
            
            # WebSocket support for live updates
            proxy_http_version 1.1;
            proxy_set_header Upgrade $http_upgrade;
            proxy_set_header Connection "upgrade";
            
            # Large file support
            client_max_body_size 20M;
          '';
        };
      };
    };

    # Enhanced systemd integration
    systemd.services = {
      # Integration health check service
      dagger-nixarr-integration = {
        description = "Dagger-Nixarr Integration Health Check";
        after = ["dagger-secrets.service"];
        wants = ["dagger-secrets.service"];
        
        serviceConfig = {
          Type = "simple";
          User = "dagger";
          Group = "dagger";
          Restart = "always";
          RestartSec = "60s";
        };

        script = ''
          while true; do
            echo "Running Dagger-Nixarr integration health check..."
            
            # Check Dagger daemon
            if ! ${pkgs.dagger}/bin/dagger version > /dev/null 2>&1; then
              echo "ERROR: Dagger daemon not accessible"
            else
              echo "✓ Dagger daemon healthy"
            fi
            
            # Check nixarr service health via Dagger
            if ${pkgs.dagger}/bin/dagger call services nixarr orchestration monitor > /dev/null 2>&1; then
              echo "✓ Nixarr services healthy via Dagger"
            else
              echo "⚠️  Some nixarr services may be unhealthy"
            fi
            
            # Check for port conflicts
            if nixarr-migration-status | grep -q "CONFLICT"; then
              echo "⚠️  Service conflicts detected"
            else
              echo "✓ No service conflicts detected"
            fi
            
            sleep 300  # Check every 5 minutes
          done
        '';
      };

      # Integration status reporter
      dagger-nixarr-status-reporter = {
        description = "Dagger-Nixarr Status Reporter";
        
        serviceConfig = {
          Type = "oneshot";
          User = "dagger";
          Group = "dagger";
        };

        script = ''
          echo "=== Dagger-Nixarr Integration Status ===" > /var/lib/dagger/integration-status.txt
          echo "Report generated: $(date)" >> /var/lib/dagger/integration-status.txt
          echo "" >> /var/lib/dagger/integration-status.txt
          
          # Service status
          echo "=== Service Status ===" >> /var/lib/dagger/integration-status.txt
          nixarr-migration-status >> /var/lib/dagger/integration-status.txt
          echo "" >> /var/lib/dagger/integration-status.txt
          
          # Dagger status
          echo "=== Dagger Status ===" >> /var/lib/dagger/integration-status.txt
          ${pkgs.dagger}/bin/dagger version >> /var/lib/dagger/integration-status.txt 2>&1 || echo "Dagger not available" >> /var/lib/dagger/integration-status.txt
          echo "" >> /var/lib/dagger/integration-status.txt
          
          # Resource usage
          echo "=== Resource Usage ===" >> /var/lib/dagger/integration-status.txt
          df -h ${config.services.dagger.nixarr.storage.mediaRoot} >> /var/lib/dagger/integration-status.txt
          df -h ${config.services.dagger.nixarr.storage.stateRoot} >> /var/lib/dagger/integration-status.txt
          echo "" >> /var/lib/dagger/integration-status.txt
          
          # Recent log entries
          echo "=== Recent Activity ===" >> /var/lib/dagger/integration-status.txt
          journalctl -u 'dagger-*' --since '1 hour ago' --no-pager -n 20 >> /var/lib/dagger/integration-status.txt 2>&1 || echo "No recent Dagger activity" >> /var/lib/dagger/integration-status.txt
          
          echo "Status report saved to /var/lib/dagger/integration-status.txt"
        '';
      };
    };

    # Status reporting timer
    systemd.timers.dagger-nixarr-status-reporter = {
      description = "Dagger-Nixarr Status Reporter Timer";
      wantedBy = ["timers.target"];

      timerConfig = {
        OnCalendar = "hourly";
        RandomizedDelaySec = "5m";
        Persistent = true;
      };
    };

    # Enhanced environment packages
    environment.systemPackages = with pkgs; [
      # Dagger CLI with completion
      dagger
      
      # Integration utilities
      (writeShellScriptBin "dagger-nixarr-summary" ''
        echo "Dagger-Nixarr Integration Summary"
        echo "================================="
        echo
        
        if [ -f /var/lib/dagger/integration-status.txt ]; then
          cat /var/lib/dagger/integration-status.txt
        else
          echo "No status report available. Run: systemctl start dagger-nixarr-status-reporter"
        fi
        
        echo
        echo "Quick Commands:"
        echo "  nixarr-migrate status    - Check migration status"
        echo "  dagger call nixarr       - Access Dagger nixarr actions"
        echo "  journalctl -u dagger-*   - View Dagger service logs"
      '')
    ];

    # Bash completion for nixarr commands
    programs.bash.completion.enable = mkDefault true;
    environment.shellInit = ''
      # Dagger-Nixarr integration helpers
      alias dnn='dagger call nixarr'
      alias nixarr-logs='journalctl -u "dagger-*nixarr*" -f'
      alias nixarr-status='nixarr-migrate status'
    '';

    # Documentation integration
    documentation.enable = mkDefault true;
    environment.etc."dagger-nixarr/README.md" = {
      text = ''
        # Dagger-Enhanced Nixarr Services

        This system provides enhanced nixarr services via Dagger container orchestration,
        maintaining compatibility with your existing NixOS configuration.

        ## Quick Start

        1. **Check Status**: `nixarr-migrate status`
        2. **View Integration Summary**: `dagger-nixarr-summary`
        3. **Migrate Service**: `nixarr-migrate migrate sonarr`
        4. **Rollback if Needed**: `nixarr-migrate rollback sonarr`

        ## Available Services

        ${concatStringsSep "\n        " (map (s: "- ${s}") ["sonarr" "radarr" "prowlarr" "bazarr" "transmission" "jellyfin"])}

        ## Configuration

        Services are configured via NixOS options under `services.dagger.nixarr.*`
        
        ## Monitoring

        - Integration health: `journalctl -u dagger-nixarr-integration -f`
        - Service logs: `journalctl -u "dagger-*" -f`
        - Status reports: `/var/lib/dagger/integration-status.txt`

        ## Data Locations

        - Service configs: `${config.services.dagger.nixarr.storage.stateRoot}/nixarr/`
        - Media files: `${config.services.dagger.nixarr.storage.mediaRoot}/`
        - Backups: `/var/lib/dagger/backups/`

        ## Troubleshooting

        1. **Port Conflicts**: Check with `nixarr-migrate status`
        2. **Service Issues**: View logs with `nixarr-logs`
        3. **Migration Problems**: Use `nixarr-migrate rollback <service>`

        For more information, see the NixOS configuration and Dagger CUE definitions.
      '';
      mode = "0644";
    };
  };
}