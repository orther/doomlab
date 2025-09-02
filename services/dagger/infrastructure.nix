# Dagger Infrastructure Services Integration
# Comprehensive module that integrates Pi-hole, Portainer, and Unpackerr
# Provides unified configuration and service orchestration

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
    ./pihole.nix
    ./portainer.nix
    ./unpackerr.nix
    ./nixarr.nix
    ./homebridge.nix
    ./migration.nix
    ./integration.nix
  ];

  options.services.dagger.infrastructure = {
    enable = mkEnableOption "Complete Dagger infrastructure services integration";
    
    enableAllServices = mkOption {
      type = types.bool;
      default = false;
      description = "Enable all infrastructure services (Pi-hole, Portainer, Unpackerr)";
    };
    
    profile = mkOption {
      type = types.enum [ "minimal" "homelab" "production" "development" ];
      default = "homelab";
      description = ''
        Service profile to use:
        - minimal: Core services only
        - homelab: Standard homelab setup  
        - production: Full production features
        - development: All services with debug features
      '';
    };
    
    networkSegmentation = mkOption {
      type = types.bool;
      default = true;
      description = "Enable network segmentation between service types";
    };
    
    sharedStorage = mkOption {
      type = types.bool;
      default = true;
      description = "Enable shared storage configuration between services";
    };
    
    centralizedLogging = mkOption {
      type = types.bool;
      default = true;
      description = "Enable centralized logging for all infrastructure services";
    };
    
    serviceDiscovery = mkOption {
      type = types.bool;
      default = true;
      description = "Enable service discovery and health monitoring";
    };
    
    autoScaling = mkOption {
      type = types.bool;
      default = false;
      description = "Enable automatic scaling based on resource usage";
    };
    
    disaster_recovery = mkOption {
      type = types.bool;
      default = true;
      description = "Enable disaster recovery and backup coordination";
    };
  };

  config = mkIf config.services.dagger.infrastructure.enable {
    # Profile-based service enablement
    services.dagger = {
      # Always enable base services
      enable = true;
      enableBackupIntegration = config.services.dagger.infrastructure.disaster_recovery;
      enableMonitoring = true;
      
      # Profile-specific configurations
      pihole = mkIf (config.services.dagger.infrastructure.profile != "minimal") {
        enable = mkDefault true;
        enableMonitoring = true;
        enableBackup = config.services.dagger.infrastructure.disaster_recovery;
        
        # Production optimizations
        dns.upstream = mkIf (config.services.dagger.infrastructure.profile == "production") 
          [ "1.1.1.1" "1.0.0.1" "9.9.9.9" "149.112.112.112" ];
      };
      
      portainer = mkIf (config.services.dagger.infrastructure.profile != "minimal") {
        enable = mkDefault true;
        enableMonitoring = true;
        enableBackup = config.services.dagger.infrastructure.disaster_recovery;
        enableAuditLog = mkIf (config.services.dagger.infrastructure.profile == "production") true;
        
        # Development features
        enableEdgeAgent = mkIf (config.services.dagger.infrastructure.profile == "development") true;
      };
      
      unpackerr = mkIf (config.services.dagger.infrastructure.enableAllServices || 
                       config.services.dagger.infrastructure.profile == "homelab" ||
                       config.services.dagger.infrastructure.profile == "production") {
        enable = mkDefault true;
        enableMonitoring = true;
        enableBackup = config.services.dagger.infrastructure.disaster_recovery;
        
        # Auto-enable integrations if nixarr is available
        sonarr.enable = mkDefault (config.services.dagger.nixarr.sonarr.enable or false);
        radarr.enable = mkDefault (config.services.dagger.nixarr.radarr.enable or false);
        
        # Development features
        enableMetrics = mkIf (config.services.dagger.infrastructure.profile == "development") true;
      };
    };
    
    # Shared storage configuration
    systemd.tmpfiles.rules = mkIf config.services.dagger.infrastructure.sharedStorage [
      # Central shared directories
      "d /var/lib/dagger-shared 0755 root root -"
      "d /var/lib/dagger-shared/config 0755 root root -"
      "d /var/lib/dagger-shared/data 0755 root root -"
      "d /var/lib/dagger-shared/logs 0755 root root -"
      "d /var/lib/dagger-shared/backups 0755 root root -"
      
      # Shared configuration templates
      "d /etc/dagger-shared 0755 root root -"
      "d /etc/dagger-shared/templates 0755 root root -"
    ];
    
    # Centralized logging configuration
    services.journald = mkIf config.services.dagger.infrastructure.centralizedLogging {
      extraConfig = ''
        # Enhanced logging for Dagger services
        SystemMaxUse=1G
        SystemMaxFileSize=100M
        SystemMaxFiles=10
        
        # Persistent storage
        Storage=persistent
        
        # Rate limiting
        RateLimitInterval=30s
        RateLimitBurst=10000
      '';
    };
    
    # Service discovery and health monitoring
    systemd.services.dagger-infrastructure-monitor = mkIf config.services.dagger.infrastructure.serviceDiscovery {
      description = "Dagger Infrastructure Service Discovery and Health Monitor";
      wantedBy = [ "multi-user.target" ];
      after = [ "dagger-coordinator.service" ];
      
      serviceConfig = {
        Type = "simple";
        User = "root";
        Group = "root";
        Restart = "always";
        RestartSec = "30s";
      };
      
      script = ''
        #!/bin/bash
        
        # Service registry
        declare -A services
        services[pihole]="127.0.0.1:${toString config.services.dagger.pihole.webPort}"
        services[portainer]="127.0.0.1:${toString config.services.dagger.portainer.port}"
        ${optionalString config.services.dagger.unpackerr.webui.enable ''
        services[unpackerr]="127.0.0.1:${toString config.services.dagger.unpackerr.webui.port}"
        ''}
        
        # Service discovery loop
        while true; do
          echo "$(date): Running infrastructure service discovery..."
          
          # Update service registry
          service_registry="/var/lib/dagger-shared/service-registry.json"
          echo "{" > "$service_registry.tmp"
          echo '  "timestamp": "'$(date -Iseconds)'",' >> "$service_registry.tmp"
          echo '  "services": {' >> "$service_registry.tmp"
          
          first=true
          for service in "''${!services[@]}"; do
            endpoint="''${services[$service]}"
            
            # Test service health
            if curl -f -s --connect-timeout 5 "http://$endpoint" > /dev/null 2>&1; then
              status="healthy"
              echo "✓ $service ($endpoint) is healthy"
            else
              status="unhealthy"
              echo "✗ $service ($endpoint) is unhealthy"
            fi
            
            # Add to registry
            if [ "$first" = true ]; then
              first=false
            else
              echo "," >> "$service_registry.tmp"
            fi
            
            echo "    \"$service\": {" >> "$service_registry.tmp"
            echo "      \"endpoint\": \"$endpoint\"," >> "$service_registry.tmp"
            echo "      \"status\": \"$status\"," >> "$service_registry.tmp"
            echo "      \"last_check\": \"$(date -Iseconds)\"" >> "$service_registry.tmp"
            echo -n "    }" >> "$service_registry.tmp"
          done
          
          echo "" >> "$service_registry.tmp"
          echo "  }" >> "$service_registry.tmp"
          echo "}" >> "$service_registry.tmp"
          
          # Atomically update registry
          mv "$service_registry.tmp" "$service_registry"
          chmod 644 "$service_registry"
          
          # Wait before next check
          sleep 60
        done
      '';
    };
    
    # Network segmentation using iptables
    networking.firewall.extraCommands = mkIf config.services.dagger.infrastructure.networkSegmentation ''
      # Infrastructure services network rules
      
      # Create custom chains for infrastructure services
      iptables -N dagger-infra-in 2>/dev/null || true
      iptables -N dagger-infra-forward 2>/dev/null || true
      
      # Allow infrastructure services to communicate with each other
      iptables -A dagger-infra-in -s 127.0.0.1 -j ACCEPT
      iptables -A dagger-infra-in -s 10.0.10.0/24 -j ACCEPT  # Local network
      iptables -A dagger-infra-in -s 100.64.0.0/10 -j ACCEPT # Tailscale
      
      # Pi-hole specific rules (if enabled)
      ${optionalString config.services.dagger.pihole.enable ''
      iptables -A dagger-infra-in -p udp --dport 53 -j ACCEPT
      iptables -A dagger-infra-in -p tcp --dport 53 -j ACCEPT
      ''}
      
      # Portainer specific rules (if enabled)  
      ${optionalString config.services.dagger.portainer.enable ''
      iptables -A dagger-infra-in -p tcp --dport ${toString config.services.dagger.portainer.port} -s 10.0.10.0/24 -j ACCEPT
      ''}
      
      # Insert rules into main chains
      iptables -I nixos-fw -j dagger-infra-in
    '';
    
    networking.firewall.extraStopCommands = mkIf config.services.dagger.infrastructure.networkSegmentation ''
      # Clean up custom chains
      iptables -D nixos-fw -j dagger-infra-in 2>/dev/null || true
      iptables -F dagger-infra-in 2>/dev/null || true
      iptables -F dagger-infra-forward 2>/dev/null || true
      iptables -X dagger-infra-in 2>/dev/null || true
      iptables -X dagger-infra-forward 2>/dev/null || true
    '';
    
    # Disaster recovery coordination
    systemd.services.dagger-infrastructure-backup-coordinator = mkIf config.services.dagger.infrastructure.disaster_recovery {
      description = "Dagger Infrastructure Backup Coordinator";
      
      serviceConfig = {
        Type = "oneshot";
        User = "root";
        Group = "root";
      };
      
      script = ''
        #!/bin/bash
        set -euo pipefail
        
        echo "Starting infrastructure backup coordination..."
        
        # Create backup manifest
        backup_manifest="/var/lib/dagger-shared/backups/infrastructure-backup-$(date +%Y%m%d-%H%M%S).json"
        mkdir -p "$(dirname "$backup_manifest")"
        
        echo "{" > "$backup_manifest"
        echo '  "timestamp": "'$(date -Iseconds)'",' >> "$backup_manifest"
        echo '  "services": [' >> "$backup_manifest"
        
        backup_services=()
        
        # Coordinate service-specific backups
        ${optionalString config.services.dagger.pihole.enable ''
        if systemctl is-active --quiet dagger-backup-pihole.service; then
          echo "    \"pihole\"," >> "$backup_manifest"
          backup_services+=("pihole")
        fi
        ''}
        
        ${optionalString config.services.dagger.portainer.enable ''
        if systemctl is-active --quiet dagger-backup-portainer.service; then
          echo "    \"portainer\"," >> "$backup_manifest"
          backup_services+=("portainer") 
        fi
        ''}
        
        ${optionalString config.services.dagger.unpackerr.enable ''
        if systemctl is-active --quiet dagger-backup-unpackerr.service; then
          echo "    \"unpackerr\"," >> "$backup_manifest"
          backup_services+=("unpackerr")
        fi
        ''}
        
        # Remove trailing comma and close
        sed -i '$ s/,$//' "$backup_manifest"
        echo "  ]," >> "$backup_manifest"
        echo '  "status": "completed"' >> "$backup_manifest"
        echo "}" >> "$backup_manifest"
        
        echo "Infrastructure backup coordination completed: ''${#backup_services[@]} services"
      '';
    };
    
    # Backup coordination timer
    systemd.timers.dagger-infrastructure-backup-coordinator = mkIf config.services.dagger.infrastructure.disaster_recovery {
      description = "Infrastructure Backup Coordination Timer";
      wantedBy = [ "timers.target" ];
      
      timerConfig = {
        OnCalendar = "*-*-* 5:00:00";
        RandomizedDelaySec = "30m";
        Persistent = true;
      };
    };
    
    # Auto-scaling service (basic implementation)
    systemd.services.dagger-infrastructure-autoscaler = mkIf config.services.dagger.infrastructure.autoScaling {
      description = "Dagger Infrastructure Auto-scaler";
      after = [ "dagger-infrastructure-monitor.service" ];
      
      serviceConfig = {
        Type = "simple";
        User = "root";
        Group = "root";
        Restart = "always";
        RestartSec = "60s";
      };
      
      script = ''
        #!/bin/bash
        
        while true; do
          echo "$(date): Checking infrastructure resource usage..."
          
          # Get system resources
          cpu_usage=$(top -bn1 | grep "Cpu(s)" | sed "s/.*, *\([0-9.]*\)%* id.*/\1/" | awk '{print 100 - $1}')
          memory_usage=$(free | grep Mem | awk '{printf("%.1f", $3/$2 * 100.0)}')
          
          echo "CPU: $cpu_usage%, Memory: $memory_usage%"
          
          # Basic scaling decisions (placeholder for more sophisticated logic)
          if (( $(echo "$cpu_usage > 80" | bc -l) )); then
            echo "High CPU usage detected, could scale services..."
            # Placeholder for scaling logic
          fi
          
          if (( $(echo "$memory_usage > 85" | bc -l) )); then
            echo "High memory usage detected, could optimize services..."
            # Placeholder for optimization logic
          fi
          
          sleep 300  # Check every 5 minutes
        done
      '';
    };
    
    # Central configuration management
    environment.etc = mkMerge [
      {
        "dagger-infrastructure/config.yaml" = {
          text = ''
            # Dagger Infrastructure Configuration
            # Auto-generated by NixOS
            
            profile: "${config.services.dagger.infrastructure.profile}"
            network_segmentation: ${boolToString config.services.dagger.infrastructure.networkSegmentation}
            shared_storage: ${boolToString config.services.dagger.infrastructure.sharedStorage}
            centralized_logging: ${boolToString config.services.dagger.infrastructure.centralizedLogging}
            service_discovery: ${boolToString config.services.dagger.infrastructure.serviceDiscovery}
            auto_scaling: ${boolToString config.services.dagger.infrastructure.autoScaling}
            disaster_recovery: ${boolToString config.services.dagger.infrastructure.disaster_recovery}
            
            services:
              pihole:
                enabled: ${boolToString config.services.dagger.pihole.enable}
                ${optionalString config.services.dagger.pihole.enable ''
                web_port: ${toString config.services.dagger.pihole.webPort}
                dns_port: ${toString config.services.dagger.pihole.dnsPort}
                ''}
              
              portainer:
                enabled: ${boolToString config.services.dagger.portainer.enable}
                ${optionalString config.services.dagger.portainer.enable ''
                web_port: ${toString config.services.dagger.portainer.port}
                container_runtime: "${config.services.dagger.portainer.containerRuntime}"
                ''}
              
              unpackerr:
                enabled: ${boolToString config.services.dagger.unpackerr.enable}
                ${optionalString config.services.dagger.unpackerr.enable ''
                web_port: ${toString config.services.dagger.unpackerr.webui.port}
                parallel_jobs: ${toString config.services.dagger.unpackerr.extraction.parallelJobs}
                ''}
            
            monitoring:
              service_registry: "/var/lib/dagger-shared/service-registry.json"
              log_directory: "/var/lib/dagger-shared/logs"
              backup_directory: "/var/lib/dagger-shared/backups"
          '';
          mode = "0644";
        };
      }
      
      # Service integration templates
      {
        "dagger-shared/templates/docker-compose.yml" = {
          text = ''
            # Template Docker Compose for Dagger services
            # This can be used for testing or alternative deployments
            
            version: '3.8'
            
            services:
              ${optionalString config.services.dagger.pihole.enable ''
              pihole:
                image: ${config.services.dagger.pihole.image}
                container_name: pihole-dagger
                ports:
                  - "${toString config.services.dagger.pihole.webPort}:80"
                  - "${toString config.services.dagger.pihole.dnsPort}:53/tcp"
                  - "${toString config.services.dagger.pihole.dnsPort}:53/udp"
                volumes:
                  - ${config.services.dagger.pihole.dataDir}:/etc/pihole
                  - ${config.services.dagger.pihole.dnsmasqDir}:/etc/dnsmasq.d
                restart: unless-stopped
              ''}
              
              ${optionalString config.services.dagger.portainer.enable ''
              portainer:
                image: ${config.services.dagger.portainer.image}
                container_name: portainer-dagger
                ports:
                  - "${toString config.services.dagger.portainer.port}:9000"
                volumes:
                  - ${config.services.dagger.portainer.dataDir}:/data
                  - ${config.services.dagger.portainer.socketPath}:/var/run/docker.sock
                restart: unless-stopped
              ''}
              
              ${optionalString config.services.dagger.unpackerr.enable ''
              unpackerr:
                image: ${config.services.dagger.unpackerr.image}
                container_name: unpackerr-dagger
                ports:
                  - "${toString config.services.dagger.unpackerr.webui.port}:5656"
                volumes:
                  - ${config.services.dagger.unpackerr.dataDir}:/config
                  - ${config.services.dagger.unpackerr.extraction.extractPath}:/downloads
                restart: unless-stopped
              ''}
          '';
          mode = "0644";
        };
      }
    ];
    
    # Utility commands for infrastructure management
    environment.systemPackages = [
      # Infrastructure status command
      (pkgs.writeShellScriptBin "dagger-infra-status" ''
        #!/bin/bash
        echo "=== Dagger Infrastructure Status ==="
        echo "Profile: ${config.services.dagger.infrastructure.profile}"
        echo ""
        
        # Service status
        echo "=== Service Status ==="
        services=(
          ${optionalString config.services.dagger.pihole.enable '"pihole:dagger-infrastructure-pihole"'}
          ${optionalString config.services.dagger.portainer.enable '"portainer:dagger-infrastructure-portainer"'}
          ${optionalString config.services.dagger.unpackerr.enable '"unpackerr:dagger-automation-unpackerr"'}
        )
        
        for service_info in "''${services[@]}"; do
          IFS=':' read -r name service <<< "$service_info"
          status=$(systemctl is-active "$service.service" 2>/dev/null || echo "inactive")
          if [ "$status" = "active" ]; then
            echo "✓ $name: $status"
          else
            echo "✗ $name: $status"
          fi
        done
        
        echo ""
        echo "=== Service Discovery ==="
        if [ -f /var/lib/dagger-shared/service-registry.json ]; then
          ${pkgs.jq}/bin/jq -r '.services | to_entries[] | "\(.key): \(.value.status) (\(.value.endpoint))"' /var/lib/dagger-shared/service-registry.json
        else
          echo "Service registry not available"
        fi
        
        echo ""
        echo "=== Resource Usage ==="
        echo "CPU: $(top -bn1 | grep "Cpu(s)" | sed "s/.*, *\([0-9.]*\)%* id.*/\1/" | awk '{print 100 - $1}')%"
        echo "Memory: $(free | grep Mem | awk '{printf("%.1f", $3/$2 * 100.0)}')%"
        echo "Disk (shared): $(df -h /var/lib/dagger-shared | tail -1 | awk '{print $5}') used"
        
        echo ""
        echo "=== Quick Commands ==="
        echo "  dagger-infra-restart  - Restart all infrastructure services"
        echo "  dagger-infra-backup   - Trigger infrastructure backup"
        echo "  dagger-infra-logs     - View infrastructure service logs"
      '')
      
      # Infrastructure restart command
      (pkgs.writeShellScriptBin "dagger-infra-restart" ''
        #!/bin/bash
        echo "Restarting Dagger infrastructure services..."
        
        services=(
          ${optionalString config.services.dagger.pihole.enable '"dagger-infrastructure-pihole"'}
          ${optionalString config.services.dagger.portainer.enable '"dagger-infrastructure-portainer"'}
          ${optionalString config.services.dagger.unpackerr.enable '"dagger-automation-unpackerr"'}
        )
        
        for service in "''${services[@]}"; do
          echo "Restarting $service..."
          systemctl restart "$service.service"
        done
        
        echo "Infrastructure restart completed"
      '')
      
      # Infrastructure backup command
      (pkgs.writeShellScriptBin "dagger-infra-backup" ''
        #!/bin/bash
        echo "Triggering infrastructure backup..."
        systemctl start dagger-infrastructure-backup-coordinator.service
        echo "Backup initiated - check systemctl status dagger-infrastructure-backup-coordinator for progress"
      '')
      
      # Infrastructure logs command
      (pkgs.writeShellScriptBin "dagger-infra-logs" ''
        #!/bin/bash
        echo "=== Dagger Infrastructure Logs ==="
        journalctl -u "dagger-*" --since "1 hour ago" --no-pager -n 50
      '')
    ];
    
    # Persistence configuration for shared infrastructure
    environment.persistence."/nix/persist" = mkIf config.environment.persistence."/nix/persist".enable {
      directories = [
        "/var/lib/dagger-shared"
      ];
    };
    
    # Assertions for proper infrastructure configuration
    assertions = [
      {
        assertion = config.services.dagger.enable;
        message = "Base Dagger service must be enabled for infrastructure services";
      }
      {
        assertion = !(config.services.dagger.infrastructure.autoScaling && config.services.dagger.infrastructure.profile == "minimal");
        message = "Auto-scaling is not compatible with minimal profile";
      }
      {
        assertion = config.services.dagger.infrastructure.disaster_recovery -> config.services.dagger.enableBackupIntegration;
        message = "Disaster recovery requires backup integration to be enabled";
      }
    ];
    
    # Warnings for infrastructure considerations
    warnings = 
      (optional (config.services.dagger.infrastructure.profile == "development" && !config.services.dagger.infrastructure.centralizedLogging)
        "Development profile works best with centralized logging enabled") ++
      (optional (config.services.dagger.infrastructure.autoScaling && config.services.dagger.infrastructure.profile != "production")
        "Auto-scaling is experimental and should be tested thoroughly before production use") ++
      (optional (!config.services.dagger.infrastructure.networkSegmentation && config.services.dagger.infrastructure.profile == "production")
        "Production profile should use network segmentation for security");
  };
}