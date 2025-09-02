{
  config,
  pkgs,
  lib,
  ...
}:

with lib;

{
  options.services.resource-limits = {
    enable = mkEnableOption "Service resource limits and monitoring";
    
    defaultMemoryLimit = mkOption {
      type = types.str;
      default = "2G";
      description = "Default memory limit for services";
    };
    
    defaultCpuQuota = mkOption {
      type = types.str;
      default = "50%";
      description = "Default CPU quota for services";
    };
    
    enableSystemMonitoring = mkOption {
      type = types.bool;
      default = true;
      description = "Enable system resource monitoring";
    };
  };

  config = mkIf config.services.resource-limits.enable {
    # Apply resource limits to critical services
    systemd.services = {
      # Docker containers resource limits
      docker = mkIf config.virtualisation.docker.enable {
        serviceConfig = {
          MemoryMax = "4G";
          CPUQuota = "200%"; # Allow up to 2 cores
          TasksMax = 8192;
          
          # Security hardening
          PrivateTmp = true;
          ProtectSystem = "strict";
          ReadWritePaths = [
            "/var/lib/docker"
            "/var/run/docker"
          ];
          
          # Resource accounting
          MemoryAccounting = true;
          CPUAccounting = true;
          TasksAccounting = true;
        };
      };

      # Nginx resource limits
      nginx = mkIf config.services.nginx.enable {
        serviceConfig = {
          MemoryMax = config.services.resource-limits.defaultMemoryLimit;
          CPUQuota = config.services.resource-limits.defaultCpuQuota;
          
          # Connection limits
          LimitNOFILE = 65536;
          
          # Security hardening
          PrivateTmp = true;
          ProtectSystem = "strict";
          ProtectHome = true;
          ReadWritePaths = [
            "/var/log/nginx"
            "/var/cache/nginx"
            "/run/nginx"
          ];
          
          # Resource accounting
          MemoryAccounting = true;
          CPUAccounting = true;
        };
      };

      # Tailscale resource limits
      tailscaled = mkIf config.services.tailscale.enable {
        serviceConfig = {
          MemoryMax = "512M";
          CPUQuota = "25%";
          
          # Security hardening
          PrivateTmp = true;
          ProtectSystem = "strict";
          ProtectHome = true;
          ReadWritePaths = [
            "/var/lib/tailscale"
          ];
          
          # Resource accounting
          MemoryAccounting = true;
          CPUAccounting = true;
        };
      };

      # SSH daemon resource limits
      sshd = {
        serviceConfig = {
          MemoryMax = "1G";
          CPUQuota = "50%";
          
          # Connection limits
          LimitNOFILE = 4096;
          
          # Resource accounting
          MemoryAccounting = true;
          CPUAccounting = true;
        };
      };

    };

    # System-wide resource monitoring and limits
    systemd.extraConfig = ''
      # Global defaults for user services
      DefaultMemoryAccounting=yes
      DefaultCPUAccounting=yes
      DefaultTasksAccounting=yes
      DefaultIOAccounting=yes
      
      # System-wide limits
      DefaultTasksMax=65536
      DefaultLimitNOFILE=65536
    '';

    # Enable systemd resource monitoring tools
    environment.systemPackages = with pkgs; [
      systemd  # systemd-cgtop, systemctl show, etc.
      htop     # Enhanced top with better resource display
      iotop    # I/O monitoring
      nethogs  # Network usage per process
    ];

    # Optional: Basic system monitoring service
    systemd.services.system-monitor = mkIf config.services.resource-limits.enableSystemMonitoring {
      description = "System resource monitoring";
      serviceConfig = {
        Type = "oneshot";
        ExecStart = pkgs.writeScript "system-monitor" ''
          #!/bin/sh
          # Log system resource usage
          LOG_FILE="/var/log/system-resources.log"
          DATE=$(date -Iseconds)
          
          # Memory usage
          MEM_USAGE=$(free -h | grep Mem | awk '{print "Used: " $3 "/" $2 " (" $3/$2*100 "%)"}')
          
          # CPU load
          CPU_LOAD=$(uptime | awk -F'load average:' '{print $2}')
          
          # Disk usage
          DISK_USAGE=$(df -h / | tail -n1 | awk '{print "Root: " $3 "/" $2 " (" $5 ")"}')
          
          # Top memory consumers
          TOP_MEM=$(ps aux --sort=-%mem | head -6 | tail -n +2 | awk '{print $11 " " $4"%"}')
          
          # Log everything
          {
            echo "[$DATE] System Resources:"
            echo "  Memory: $MEM_USAGE"
            echo "  CPU Load: $CPU_LOAD"
            echo "  Disk: $DISK_USAGE"
            echo "  Top Memory Users:"
            echo "$TOP_MEM" | sed 's/^/    /'
            echo ""
          } >> "$LOG_FILE"
          
          # Rotate log if it gets too large (>10MB)
          if [ -f "$LOG_FILE" ] && [ $(stat -c%s "$LOG_FILE") -gt 10485760 ]; then
            mv "$LOG_FILE" "$LOG_FILE.old"
            echo "[$DATE] Log rotated" > "$LOG_FILE"
          fi
        '';
        
        # Run with minimal privileges
        User = "nobody";
        Group = "nogroup";
        PrivateTmp = true;
        ProtectSystem = "strict";
        ProtectHome = true;
        ReadWritePaths = [ "/var/log" ];
        
        # Resource limits for the monitor itself
        MemoryMax = "64M";
        CPUQuota = "10%";
      };
    };

    # Timer for system monitoring
    systemd.timers.system-monitor = mkIf config.services.resource-limits.enableSystemMonitoring {
      description = "System resource monitoring timer";
      wantedBy = [ "timers.target" ];
      timerConfig = {
        OnCalendar = "*:0/15"; # Every 15 minutes
        Persistent = true;
      };
    };

    # Create log directory and files
    systemd.tmpfiles.rules = [
      "d /var/log 0755 root root -"
      "f /var/log/system-resources.log 0644 nobody nogroup -"
    ];

    # Persist monitoring logs
    environment.persistence."/nix/persist" = mkIf (config ? environment.persistence) {
      files = [
        "/var/log/system-resources.log"
        "/var/log/system-resources.log.old"
      ];
    };
  };
}