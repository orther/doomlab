# Dagger-managed Portainer Service
# Container management platform with Docker socket mounting and advanced security
# Provides secure access to container orchestration capabilities

{ config, lib, pkgs, ... }:

with lib;

let
  cfg = config.services.dagger.portainer;
  
in {
  options.services.dagger.portainer = {
    enable = mkEnableOption "Dagger-managed Portainer container management service";
    
    image = mkOption {
      type = types.str;
      default = "portainer/portainer-ce:latest";
      description = "Container image to use for Portainer";
    };
    
    dataDir = mkOption {
      type = types.path;
      default = "/var/lib/portainer";
      description = "Directory for Portainer data and configuration";
    };
    
    port = mkOption {
      type = types.port;
      default = 9000;
      description = "Port for Portainer web interface";
    };
    
    sslPort = mkOption {
      type = types.port;
      default = 9443;
      description = "HTTPS port for Portainer web interface";
    };
    
    edgePort = mkOption {
      type = types.port;
      default = 8000;
      description = "Port for Portainer Edge agent communication";
    };
    
    # Container runtime configuration
    containerRuntime = mkOption {
      type = types.enum [ "podman" "docker" ];
      default = "podman";
      description = "Container runtime to manage (podman or docker)";
    };
    
    socketPath = mkOption {
      type = types.str;
      default = if cfg.containerRuntime == "podman" 
                then "/run/podman/podman.sock" 
                else "/var/run/docker.sock";
      description = "Path to container runtime socket";
    };
    
    # Security and access control
    adminUser = mkOption {
      type = types.str;
      default = "admin";
      description = "Default admin username for Portainer";
    };
    
    requireAuthentication = mkOption {
      type = types.bool;
      default = true;
      description = "Require authentication for Portainer access";
    };
    
    enableSSL = mkOption {
      type = types.bool;
      default = true;
      description = "Enable SSL/TLS for Portainer web interface";
    };
    
    # Feature flags
    enableEdgeAgent = mkOption {
      type = types.bool;
      default = false;
      description = "Enable Portainer Edge agent functionality";
    };
    
    enableTunnel = mkOption {
      type = types.bool;
      default = false;
      description = "Enable Portainer tunnel server for edge environments";
    };
    
    hideLabels = mkOption {
      type = types.listOf types.str;
      default = [ "io.kubernetes.*" "com.docker.*" ];
      description = "Container labels to hide in Portainer interface";
    };
    
    # Resource and security limits
    enableResourceLimits = mkOption {
      type = types.bool;
      default = true;
      description = "Enable resource limits for managed containers";
    };
    
    maxContainerCpuLimit = mkOption {
      type = types.str;
      default = "2";
      description = "Maximum CPU limit for containers managed through Portainer";
    };
    
    maxContainerMemoryLimit = mkOption {
      type = types.str;
      default = "4G";
      description = "Maximum memory limit for containers managed through Portainer";
    };
    
    # Integration options
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
      description = "Enable health monitoring and metrics";
    };
    
    enableAuditLog = mkOption {
      type = types.bool;
      default = true;
      description = "Enable audit logging for container operations";
    };
    
    # Network configuration
    allowedNetworks = mkOption {
      type = types.listOf types.str;
      default = [ "10.0.10.0/24" "100.64.0.0/10" ]; # Local network + Tailscale
      description = "Networks allowed to access Portainer";
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
      services = [ "infrastructure.portainer" ];
      enableBackupIntegration = cfg.enableBackup;
      enableMonitoring = cfg.enableMonitoring;
    };
    
    # Ensure container runtime is properly configured
    virtualisation.podman = mkIf (cfg.containerRuntime == "podman") {
      enable = true;
      dockerCompat = true;
      autoPrune.enable = true;
      defaultNetwork.settings.dns_enabled = true;
      
      # Enable socket activation for Portainer access
      extraPackages = [ pkgs.podman-compose ];
    };
    
    virtualisation.docker = mkIf (cfg.containerRuntime == "docker") {
      enable = true;
      autoPrune.enable = true;
      
      # Security daemon configuration
      daemon.settings = {
        log-driver = "journald";
        log-opts = {
          max-size = "10m";
          max-file = "3";
        };
        
        # Security options
        userns-remap = "default";
        no-new-privileges = true;
        
        # Resource limits
        default-ulimits = {
          memlock = {
            Name = "memlock";
            Soft = -1;
            Hard = -1;
          };
        };
      };
    };
    
    # Create data directory
    systemd.tmpfiles.rules = [
      "d ${cfg.dataDir} 0755 root root"
      "d ${cfg.dataDir}/data 0755 root root"
      "d ${cfg.dataDir}/ssl 0755 root root"
      "d /var/log/portainer 0755 root root"
    ];
    
    # Configure firewall
    networking.firewall = {
      allowedTCPPorts = [ cfg.port ] 
        ++ optional cfg.enableSSL cfg.sslPort
        ++ optional cfg.enableEdgeAgent cfg.edgePort;
      
      # Network-specific access rules
      extraCommands = concatMapStringsSep "\n" (network: ''
        iptables -A nixos-fw -p tcp --source ${network} --dport ${toString cfg.port} -j nixos-fw-accept
        ${optionalString cfg.enableSSL ''
        iptables -A nixos-fw -p tcp --source ${network} --dport ${toString cfg.sslPort} -j nixos-fw-accept
        ''}
      '') cfg.allowedNetworks;
      
      extraStopCommands = concatMapStringsSep "\n" (network: ''
        iptables -D nixos-fw -p tcp --source ${network} --dport ${toString cfg.port} -j nixos-fw-accept || true
        ${optionalString cfg.enableSSL ''
        iptables -D nixos-fw -p tcp --source ${network} --dport ${toString cfg.sslPort} -j nixos-fw-accept || true
        ''}
      '') cfg.allowedNetworks;
    };
    
    # Nginx reverse proxy with enhanced security
    services.nginx.virtualHosts."portainer.orther.dev" = mkIf config.services.nginx.enable {
      forceSSL = true;
      useACMEHost = "orther.dev";
      
      locations."/" = {
        recommendedProxySettings = true;
        proxyPass = if cfg.enableSSL 
                   then "https://127.0.0.1:${toString cfg.sslPort}"
                   else "http://127.0.0.1:${toString cfg.port}";
        
        extraConfig = ''
          # Portainer-specific headers
          proxy_set_header Connection "";
          proxy_set_header X-Forwarded-Proto $scheme;
          proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
          proxy_set_header X-Real-IP $remote_addr;
          
          # WebSocket support for real-time updates
          proxy_http_version 1.1;
          proxy_set_header Upgrade $http_upgrade;
          proxy_set_header Connection "upgrade";
          
          # Security headers
          proxy_set_header X-Content-Type-Options nosniff;
          proxy_set_header X-Frame-Options SAMEORIGIN;
          proxy_set_header X-XSS-Protection "1; mode=block";
          
          # Timeout configurations for long operations
          proxy_read_timeout 300;
          proxy_connect_timeout 300;
          proxy_send_timeout 300;
          
          # Large request support for container uploads
          client_max_body_size 2G;
          proxy_request_buffering off;
          
          ${optionalString cfg.enableSSL ''
          # SSL verification for backend
          proxy_ssl_verify off;
          ''}
        '';
      };
      
      # Health endpoint
      locations."/dagger-health" = {
        return = "200 'healthy'";
        extraConfig = ''
          add_header Content-Type text/plain;
        '';
      };
      
      # Edge agent endpoint
      locations."/edge" = mkIf cfg.enableEdgeAgent {
        proxyPass = "http://127.0.0.1:${toString cfg.edgePort}";
        extraConfig = ''
          proxy_set_header Upgrade $http_upgrade;
          proxy_set_header Connection "upgrade";
          proxy_http_version 1.1;
        '';
      };
    };
    
    # Dagger-specific systemd service
    systemd.services."dagger-infrastructure-portainer" = {
      description = "Dagger-managed Portainer container management service";
      wantedBy = [ "multi-user.target" ];
      after = [ 
        "network.target" 
        "dagger-coordinator.service"
        "${cfg.containerRuntime}.service"
      ];
      requires = [ 
        "dagger-coordinator.service"
        "${cfg.containerRuntime}.service"
      ];
      
      environment = {
        DAGGER_PORTAINER_IMAGE = cfg.image;
        DAGGER_PORTAINER_DATA_DIR = cfg.dataDir;
        DAGGER_PORTAINER_PORT = toString cfg.port;
        DAGGER_PORTAINER_SSL_PORT = toString cfg.sslPort;
        DAGGER_PORTAINER_EDGE_PORT = toString cfg.edgePort;
        DAGGER_PORTAINER_CONTAINER_RUNTIME = cfg.containerRuntime;
        DAGGER_PORTAINER_SOCKET_PATH = cfg.socketPath;
        DAGGER_PORTAINER_ADMIN_USER = cfg.adminUser;
        DAGGER_PORTAINER_REQUIRE_AUTH = if cfg.requireAuthentication then "true" else "false";
        DAGGER_PORTAINER_ENABLE_SSL = if cfg.enableSSL then "true" else "false";
        DAGGER_PORTAINER_ENABLE_EDGE = if cfg.enableEdgeAgent then "true" else "false";
        DAGGER_PORTAINER_ENABLE_TUNNEL = if cfg.enableTunnel then "true" else "false";
        DAGGER_PORTAINER_HIDE_LABELS = concatStringsSep "," cfg.hideLabels;
        DAGGER_PORTAINER_RESOURCE_LIMITS = if cfg.enableResourceLimits then "true" else "false";
        DAGGER_PORTAINER_MAX_CPU = cfg.maxContainerCpuLimit;
        DAGGER_PORTAINER_MAX_MEMORY = cfg.maxContainerMemoryLimit;
        DAGGER_PORTAINER_ALLOWED_NETWORKS = concatStringsSep "," cfg.allowedNetworks;
        DAGGER_PORTAINER_ENABLE_AUTOUPDATE = if cfg.enableAutoUpdate then "true" else "false";
        DAGGER_PORTAINER_ENABLE_BACKUP = if cfg.enableBackup then "true" else "false";
        DAGGER_PORTAINER_ENABLE_MONITORING = if cfg.enableMonitoring then "true" else "false";
        DAGGER_PORTAINER_ENABLE_AUDIT = if cfg.enableAuditLog then "true" else "false";
      };
      
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
        WorkingDirectory = config.services.dagger.workingDirectory;
        User = "root";
        Group = "root";
        
        # Portainer needs access to container socket
        SupplementaryGroups = [ 
          (if cfg.containerRuntime == "podman" then "podman" else "docker")
        ];
        
        ExecStart = pkgs.writeShellScript "start-dagger-portainer" ''
          #!/bin/bash
          set -euo pipefail
          
          echo "Starting Dagger-managed Portainer service..."
          
          # Verify socket access
          if [ ! -S "${cfg.socketPath}" ]; then
            echo "ERROR: Container runtime socket not found at ${cfg.socketPath}"
            echo "Ensure ${cfg.containerRuntime} service is running"
            exit 1
          fi
          
          # Check socket permissions
          if ! [ -r "${cfg.socketPath}" ] || ! [ -w "${cfg.socketPath}" ]; then
            echo "ERROR: Insufficient permissions for container runtime socket"
            echo "Adding root to ${cfg.containerRuntime} group..."
            ${pkgs.shadow}/bin/usermod -aG ${cfg.containerRuntime} root || true
          fi
          
          # Navigate to Dagger project
          cd ${config.services.dagger.projectDirectory}
          
          # Deploy Portainer via Dagger
          ${pkgs.dagger}/bin/dagger call services.infrastructure.portainer.deploy \
            --image="$DAGGER_PORTAINER_IMAGE" \
            --data-dir="$DAGGER_PORTAINER_DATA_DIR" \
            --port="$DAGGER_PORTAINER_PORT" \
            --ssl-port="$DAGGER_PORTAINER_SSL_PORT" \
            --edge-port="$DAGGER_PORTAINER_EDGE_PORT" \
            --container-runtime="$DAGGER_PORTAINER_CONTAINER_RUNTIME" \
            --socket-path="$DAGGER_PORTAINER_SOCKET_PATH" \
            --admin-user="$DAGGER_PORTAINER_ADMIN_USER" \
            --require-auth="$DAGGER_PORTAINER_REQUIRE_AUTH" \
            --enable-ssl="$DAGGER_PORTAINER_ENABLE_SSL" \
            --enable-edge="$DAGGER_PORTAINER_ENABLE_EDGE" \
            --enable-tunnel="$DAGGER_PORTAINER_ENABLE_TUNNEL" \
            --hide-labels="$DAGGER_PORTAINER_HIDE_LABELS" \
            --resource-limits="$DAGGER_PORTAINER_RESOURCE_LIMITS" \
            --max-cpu="$DAGGER_PORTAINER_MAX_CPU" \
            --max-memory="$DAGGER_PORTAINER_MAX_MEMORY" \
            --allowed-networks="$DAGGER_PORTAINER_ALLOWED_NETWORKS" \
            --enable-autoupdate="$DAGGER_PORTAINER_ENABLE_AUTOUPDATE" \
            --enable-backup="$DAGGER_PORTAINER_ENABLE_BACKUP" \
            --enable-monitoring="$DAGGER_PORTAINER_ENABLE_MONITORING" \
            --enable-audit="$DAGGER_PORTAINER_ENABLE_AUDIT"
          
          echo "Dagger-managed Portainer started successfully"
        '';
        
        ExecStop = pkgs.writeShellScript "stop-dagger-portainer" ''
          #!/bin/bash
          set -euo pipefail
          
          echo "Stopping Dagger-managed Portainer service..."
          
          cd ${config.services.dagger.projectDirectory}
          
          # Stop Portainer via Dagger
          ${pkgs.dagger}/bin/dagger call services.infrastructure.portainer.stop
          
          echo "Dagger-managed Portainer stopped"
        '';
        
        ExecReload = pkgs.writeShellScript "reload-dagger-portainer" ''
          #!/bin/bash
          set -euo pipefail
          
          echo "Reloading Dagger-managed Portainer service..."
          
          cd ${config.services.dagger.projectDirectory}
          
          # Restart Portainer via Dagger
          ${pkgs.dagger}/bin/dagger call services.infrastructure.portainer.restart
          
          echo "Dagger-managed Portainer reloaded"
        '';
        
        # Resource limits
        MemoryMax = "1G";
        CPUQuota = "200%";
        TasksMax = "1000";
        
        # Security settings (need socket access)
        NoNewPrivileges = true;
        ProtectSystem = "strict";
        ProtectHome = true;
        ReadWritePaths = [
          cfg.dataDir
          "/var/log/portainer"
          config.services.dagger.workingDirectory
          cfg.socketPath  # Need access to container runtime socket
        ];
        PrivateTmp = true;
        
        # Required for container socket access
        ProtectKernelTunables = false;
        ProtectControlGroups = false;
      };
      
      # Health check integration  
      onFailure = mkIf cfg.enableMonitoring [ "dagger-portainer-health-check.service" ];
    };
    
    # Enhanced health check service
    systemd.services."dagger-portainer-health-check" = mkIf cfg.enableMonitoring {
      description = "Portainer health check";
      serviceConfig = {
        Type = "oneshot";
        User = "root";
        Group = "root";
        ExecStart = pkgs.writeShellScript "portainer-health-check" ''
          #!/bin/bash
          set -euo pipefail
          
          echo "Performing Portainer health check..."
          
          # Check if web interface is responding
          endpoint="http://127.0.0.1:${toString cfg.port}"
          if cfg.enableSSL; then
            endpoint="https://127.0.0.1:${toString cfg.sslPort}"
          fi
          
          if curl -f -s --connect-timeout 10 "$endpoint/api/status" > /dev/null; then
            echo "✓ Portainer web interface is responding"
          else
            echo "✗ Portainer web interface is not responding"
            exit 1
          fi
          
          # Check container runtime connectivity
          if curl -f -s --connect-timeout 5 "$endpoint/api/endpoints" | grep -q "Name"; then
            echo "✓ Portainer can connect to container runtime"
          else
            echo "✗ Portainer cannot connect to container runtime"
            exit 1
          fi
          
          # Check if container is running
          if ${cfg.containerRuntime} ps --filter "name=portainer" --format "{{.Names}}" | grep -q portainer; then
            echo "✓ Portainer container is running"
          else
            echo "✗ Portainer container is not running"
            exit 1
          fi
          
          # Check socket permissions
          if [ -S "${cfg.socketPath}" ] && [ -r "${cfg.socketPath}" ]; then
            echo "✓ Container runtime socket is accessible"
          else
            echo "⚠️  Container runtime socket may have permission issues"
          fi
          
          # Test container operations (if possible)
          if curl -f -s --connect-timeout 5 "$endpoint/api/containers/json" > /dev/null; then
            echo "✓ Portainer can list containers"
          else
            echo "⚠️  Portainer may have issues listing containers"
          fi
          
          echo "Portainer health check completed successfully"
        '';
      };
    };
    
    # Backup service integration
    systemd.services."dagger-backup-portainer" = mkIf cfg.enableBackup {
      description = "Backup Portainer via Dagger pipeline";
      wantedBy = [ "default.target" ];
      after = [ "dagger-infrastructure-portainer.service" ];
      requisite = mkIf (config.sops.secrets ? "kopia-repository-token") [ "sops-nix.service" ];
      
      serviceConfig = {
        Type = "oneshot";
        User = "root";
        Group = "root";
        WorkingDirectory = config.services.dagger.projectDirectory;
        
        ExecStart = pkgs.writeShellScript "dagger-backup-portainer" ''
          #!/bin/bash
          set -euo pipefail
          
          echo "Starting Dagger-managed Portainer backup..."
          
          # Run backup via Dagger pipeline
          ${pkgs.dagger}/bin/dagger call services.infrastructure.portainer.backup.backup \
            --service="portainer" \
            --paths="${cfg.dataDir}"
          
          echo "Dagger-managed Portainer backup completed"
        '';
        
        # Environment for secrets access
        EnvironmentFile = mkIf (config.sops.secrets ? "kopia-repository-token") 
          config.sops.secrets."kopia-repository-token".path;
      };
    };
    
    # Backup timer
    systemd.timers."dagger-backup-portainer" = mkIf cfg.enableBackup {
      description = "Backup Portainer via Dagger";
      wantedBy = [ "timers.target" ];
      timerConfig = {
        OnCalendar = "*-*-* 2:00:00";
        RandomizedDelaySec = "1h";
        Persistent = true;
      };
    };
    
    # Auto-update timer
    systemd.timers."dagger-autoupdate-portainer" = mkIf cfg.enableAutoUpdate {
      description = "Auto-update Portainer container via Dagger";
      wantedBy = [ "timers.target" ];
      timerConfig = {
        OnCalendar = "*-*-* 5:00:00";
        RandomizedDelaySec = "1h";
        Persistent = true;
      };
    };
    
    systemd.services."dagger-autoupdate-portainer" = mkIf cfg.enableAutoUpdate {
      description = "Auto-update Portainer container";
      serviceConfig = {
        Type = "oneshot";
        User = "root";
        Group = "root";
        WorkingDirectory = config.services.dagger.projectDirectory;
        
        ExecStart = pkgs.writeShellScript "dagger-autoupdate-portainer" ''
          #!/bin/bash
          set -euo pipefail
          
          echo "Checking for Portainer container updates..."
          
          # Update via Dagger pipeline
          ${pkgs.dagger}/bin/dagger call services.infrastructure.portainer.update \
            --check-only=false
          
          echo "Portainer container update check completed"
        '';
      };
    };
    
    # Audit logging service
    systemd.services."portainer-audit-logger" = mkIf cfg.enableAuditLog {
      description = "Portainer audit log monitoring";
      after = [ "dagger-infrastructure-portainer.service" ];
      
      serviceConfig = {
        Type = "simple";
        User = "root";
        Group = "root";
        Restart = "always";
        RestartSec = "30s";
      };
      
      script = ''
        # Monitor Portainer logs for audit events
        ${pkgs.podman}/bin/podman logs -f portainer 2>&1 | \
        while IFS= read -r line; do
          # Log security-relevant events
          if echo "$line" | grep -E "(login|logout|container|image|volume|network)"; then
            echo "[PORTAINER-AUDIT] $(date): $line" >> /var/log/portainer/audit.log
          fi
        done
      '';
    };
    
    # Persistence configuration
    environment.persistence."/nix/persist" = mkIf config.environment.persistence."/nix/persist".enable {
      directories = [
        cfg.dataDir
        "/var/log/portainer"
      ];
    };
    
    # Log rotation for audit logs
    services.logrotate.settings.portainer = mkIf cfg.enableAuditLog {
      files = "/var/log/portainer/*.log";
      frequency = "weekly";
      rotate = 4;
      compress = true;
      delaycompress = true;
      missingok = true;
      notifempty = true;
      create = "644 root root";
    };
    
    # Container runtime socket systemd service enhancement
    systemd.services.${cfg.containerRuntime} = {
      serviceConfig = {
        # Ensure socket is accessible to Portainer
        ExecStartPost = pkgs.writeShellScript "setup-portainer-socket-access" ''
          # Wait for socket to be created
          for i in {1..10}; do
            if [ -S "${cfg.socketPath}" ]; then
              break
            fi
            sleep 1
          done
          
          # Set appropriate permissions
          if [ -S "${cfg.socketPath}" ]; then
            chmod 660 "${cfg.socketPath}"
            chgrp ${cfg.containerRuntime} "${cfg.socketPath}"
            echo "Container runtime socket prepared for Portainer access"
          fi
        '';
      };
    };
    
    # Assertions to ensure proper configuration
    assertions = [
      {
        assertion = cfg.port != cfg.sslPort && cfg.port != cfg.edgePort && cfg.sslPort != cfg.edgePort;
        message = "Portainer ports must all be different";
      }
      {
        assertion = cfg.dataDir != "";
        message = "Portainer data directory must be specified";
      }
      {
        assertion = config.services.dagger.enable;
        message = "Dagger service must be enabled for Dagger-managed Portainer";
      }
      {
        assertion = config.virtualisation.${cfg.containerRuntime}.enable;
        message = "Container runtime (${cfg.containerRuntime}) must be enabled for Portainer";
      }
      {
        assertion = pathExists cfg.socketPath || !cfg.enable;
        message = "Container runtime socket path ${cfg.socketPath} must exist";
      }
    ];
    
    # Warnings for security considerations
    warnings = 
      (optional (!cfg.requireAuthentication) 
        "Portainer authentication is disabled - this is a security risk") ++
      (optional (!cfg.enableSSL)
        "Portainer SSL is disabled - consider enabling for production use") ++
      (optional (elem "0.0.0.0/0" cfg.allowedNetworks)
        "Portainer is accessible from all networks - consider restricting access") ++
      (optional (!cfg.enableAuditLog)
        "Portainer audit logging is disabled - enable for compliance and security monitoring");
  };
}