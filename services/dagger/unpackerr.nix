# Dagger-managed Unpackerr Service
# Automated archive extraction for media downloads
# Integrates with nixarr services (Sonarr, Radarr) and supports complex environment configurations

{ config, lib, pkgs, ... }:

with lib;

let
  cfg = config.services.dagger.unpackerr;
  nixarrCfg = config.services.dagger.nixarr;
  
  # Helper function to generate service API configurations
  mkServiceConfig = service: serviceConfig: {
    url = "http://127.0.0.1:${toString serviceConfig.port}";
    api_key = "/run/dagger-secrets/${service}/api-key";
    paths = serviceConfig.paths or [];
    protocols = serviceConfig.protocols or ["torrent"];
    timeout = serviceConfig.timeout or "10s";
    delete_delay = serviceConfig.deleteDelay or "5m";
    delete_orig = serviceConfig.deleteOriginal or false;
    syncthing = serviceConfig.syncthing or false;
  };
  
in {
  options.services.dagger.unpackerr = {
    enable = mkEnableOption "Dagger-managed Unpackerr archive extraction service";
    
    image = mkOption {
      type = types.str;
      default = "golift/unpackerr:latest";
      description = "Container image to use for Unpackerr";
    };
    
    dataDir = mkOption {
      type = types.path;
      default = "/var/lib/unpackerr";
      description = "Directory for Unpackerr data and logs";
    };
    
    # Core extraction settings
    extraction = {
      parallelJobs = mkOption {
        type = types.int;
        default = 2;
        description = "Maximum number of parallel extraction jobs";
      };
      
      deleteAfter = mkOption {
        type = types.str;
        default = "10m";
        description = "How long to wait before deleting extracted archives";
      };
      
      deleteOriginal = mkOption {
        type = types.bool;
        default = true;
        description = "Delete original archive files after successful extraction";
      };
      
      extractPath = mkOption {
        type = types.path;
        default = "${nixarrCfg.storage.mediaRoot}/downloads";
        description = "Base path for extraction operations";
      };
      
      fileMode = mkOption {
        type = types.str;
        default = "0644";
        description = "File permissions for extracted files";
      };
      
      dirMode = mkOption {
        type = types.str;
        default = "0755";
        description = "Directory permissions for extracted folders";
      };
    };
    
    # Archive format support
    formats = {
      enableRar = mkOption {
        type = types.bool;
        default = true;
        description = "Enable RAR archive extraction";
      };
      
      enableZip = mkOption {
        type = types.bool;
        default = true;
        description = "Enable ZIP archive extraction";
      };
      
      enable7zip = mkOption {
        type = types.bool;
        default = true;
        description = "Enable 7-Zip archive extraction";
      };
      
      enableTar = mkOption {
        type = types.bool;
        default = true;
        description = "Enable TAR archive extraction (including gz, bz2, xz)";
      };
      
      enableIso = mkOption {
        type = types.bool;
        default = false;
        description = "Enable ISO image mounting and extraction";
      };
      
      passwordFile = mkOption {
        type = types.nullOr types.path;
        default = null;
        description = "File containing passwords for encrypted archives (one per line)";
      };
    };
    
    # Nixarr service integrations
    sonarr = {
      enable = mkOption {
        type = types.bool;
        default = nixarrCfg.sonarr.enable or false;
        description = "Enable Sonarr integration";
      };
      
      port = mkOption {
        type = types.port;
        default = nixarrCfg.sonarr.port or 8989;
        description = "Sonarr API port";
      };
      
      paths = mkOption {
        type = types.listOf types.str;
        default = [ "/downloads/tv" "/downloads/complete/tv" ];
        description = "Paths to monitor for Sonarr downloads";
      };
      
      protocols = mkOption {
        type = types.listOf types.str;
        default = [ "torrent" "usenet" ];
        description = "Download protocols to monitor";
      };
      
      timeout = mkOption {
        type = types.str;
        default = "30s";
        description = "API timeout for Sonarr requests";
      };
      
      deleteDelay = mkOption {
        type = types.str;
        default = "5m";
        description = "Delay before deleting archives after Sonarr import";
      };
      
      deleteOriginal = mkOption {
        type = types.bool;
        default = true;
        description = "Delete original archives after Sonarr import";
      };
      
      syncthing = mkOption {
        type = types.bool;
        default = false;
        description = "Enable Syncthing integration for Sonarr";
      };
    };
    
    radarr = {
      enable = mkOption {
        type = types.bool;
        default = nixarrCfg.radarr.enable or false;
        description = "Enable Radarr integration";
      };
      
      port = mkOption {
        type = types.port;
        default = nixarrCfg.radarr.port or 7878;
        description = "Radarr API port";
      };
      
      paths = mkOption {
        type = types.listOf types.str;
        default = [ "/downloads/movies" "/downloads/complete/movies" ];
        description = "Paths to monitor for Radarr downloads";
      };
      
      protocols = mkOption {
        type = types.listOf types.str;
        default = [ "torrent" "usenet" ];
        description = "Download protocols to monitor";
      };
      
      timeout = mkOption {
        type = types.str;
        default = "30s";
        description = "API timeout for Radarr requests";
      };
      
      deleteDelay = mkOption {
        type = types.str;
        default = "5m";
        description = "Delay before deleting archives after Radarr import";
      };
      
      deleteOriginal = mkOption {
        type = types.bool;
        default = true;
        description = "Delete original archives after Radarr import";
      };
      
      syncthing = mkOption {
        type = types.bool;
        default = false;
        description = "Enable Syncthing integration for Radarr";
      };
    };
    
    # Folder monitoring
    folders = mkOption {
      type = types.listOf (types.submodule {
        options = {
          path = mkOption {
            type = types.str;
            description = "Path to monitor for archives";
          };
          
          extractPath = mkOption {
            type = types.nullOr types.str;
            default = null;
            description = "Custom extraction path (uses global if null)";
          };
          
          deleteAfter = mkOption {
            type = types.str;
            default = cfg.extraction.deleteAfter;
            description = "Delete delay for this folder";
          };
          
          deleteOriginal = mkOption {
            type = types.bool;
            default = cfg.extraction.deleteOriginal;
            description = "Delete original files for this folder";
          };
          
          moveBack = mkOption {
            type = types.bool;
            default = false;
            description = "Move extracted files back to original location";
          };
        };
      });
      default = [
        {
          path = "${cfg.extraction.extractPath}";
          deleteAfter = "10m";
          deleteOriginal = true;
          moveBack = false;
        }
      ];
      description = "Additional folders to monitor for archives";
    };
    
    # Logging and monitoring
    logging = {
      level = mkOption {
        type = types.enum [ "ERROR" "WARN" "INFO" "DEBUG" ];
        default = "INFO";
        description = "Log level for Unpackerr";
      };
      
      logFile = mkOption {
        type = types.str;
        default = "${cfg.dataDir}/unpackerr.log";
        description = "Path to Unpackerr log file";
      };
      
      maxSize = mkOption {
        type = types.str;
        default = "10MB";
        description = "Maximum log file size before rotation";
      };
      
      maxBackups = mkOption {
        type = types.int;
        default = 3;
        description = "Number of rotated log files to keep";
      };
      
      enableSyslog = mkOption {
        type = types.bool;
        default = true;
        description = "Send logs to syslog/journald";
      };
    };
    
    # Web interface
    webui = {
      enable = mkOption {
        type = types.bool;
        default = true;
        description = "Enable Unpackerr web interface";
      };
      
      port = mkOption {
        type = types.port;
        default = 5656;
        description = "Port for Unpackerr web interface";
      };
      
      enableAuth = mkOption {
        type = types.bool;
        default = true;
        description = "Enable authentication for web interface";
      };
      
      username = mkOption {
        type = types.str;
        default = "admin";
        description = "Username for web interface authentication";
      };
      
      urlBase = mkOption {
        type = types.str;
        default = "/";
        description = "URL base for reverse proxy setups";
      };
    };
    
    # Notification settings
    webhooks = mkOption {
      type = types.listOf (types.submodule {
        options = {
          name = mkOption {
            type = types.str;
            description = "Webhook name/identifier";
          };
          
          url = mkOption {
            type = types.str;
            description = "Webhook URL to send notifications to";
          };
          
          events = mkOption {
            type = types.listOf (types.enum [ "extract" "delete" "error" "stuck" ]);
            default = [ "extract" "error" ];
            description = "Events that trigger this webhook";
          };
          
          timeout = mkOption {
            type = types.str;
            default = "10s";
            description = "Timeout for webhook requests";
          };
          
          silent = mkOption {
            type = types.bool;
            default = false;
            description = "Don't log webhook errors";
          };
        };
      });
      default = [];
      description = "Webhook notifications configuration";
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
      description = "Enable health monitoring and metrics";
    };
    
    enableMetrics = mkOption {
      type = types.bool;
      default = false;
      description = "Enable Prometheus metrics endpoint";
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
      services = [ "automation.unpackerr" ];
      enableBackupIntegration = cfg.enableBackup;
      enableMonitoring = cfg.enableMonitoring;
    };
    
    # Ensure SOPS secrets are available for service integrations
    services.dagger.secrets.enable = mkIf (cfg.sonarr.enable || cfg.radarr.enable) true;
    
    # Create directories
    systemd.tmpfiles.rules = [
      "d ${cfg.dataDir} 0755 root root"
      "d ${cfg.extraction.extractPath} 0755 root root"
      "d /var/log/unpackerr 0755 root root"
      
      # Create download subdirectories
      "d ${cfg.extraction.extractPath}/tv 0755 root root"
      "d ${cfg.extraction.extractPath}/movies 0755 root root"
      "d ${cfg.extraction.extractPath}/complete 0755 root root"
      "d ${cfg.extraction.extractPath}/complete/tv 0755 root root"
      "d ${cfg.extraction.extractPath}/complete/movies 0755 root root"
    ] ++ 
    # Additional folder monitoring directories
    (map (folder: "d ${folder.path} 0755 root root") cfg.folders);
    
    # Configure firewall for web interface
    networking.firewall.allowedTCPPorts = mkIf cfg.webui.enable [ cfg.webui.port ];
    
    # Nginx reverse proxy for web interface
    services.nginx.virtualHosts."unpackerr.orther.dev" = mkIf (config.services.nginx.enable && cfg.webui.enable) {
      forceSSL = true;
      useACMEHost = "orther.dev";
      locations."/" = {
        recommendedProxySettings = true;
        proxyPass = "http://127.0.0.1:${toString cfg.webui.port}${cfg.webui.urlBase}";
        extraConfig = ''
          # Unpackerr-specific headers
          proxy_set_header X-Forwarded-Proto $scheme;
          proxy_set_header X-Forwarded-Host $host;
          proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
          
          # WebSocket support for real-time updates
          proxy_http_version 1.1;
          proxy_set_header Upgrade $http_upgrade;
          proxy_set_header Connection "upgrade";
          
          # Timeout for long extraction operations
          proxy_read_timeout 300;
        '';
      };
      
      # Health endpoint
      locations."/dagger-health" = {
        return = "200 'healthy'";
        extraConfig = ''
          add_header Content-Type text/plain;
        '';
      };
    };
    
    # Generate Unpackerr configuration
    environment.etc."dagger-unpackerr/unpackerr.conf" = {
      text = ''
        # Unpackerr Configuration
        # Generated by NixOS Dagger integration
        
        ## Global Settings
        debug = ${if cfg.logging.level == "DEBUG" then "true" else "false"}
        quiet = ${if cfg.logging.level == "ERROR" then "true" else "false"}
        activity = ${if cfg.logging.enableSyslog then "true" else "false"}
        log_file = "${cfg.logging.logFile}"
        log_files = ${toString cfg.logging.maxBackups}
        log_file_mb = ${toString (lib.removeSuffix "MB" cfg.logging.maxSize)}
        
        ## Parallel Extraction
        parallel = ${toString cfg.extraction.parallelJobs}
        
        ## File Permissions
        file_mode = "${cfg.extraction.fileMode}"
        dir_mode = "${cfg.extraction.dirMode}"
        
        ## Archive Formats
        rar = ${if cfg.formats.enableRar then "true" else "false"}
        zip = ${if cfg.formats.enableZip then "true" else "false"}
        gz = ${if cfg.formats.enableTar then "true" else "false"}
        bz2 = ${if cfg.formats.enableTar then "true" else "false"}
        xz = ${if cfg.formats.enableTar then "true" else "false"}
        tar = ${if cfg.formats.enableTar then "true" else "false"}
        iso = ${if cfg.formats.enableIso then "true" else "false"}
        
        ${optionalString (cfg.formats.passwordFile != null) ''
        ## Archive Passwords
        passwords = ["${builtins.readFile cfg.formats.passwordFile}"]
        ''}
        
        ## Web UI
        ${optionalString cfg.webui.enable ''
        [webserver]
        metrics = ${if cfg.enableMetrics then "true" else "false"}
        listen_addr = "0.0.0.0:${toString cfg.webui.port}"
        log_file = "/var/log/unpackerr/webui.log"
        log_files = 5
        log_file_mb = 10
        ssl_key_file = ""
        ssl_cert_file = ""
        url_base = "${cfg.webui.urlBase}"
        upstreams = []
        ''}
        
        ${optionalString cfg.sonarr.enable ''
        ## Sonarr Configuration
        [[sonarr]]
        url = "http://127.0.0.1:${toString cfg.sonarr.port}"
        api_key = "/run/dagger-secrets/sonarr/api-key"
        paths = [${concatMapStringsSep ", " (p: ''"${p}"'') cfg.sonarr.paths}]
        protocols = "${concatStringsSep "," cfg.sonarr.protocols}"
        timeout = "${cfg.sonarr.timeout}"
        delete_delay = "${cfg.sonarr.deleteDelay}"
        delete_orig = ${if cfg.sonarr.deleteOriginal then "true" else "false"}
        syncthing = ${if cfg.sonarr.syncthing then "true" else "false"}
        ''}
        
        ${optionalString cfg.radarr.enable ''
        ## Radarr Configuration
        [[radarr]]
        url = "http://127.0.0.1:${toString cfg.radarr.port}"
        api_key = "/run/dagger-secrets/radarr/api-key"
        paths = [${concatMapStringsSep ", " (p: ''"${p}"'') cfg.radarr.paths}]
        protocols = "${concatStringsSep "," cfg.radarr.protocols}"
        timeout = "${cfg.radarr.timeout}"
        delete_delay = "${cfg.radarr.deleteDelay}"
        delete_orig = ${if cfg.radarr.deleteOriginal then "true" else "false"}
        syncthing = ${if cfg.radarr.syncthing then "true" else "false"}
        ''}
        
        ## Folder Monitoring
        ${concatMapStrings (folder: ''
        [[folder]]
        path = "${folder.path}"
        ${optionalString (folder.extractPath != null) ''extract_path = "${folder.extractPath}"''}
        delete_after = "${folder.deleteAfter}"
        delete_orig = ${if folder.deleteOriginal then "true" else "false"}
        move_back = ${if folder.moveBack then "true" else "false"}
        
        '') cfg.folders}
        
        ## Webhooks
        ${concatMapStrings (webhook: ''
        [[webhook]]
        name = "${webhook.name}"
        url = "${webhook.url}"
        events = [${concatMapStringsSep ", " (e: ''"${e}"'') webhook.events}]
        timeout = "${webhook.timeout}"
        silent = ${if webhook.silent then "true" else "false"}
        
        '') cfg.webhooks}
      '';
      mode = "0644";
    };
    
    # Dagger-specific systemd service
    systemd.services."dagger-automation-unpackerr" = {
      description = "Dagger-managed Unpackerr archive extraction service";
      wantedBy = [ "multi-user.target" ];
      after = [ 
        "network.target" 
        "dagger-coordinator.service"
      ] ++ optional (cfg.sonarr.enable || cfg.radarr.enable) "dagger-secret-injection.service";
      requires = [ 
        "dagger-coordinator.service"
      ] ++ optional (cfg.sonarr.enable || cfg.radarr.enable) "dagger-secret-injection.service";
      
      environment = {
        DAGGER_UNPACKERR_IMAGE = cfg.image;
        DAGGER_UNPACKERR_DATA_DIR = cfg.dataDir;
        DAGGER_UNPACKERR_CONFIG_FILE = "/etc/dagger-unpackerr/unpackerr.conf";
        DAGGER_UNPACKERR_EXTRACT_PATH = cfg.extraction.extractPath;
        DAGGER_UNPACKERR_PARALLEL_JOBS = toString cfg.extraction.parallelJobs;
        DAGGER_UNPACKERR_DELETE_AFTER = cfg.extraction.deleteAfter;
        DAGGER_UNPACKERR_DELETE_ORIGINAL = if cfg.extraction.deleteOriginal then "true" else "false";
        DAGGER_UNPACKERR_LOG_LEVEL = cfg.logging.level;
        DAGGER_UNPACKERR_WEB_PORT = toString cfg.webui.port;
        DAGGER_UNPACKERR_ENABLE_WEBUI = if cfg.webui.enable then "true" else "false";
        DAGGER_UNPACKERR_ENABLE_SONARR = if cfg.sonarr.enable then "true" else "false";
        DAGGER_UNPACKERR_ENABLE_RADARR = if cfg.radarr.enable then "true" else "false";
        DAGGER_UNPACKERR_ENABLE_AUTOUPDATE = if cfg.enableAutoUpdate then "true" else "false";
        DAGGER_UNPACKERR_ENABLE_BACKUP = if cfg.enableBackup then "true" else "false";
        DAGGER_UNPACKERR_ENABLE_MONITORING = if cfg.enableMonitoring then "true" else "false";
        DAGGER_UNPACKERR_ENABLE_METRICS = if cfg.enableMetrics then "true" else "false";
      };
      
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
        WorkingDirectory = config.services.dagger.workingDirectory;
        User = "root";
        Group = "root";
        
        ExecStart = pkgs.writeShellScript "start-dagger-unpackerr" ''
          #!/bin/bash
          set -euo pipefail
          
          echo "Starting Dagger-managed Unpackerr service..."
          
          # Verify extraction paths exist
          if [ ! -d "${cfg.extraction.extractPath}" ]; then
            echo "Creating extraction path: ${cfg.extraction.extractPath}"
            mkdir -p "${cfg.extraction.extractPath}"
            chmod 755 "${cfg.extraction.extractPath}"
          fi
          
          # Navigate to Dagger project
          cd ${config.services.dagger.projectDirectory}
          
          # Deploy Unpackerr via Dagger
          ${pkgs.dagger}/bin/dagger call services.automation.unpackerr.deploy \
            --image="$DAGGER_UNPACKERR_IMAGE" \
            --data-dir="$DAGGER_UNPACKERR_DATA_DIR" \
            --config-file="$DAGGER_UNPACKERR_CONFIG_FILE" \
            --extract-path="$DAGGER_UNPACKERR_EXTRACT_PATH" \
            --parallel-jobs="$DAGGER_UNPACKERR_PARALLEL_JOBS" \
            --delete-after="$DAGGER_UNPACKERR_DELETE_AFTER" \
            --delete-original="$DAGGER_UNPACKERR_DELETE_ORIGINAL" \
            --log-level="$DAGGER_UNPACKERR_LOG_LEVEL" \
            --web-port="$DAGGER_UNPACKERR_WEB_PORT" \
            --enable-webui="$DAGGER_UNPACKERR_ENABLE_WEBUI" \
            --enable-sonarr="$DAGGER_UNPACKERR_ENABLE_SONARR" \
            --enable-radarr="$DAGGER_UNPACKERR_ENABLE_RADARR" \
            --enable-autoupdate="$DAGGER_UNPACKERR_ENABLE_AUTOUPDATE" \
            --enable-backup="$DAGGER_UNPACKERR_ENABLE_BACKUP" \
            --enable-monitoring="$DAGGER_UNPACKERR_ENABLE_MONITORING" \
            --enable-metrics="$DAGGER_UNPACKERR_ENABLE_METRICS"
          
          echo "Dagger-managed Unpackerr started successfully"
        '';
        
        ExecStop = pkgs.writeShellScript "stop-dagger-unpackerr" ''
          #!/bin/bash
          set -euo pipefail
          
          echo "Stopping Dagger-managed Unpackerr service..."
          
          cd ${config.services.dagger.projectDirectory}
          
          # Stop Unpackerr via Dagger
          ${pkgs.dagger}/bin/dagger call services.automation.unpackerr.stop
          
          echo "Dagger-managed Unpackerr stopped"
        '';
        
        ExecReload = pkgs.writeShellScript "reload-dagger-unpackerr" ''
          #!/bin/bash
          set -euo pipefail
          
          echo "Reloading Dagger-managed Unpackerr service..."
          
          cd ${config.services.dagger.projectDirectory}
          
          # Restart Unpackerr via Dagger
          ${pkgs.dagger}/bin/dagger call services.automation.unpackerr.restart
          
          echo "Dagger-managed Unpackerr reloaded"
        '';
        
        # Resource limits
        MemoryMax = "1G";
        CPUQuota = "150%";
        TasksMax = "100";
        
        # Security settings
        NoNewPrivileges = true;
        ProtectSystem = "strict";
        ProtectHome = true;
        ReadWritePaths = [
          cfg.dataDir
          cfg.extraction.extractPath
          "/var/log/unpackerr"
          config.services.dagger.workingDirectory
          # Add paths for folder monitoring
        ] ++ (map (folder: folder.path) cfg.folders) ++
          # Add paths for nixarr integration
          (optional cfg.sonarr.enable "${nixarrCfg.storage.mediaRoot}/tv") ++
          (optional cfg.radarr.enable "${nixarrCfg.storage.mediaRoot}/movies");
        PrivateTmp = true;
      };
      
      # Health check integration  
      onFailure = mkIf cfg.enableMonitoring [ "dagger-unpackerr-health-check.service" ];
    };
    
    # Enhanced health check service
    systemd.services."dagger-unpackerr-health-check" = mkIf cfg.enableMonitoring {
      description = "Unpackerr health check";
      serviceConfig = {
        Type = "oneshot";
        User = "root";
        Group = "root";
        ExecStart = pkgs.writeShellScript "unpackerr-health-check" ''
          #!/bin/bash
          set -euo pipefail
          
          echo "Performing Unpackerr health check..."
          
          # Check if web interface is responding (if enabled)
          ${optionalString cfg.webui.enable ''
          if curl -f -s --connect-timeout 10 "http://127.0.0.1:${toString cfg.webui.port}/api/health" > /dev/null; then
            echo "✓ Unpackerr web interface is responding"
          else
            echo "✗ Unpackerr web interface is not responding"
            exit 1
          fi
          ''}
          
          # Check if container is running
          if podman ps --filter "name=unpackerr" --format "{{.Names}}" | grep -q unpackerr; then
            echo "✓ Unpackerr container is running"
          else
            echo "✗ Unpackerr container is not running"
            exit 1
          fi
          
          # Check extraction path accessibility
          if [ -d "${cfg.extraction.extractPath}" ] && [ -w "${cfg.extraction.extractPath}" ]; then
            echo "✓ Extraction path is accessible and writable"
          else
            echo "✗ Extraction path is not accessible or writable"
            exit 1
          fi
          
          # Test service integrations
          ${optionalString cfg.sonarr.enable ''
          if curl -f -s --connect-timeout 5 "http://127.0.0.1:${toString cfg.sonarr.port}/api/v3/system/status" > /dev/null; then
            echo "✓ Sonarr integration is healthy"
          else
            echo "⚠️  Sonarr integration may have issues"
          fi
          ''}
          
          ${optionalString cfg.radarr.enable ''
          if curl -f -s --connect-timeout 5 "http://127.0.0.1:${toString cfg.radarr.port}/api/v3/system/status" > /dev/null; then
            echo "✓ Radarr integration is healthy"
          else
            echo "⚠️  Radarr integration may have issues"
          fi
          ''}
          
          # Check recent extraction activity
          if find "${cfg.extraction.extractPath}" -name "*.log" -mtime -1 | grep -q .; then
            echo "✓ Recent extraction activity detected"
          else
            echo "ℹ️  No recent extraction activity"
          fi
          
          echo "Unpackerr health check completed successfully"
        '';
      };
    };
    
    # Backup service integration
    systemd.services."dagger-backup-unpackerr" = mkIf cfg.enableBackup {
      description = "Backup Unpackerr via Dagger pipeline";
      wantedBy = [ "default.target" ];
      after = [ "dagger-automation-unpackerr.service" ];
      requisite = mkIf (config.sops.secrets ? "kopia-repository-token") [ "sops-nix.service" ];
      
      serviceConfig = {
        Type = "oneshot";
        User = "root";
        Group = "root";
        WorkingDirectory = config.services.dagger.projectDirectory;
        
        ExecStart = pkgs.writeShellScript "dagger-backup-unpackerr" ''
          #!/bin/bash
          set -euo pipefail
          
          echo "Starting Dagger-managed Unpackerr backup..."
          
          # Run backup via Dagger pipeline (config only, not temp files)
          ${pkgs.dagger}/bin/dagger call services.automation.unpackerr.backup.backup \
            --service="unpackerr" \
            --paths="${cfg.dataDir},/etc/dagger-unpackerr,/var/log/unpackerr"
          
          echo "Dagger-managed Unpackerr backup completed"
        '';
        
        # Environment for secrets access
        EnvironmentFile = mkIf (config.sops.secrets ? "kopia-repository-token") 
          config.sops.secrets."kopia-repository-token".path;
      };
    };
    
    # Backup timer
    systemd.timers."dagger-backup-unpackerr" = mkIf cfg.enableBackup {
      description = "Backup Unpackerr via Dagger";
      wantedBy = [ "timers.target" ];
      timerConfig = {
        OnCalendar = "*-*-* 1:30:00";
        RandomizedDelaySec = "30m";
        Persistent = true;
      };
    };
    
    # Auto-update timer
    systemd.timers."dagger-autoupdate-unpackerr" = mkIf cfg.enableAutoUpdate {
      description = "Auto-update Unpackerr container via Dagger";
      wantedBy = [ "timers.target" ];
      timerConfig = {
        OnCalendar = "*-*-* 4:30:00";
        RandomizedDelaySec = "30m";
        Persistent = true;
      };
    };
    
    systemd.services."dagger-autoupdate-unpackerr" = mkIf cfg.enableAutoUpdate {
      description = "Auto-update Unpackerr container";
      serviceConfig = {
        Type = "oneshot";
        User = "root";
        Group = "root";
        WorkingDirectory = config.services.dagger.projectDirectory;
        
        ExecStart = pkgs.writeShellScript "dagger-autoupdate-unpackerr" ''
          #!/bin/bash
          set -euo pipefail
          
          echo "Checking for Unpackerr container updates..."
          
          # Update via Dagger pipeline
          ${pkgs.dagger}/bin/dagger call services.automation.unpackerr.update \
            --check-only=false
          
          echo "Unpackerr container update check completed"
        '';
      };
    };
    
    # Log rotation for application logs
    services.logrotate.settings.unpackerr = {
      files = "/var/log/unpackerr/*.log";
      frequency = "daily";
      rotate = 7;
      compress = true;
      delaycompress = true;
      missingok = true;
      notifempty = true;
      create = "644 root root";
      copytruncate = true; # Important for active log files
    };
    
    # Persistence configuration
    environment.persistence."/nix/persist" = mkIf config.environment.persistence."/nix/persist".enable {
      directories = [
        cfg.dataDir
        "/var/log/unpackerr"
        # Note: extraction path is typically on media storage, already persisted
      ];
    };
    
    # Assertions to ensure proper configuration
    assertions = [
      {
        assertion = cfg.extraction.parallelJobs > 0 && cfg.extraction.parallelJobs <= 10;
        message = "Unpackerr parallel jobs must be between 1 and 10";
      }
      {
        assertion = cfg.dataDir != "";
        message = "Unpackerr data directory must be specified";
      }
      {
        assertion = config.services.dagger.enable;
        message = "Dagger service must be enabled for Dagger-managed Unpackerr";
      }
      {
        assertion = !cfg.sonarr.enable || nixarrCfg.sonarr.enable or false;
        message = "Sonarr must be enabled in nixarr configuration for Unpackerr integration";
      }
      {
        assertion = !cfg.radarr.enable || nixarrCfg.radarr.enable or false;
        message = "Radarr must be enabled in nixarr configuration for Unpackerr integration";
      }
      {
        assertion = cfg.webui.port != cfg.sonarr.port && cfg.webui.port != cfg.radarr.port;
        message = "Unpackerr web UI port must be different from service ports";
      }
    ];
    
    # Warnings for configuration considerations
    warnings = 
      (optional (!cfg.sonarr.enable && !cfg.radarr.enable && cfg.folders == [])
        "Unpackerr has no configured integrations or folders - it may not do anything") ++
      (optional (cfg.extraction.deleteOriginal && cfg.extraction.deleteAfter == "0s")
        "Unpackerr will immediately delete archives - consider adding a delay") ++
      (optional (cfg.formats.enableIso && !cfg.formats.enableTar)
        "ISO extraction may require TAR support for some disc images") ++
      (optional (cfg.webui.enable && !cfg.webui.enableAuth)
        "Unpackerr web interface authentication is disabled - consider enabling for security");
  };
}