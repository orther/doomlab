# Dagger-managed Pi-hole Service
# Provides DNS ad-blocking with advanced networking requirements
# Supports host networking, DNS ports (53), and NET_ADMIN capability

{ config, lib, pkgs, ... }:

with lib;

let
  cfg = config.services.dagger.pihole;
  
in {
  options.services.dagger.pihole = {
    enable = mkEnableOption "Dagger-managed Pi-hole DNS service";
    
    image = mkOption {
      type = types.str;
      default = "pihole/pihole:latest";
      description = "Container image to use for Pi-hole";
    };
    
    dataDir = mkOption {
      type = types.path;
      default = "/var/lib/pihole";
      description = "Directory for Pi-hole data and configuration";
    };
    
    dnsmasqDir = mkOption {
      type = types.path;
      default = "/var/lib/pihole/dnsmasq.d";
      description = "Directory for dnsmasq configuration";
    };
    
    webPort = mkOption {
      type = types.port;
      default = 8080;
      description = "Port for Pi-hole web interface (avoid conflict with port 80)";
    };
    
    dnsPort = mkOption {
      type = types.port;
      default = 53;
      description = "DNS port for Pi-hole (typically 53)";
    };
    
    network = mkOption {
      type = types.enum [ "host" "bridge" ];
      default = "host";
      description = "Container network mode (host recommended for DNS)";
    };
    
    # DNS Configuration
    dns = {
      upstream = mkOption {
        type = types.listOf types.str;
        default = [ "1.1.1.1" "1.0.0.1" "8.8.8.8" "8.8.4.4" ];
        description = "Upstream DNS servers";
      };
      
      conditionalForwarding = mkOption {
        type = types.bool;
        default = true;
        description = "Enable conditional forwarding for local networks";
      };
      
      localNetwork = mkOption {
        type = types.str;
        default = "10.0.10.0/24";
        description = "Local network for conditional forwarding";
      };
      
      routerIp = mkOption {
        type = types.str;
        default = "10.0.10.1";
        description = "Router IP for conditional forwarding";
      };
      
      domain = mkOption {
        type = types.str;
        default = "orther.dev";
        description = "Local domain name";
      };
    };
    
    # Pi-hole specific configuration
    timezone = mkOption {
      type = types.str;
      default = "America/New_York";
      description = "Timezone for Pi-hole container";
    };
    
    webInterface = mkOption {
      type = types.bool;
      default = true;
      description = "Enable Pi-hole web interface";
    };
    
    enableIPv6 = mkOption {
      type = types.bool;
      default = false;
      description = "Enable IPv6 support in Pi-hole";
    };
    
    # Security and management
    adminPassword = mkOption {
      type = types.nullOr types.str;
      default = null;
      description = "Admin password for Pi-hole web interface (use secrets)";
    };
    
    enableDHCP = mkOption {
      type = types.bool;
      default = false;
      description = "Enable DHCP server in Pi-hole (requires careful network setup)";
    };
    
    # Enhanced features
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
      description = "Enable health monitoring and DNS query logging";
    };
    
    enableMetrics = mkOption {
      type = types.bool;
      default = true;
      description = "Enable Pi-hole metrics export for monitoring";
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
      services = [ "infrastructure.pihole" ];
      enableBackupIntegration = cfg.enableBackup;
      enableMonitoring = cfg.enableMonitoring;
    };
    
    # Ensure SOPS secrets are available
    services.dagger.secrets.enable = mkIf (cfg.adminPassword == null) true;
    
    # Create data directories
    systemd.tmpfiles.rules = [
      "d ${cfg.dataDir} 0755 root root"
      "d ${cfg.dnsmasqDir} 0755 root root"
    ];
    
    # Special firewall configuration for DNS
    networking.firewall = {
      # DNS ports
      allowedTCPPorts = [ cfg.dnsPort cfg.webPort ];
      allowedUDPPorts = [ cfg.dnsPort ];
      
      # Allow DHCP if enabled (ports 67, 68)
      allowedUDPPorts = cfg.allowedUDPPorts ++ optional cfg.enableDHCP 67 ++ optional cfg.enableDHCP 68;
      
      # Special rules for Pi-hole on local network
      extraCommands = ''
        # Allow local network access to Pi-hole web interface
        iptables -A nixos-fw -p tcp --source ${cfg.dns.localNetwork} --dport ${toString cfg.webPort} -j nixos-fw-accept
        iptables -A nixos-fw -p udp --source ${cfg.dns.localNetwork} --dport ${toString cfg.dnsPort} -j nixos-fw-accept
        
        ${optionalString cfg.enableDHCP ''
        # DHCP server rules
        iptables -A nixos-fw -p udp --dport 67 -j nixos-fw-accept
        iptables -A nixos-fw -p udp --dport 68 -j nixos-fw-accept
        ''}
      '';
      
      extraStopCommands = ''
        iptables -D nixos-fw -p tcp --source ${cfg.dns.localNetwork} --dport ${toString cfg.webPort} -j nixos-fw-accept || true
        iptables -D nixos-fw -p udp --source ${cfg.dns.localNetwork} --dport ${toString cfg.dnsPort} -j nixos-fw-accept || true
        
        ${optionalString cfg.enableDHCP ''
        iptables -D nixos-fw -p udp --dport 67 -j nixos-fw-accept || true
        iptables -D nixos-fw -p udp --dport 68 -j nixos-fw-accept || true
        ''}
      '';
    };
    
    # Nginx reverse proxy for Pi-hole web interface
    services.nginx.virtualHosts."pihole.${cfg.dns.domain}" = mkIf config.services.nginx.enable {
      forceSSL = true;
      useACMEHost = cfg.dns.domain;
      locations."/" = {
        recommendedProxySettings = true;
        proxyPass = "http://127.0.0.1:${toString cfg.webPort}";
        extraConfig = ''
          # Pi-hole specific headers
          proxy_set_header Host $host;
          proxy_set_header X-Real-IP $remote_addr;
          proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
          proxy_set_header X-Forwarded-Proto $scheme;
          
          # Handle Pi-hole admin interface
          proxy_redirect off;
          proxy_buffering off;
        '';
      };
      
      # Health endpoint for monitoring
      locations."/dagger-health" = {
        return = "200 'healthy'";
        extraConfig = ''
          add_header Content-Type text/plain;
        '';
      };
    };
    
    # Dagger-specific systemd service
    systemd.services."dagger-infrastructure-pihole" = {
      description = "Dagger-managed Pi-hole DNS service";
      wantedBy = [ "multi-user.target" ];
      after = [ 
        "network.target" 
        "dagger-coordinator.service"
      ] ++ optional (cfg.adminPassword == null) "dagger-secret-injection.service";
      requires = [ 
        "dagger-coordinator.service"
      ] ++ optional (cfg.adminPassword == null) "dagger-secret-injection.service";
      
      environment = {
        DAGGER_PIHOLE_IMAGE = cfg.image;
        DAGGER_PIHOLE_DATA_DIR = cfg.dataDir;
        DAGGER_PIHOLE_DNSMASQ_DIR = cfg.dnsmasqDir;
        DAGGER_PIHOLE_WEB_PORT = toString cfg.webPort;
        DAGGER_PIHOLE_DNS_PORT = toString cfg.dnsPort;
        DAGGER_PIHOLE_NETWORK = cfg.network;
        DAGGER_PIHOLE_TIMEZONE = cfg.timezone;
        DAGGER_PIHOLE_UPSTREAM_DNS = concatStringsSep ";" cfg.dns.upstream;
        DAGGER_PIHOLE_CONDITIONAL_FORWARDING = if cfg.dns.conditionalForwarding then "true" else "false";
        DAGGER_PIHOLE_LOCAL_NETWORK = cfg.dns.localNetwork;
        DAGGER_PIHOLE_ROUTER_IP = cfg.dns.routerIp;
        DAGGER_PIHOLE_DOMAIN = cfg.dns.domain;
        DAGGER_PIHOLE_WEB_INTERFACE = if cfg.webInterface then "true" else "false";
        DAGGER_PIHOLE_IPV6 = if cfg.enableIPv6 then "true" else "false";
        DAGGER_PIHOLE_DHCP = if cfg.enableDHCP then "true" else "false";
        DAGGER_PIHOLE_ENABLE_AUTOUPDATE = if cfg.enableAutoUpdate then "true" else "false";
        DAGGER_PIHOLE_ENABLE_BACKUP = if cfg.enableBackup then "true" else "false";
        DAGGER_PIHOLE_ENABLE_MONITORING = if cfg.enableMonitoring then "true" else "false";
        DAGGER_PIHOLE_ENABLE_METRICS = if cfg.enableMetrics then "true" else "false";
      };
      
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
        WorkingDirectory = config.services.dagger.workingDirectory;
        User = "root";
        Group = "root";
        
        # Pi-hole requires special capabilities
        AmbientCapabilities = [ "CAP_NET_ADMIN" "CAP_NET_BIND_SERVICE" ];
        CapabilityBoundingSet = [ "CAP_NET_ADMIN" "CAP_NET_BIND_SERVICE" ];
        
        ExecStart = pkgs.writeShellScript "start-dagger-pihole" ''
          #!/bin/bash
          set -euo pipefail
          
          echo "Starting Dagger-managed Pi-hole service..."
          
          # Navigate to Dagger project
          cd ${config.services.dagger.projectDirectory}
          
          # Deploy Pi-hole via Dagger
          ${pkgs.dagger}/bin/dagger call services.infrastructure.pihole.deploy \
            --image="$DAGGER_PIHOLE_IMAGE" \
            --data-dir="$DAGGER_PIHOLE_DATA_DIR" \
            --dnsmasq-dir="$DAGGER_PIHOLE_DNSMASQ_DIR" \
            --web-port="$DAGGER_PIHOLE_WEB_PORT" \
            --dns-port="$DAGGER_PIHOLE_DNS_PORT" \
            --network="$DAGGER_PIHOLE_NETWORK" \
            --timezone="$DAGGER_PIHOLE_TIMEZONE" \
            --upstream-dns="$DAGGER_PIHOLE_UPSTREAM_DNS" \
            --conditional-forwarding="$DAGGER_PIHOLE_CONDITIONAL_FORWARDING" \
            --local-network="$DAGGER_PIHOLE_LOCAL_NETWORK" \
            --router-ip="$DAGGER_PIHOLE_ROUTER_IP" \
            --domain="$DAGGER_PIHOLE_DOMAIN" \
            --web-interface="$DAGGER_PIHOLE_WEB_INTERFACE" \
            --enable-ipv6="$DAGGER_PIHOLE_IPV6" \
            --enable-dhcp="$DAGGER_PIHOLE_DHCP" \
            --enable-autoupdate="$DAGGER_PIHOLE_ENABLE_AUTOUPDATE" \
            --enable-backup="$DAGGER_PIHOLE_ENABLE_BACKUP" \
            --enable-monitoring="$DAGGER_PIHOLE_ENABLE_MONITORING"
          
          echo "Dagger-managed Pi-hole started successfully"
        '';
        
        ExecStop = pkgs.writeShellScript "stop-dagger-pihole" ''
          #!/bin/bash
          set -euo pipefail
          
          echo "Stopping Dagger-managed Pi-hole service..."
          
          cd ${config.services.dagger.projectDirectory}
          
          # Stop Pi-hole via Dagger
          ${pkgs.dagger}/bin/dagger call services.infrastructure.pihole.stop
          
          echo "Dagger-managed Pi-hole stopped"
        '';
        
        ExecReload = pkgs.writeShellScript "reload-dagger-pihole" ''
          #!/bin/bash
          set -euo pipefail
          
          echo "Reloading Dagger-managed Pi-hole service..."
          
          cd ${config.services.dagger.projectDirectory}
          
          # Restart Pi-hole via Dagger
          ${pkgs.dagger}/bin/dagger call services.infrastructure.pihole.restart
          
          echo "Dagger-managed Pi-hole reloaded"
        '';
        
        # Resource limits
        MemoryMax = "512M";
        CPUQuota = "100%";
        TasksMax = "500";
        
        # Security settings (relaxed for DNS and DHCP capabilities)
        NoNewPrivileges = false; # Pi-hole needs capabilities
        ProtectSystem = "strict";
        ProtectHome = true;
        ReadWritePaths = [
          cfg.dataDir
          cfg.dnsmasqDir
          config.services.dagger.workingDirectory
        ];
        PrivateTmp = true;
      };
      
      # Health check integration  
      onFailure = mkIf cfg.enableMonitoring [ "dagger-pihole-health-check.service" ];
    };
    
    # Enhanced health check service
    systemd.services."dagger-pihole-health-check" = mkIf cfg.enableMonitoring {
      description = "Pi-hole health check";
      serviceConfig = {
        Type = "oneshot";
        User = "root";
        Group = "root";
        ExecStart = pkgs.writeShellScript "pihole-health-check" ''
          #!/bin/bash
          set -euo pipefail
          
          echo "Performing Pi-hole health check..."
          
          # Check if web interface is responding
          if curl -f -s --connect-timeout 10 "http://127.0.0.1:${toString cfg.webPort}/admin/" > /dev/null; then
            echo "✓ Pi-hole web interface is responding"
          else
            echo "✗ Pi-hole web interface is not responding"
            exit 1
          fi
          
          # Check DNS resolution
          if dig @127.0.0.1 -p ${toString cfg.dnsPort} google.com +short | grep -q .; then
            echo "✓ Pi-hole DNS is resolving queries"
          else
            echo "✗ Pi-hole DNS is not resolving queries"
            exit 1
          fi
          
          # Check if container is running
          if podman ps --filter "name=pihole" --format "{{.Names}}" | grep -q pihole; then
            echo "✓ Pi-hole container is running"
          else
            echo "✗ Pi-hole container is not running"
            exit 1
          fi
          
          # Check ad blocking (test known ad domain)
          if dig @127.0.0.1 -p ${toString cfg.dnsPort} ads.google.com +short | grep -q "0.0.0.0\|::"; then
            echo "✓ Pi-hole ad blocking is working"
          else
            echo "⚠️  Pi-hole ad blocking may not be working properly"
          fi
          
          echo "Pi-hole health check completed successfully"
        '';
      };
    };
    
    # Backup service integration
    systemd.services."dagger-backup-pihole" = mkIf cfg.enableBackup {
      description = "Backup Pi-hole via Dagger pipeline";
      wantedBy = [ "default.target" ];
      after = [ "dagger-infrastructure-pihole.service" ];
      requisite = mkIf (config.sops.secrets ? "kopia-repository-token") [ "sops-nix.service" ];
      
      serviceConfig = {
        Type = "oneshot";
        User = "root";
        Group = "root";
        WorkingDirectory = config.services.dagger.projectDirectory;
        
        ExecStart = pkgs.writeShellScript "dagger-backup-pihole" ''
          #!/bin/bash
          set -euo pipefail
          
          echo "Starting Dagger-managed Pi-hole backup..."
          
          # Run backup via Dagger pipeline
          ${pkgs.dagger}/bin/dagger call services.infrastructure.pihole.backup.backup \
            --service="pihole" \
            --paths="${cfg.dataDir},${cfg.dnsmasqDir}"
          
          echo "Dagger-managed Pi-hole backup completed"
        '';
        
        # Environment for secrets access
        EnvironmentFile = mkIf (config.sops.secrets ? "kopia-repository-token") 
          config.sops.secrets."kopia-repository-token".path;
      };
    };
    
    # Backup timer
    systemd.timers."dagger-backup-pihole" = mkIf cfg.enableBackup {
      description = "Backup Pi-hole via Dagger";
      wantedBy = [ "timers.target" ];
      timerConfig = {
        OnCalendar = "*-*-* 3:00:00";
        RandomizedDelaySec = "1h";
        Persistent = true;
      };
    };
    
    # Auto-update timer
    systemd.timers."dagger-autoupdate-pihole" = mkIf cfg.enableAutoUpdate {
      description = "Auto-update Pi-hole container via Dagger";
      wantedBy = [ "timers.target" ];
      timerConfig = {
        OnCalendar = "*-*-* 6:00:00";
        RandomizedDelaySec = "1h";
        Persistent = true;
      };
    };
    
    systemd.services."dagger-autoupdate-pihole" = mkIf cfg.enableAutoUpdate {
      description = "Auto-update Pi-hole container";
      serviceConfig = {
        Type = "oneshot";
        User = "root";
        Group = "root";
        WorkingDirectory = config.services.dagger.projectDirectory;
        
        ExecStart = pkgs.writeShellScript "dagger-autoupdate-pihole" ''
          #!/bin/bash
          set -euo pipefail
          
          echo "Checking for Pi-hole container updates..."
          
          # Update via Dagger pipeline
          ${pkgs.dagger}/bin/dagger call services.infrastructure.pihole.update \
            --check-only=false
          
          echo "Pi-hole container update check completed"
        '';
      };
    };
    
    # Persistence configuration
    environment.persistence."/nix/persist" = mkIf config.environment.persistence."/nix/persist".enable {
      directories = [
        cfg.dataDir
        cfg.dnsmasqDir
      ];
    };
    
    # DNS service resolver integration
    services.resolved = mkIf cfg.enable {
      enable = mkForce false; # Avoid conflicts with Pi-hole
    };
    
    # Custom dnsmasq configuration
    environment.etc."dagger-pihole/dnsmasq-custom.conf" = {
      text = ''
        # Custom dnsmasq configuration for Pi-hole
        # This file is mounted into the Pi-hole container
        
        ${optionalString cfg.dns.conditionalForwarding ''
        # Conditional forwarding for local network
        server=/${cfg.dns.domain}/${cfg.dns.routerIp}
        ''}
        
        # Enhanced logging
        log-queries
        log-facility=/var/log/pihole.log
        
        # Performance optimizations
        cache-size=10000
        dns-forward-max=1000
        
        # Local domain resolution
        local=/${cfg.dns.domain}/
        domain=${cfg.dns.domain}
        expand-hosts
      '';
      mode = "0644";
    };
    
    # Monitoring integration
    services.netdata.configDir = mkIf (cfg.enableMetrics && config.services.netdata.enable) {
      "python.d/pihole.conf" = pkgs.writeText "pihole.conf" ''
        pihole:
          url: 'http://127.0.0.1:${toString cfg.webPort}'
          password: '${if cfg.adminPassword != null then cfg.adminPassword else "get_from_secrets"}'
          update_every: 30
      '';
    };
    
    # Assertions to ensure proper configuration
    assertions = [
      {
        assertion = cfg.dnsPort != cfg.webPort;
        message = "Pi-hole DNS port and web port must be different";
      }
      {
        assertion = cfg.dataDir != "";
        message = "Pi-hole data directory must be specified";
      }
      {
        assertion = config.services.dagger.enable;
        message = "Dagger service must be enabled for Dagger-managed Pi-hole";
      }
      {
        assertion = !config.services.resolved.enable || !cfg.enable;
        message = "systemd-resolved conflicts with Pi-hole DNS service";
      }
      {
        assertion = !(cfg.enableDHCP && config.networking.dhcpcd.enable);
        message = "Pi-hole DHCP conflicts with dhcpcd - disable one of them";
      }
    ];
    
    # Warnings for network configuration
    warnings = 
      (optional (cfg.network != "host") 
        "Pi-hole works best with host networking for DNS resolution") ++
      (optional (cfg.enableDHCP && cfg.network != "host")
        "DHCP server requires host networking to function properly") ++
      (optional (cfg.adminPassword != null)
        "Consider using SOPS secrets instead of hardcoding Pi-hole admin password");
  };
}