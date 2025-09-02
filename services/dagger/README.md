# Dagger-Enhanced Nixarr Services

This module provides complete Dagger-enhanced implementations for the nixarr suite (Sonarr, Radarr, Prowlarr, Bazarr, Transmission, and Jellyfin) that integrate seamlessly with your existing NixOS configuration.

## Overview

The Dagger integration provides:

- **Enhanced service management** with container orchestration
- **Advanced health monitoring** and automatic recovery
- **Integrated backup workflows** with Kopia
- **Service interconnectivity** with API-based communication
- **Migration compatibility** for existing nixarr installations
- **SOPS secrets integration** for secure credential management

## Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                    NixOS Host System                        │
├─────────────────────────────────────────────────────────────┤
│  Nginx Proxy    │  SOPS Secrets   │  Persistence Layer     │
├─────────────────────────────────────────────────────────────┤
│                   Dagger Engine                             │
├─────────────────────────────────────────────────────────────┤
│  Sonarr    │  Radarr    │  Prowlarr   │  Bazarr    │ Jellyfin│
│  Container │  Container │  Container   │  Container │Container│
├─────────────────────────────────────────────────────────────┤
│              Transmission Container                         │
├─────────────────────────────────────────────────────────────┤
│  Media Storage (/fun)  │  State Storage (/var/lib/nixarr)   │
└─────────────────────────────────────────────────────────────┘
```

## Quick Start

### 1. Basic Setup (Side-by-Side with Existing Services)

Add to your NixOS configuration:

```nix
{
  imports = [
    ./services/dagger/integration.nix
  ];

  services.dagger.nixarr.integration = {
    enable = true;
    enhanceExistingServices = true;  # Keeps existing services running
  };
  
  # Enable specific services you want to enhance
  services.dagger.nixarr = {
    sonarr.enable = true;
    radarr.enable = true;
    prowlarr.enable = true;
    bazarr.enable = true;
    transmission.enable = true;
    jellyfin.enable = true;
  };
}
```

### 2. Full Migration (Replace Existing Services)

```nix
{
  services.dagger.nixarr.integration = {
    enable = true;
    replaceExistingServices = true;  # Disables existing nixarr services
    enableAllServices = true;        # Enables all Dagger services
  };
}
```

### 3. Gradual Migration (Service by Service)

```nix
{
  services.dagger.nixarr.integration.enable = true;
  
  # Migrate one service at a time
  services.dagger.nixarr.sonarr.enable = true;
  # Leave others on existing nixarr for now
}
```

## Configuration Options

### Service Configuration

Each service supports the same configuration options as the existing nixarr module:

```nix
services.dagger.nixarr = {
  # Storage configuration (matches existing paths)
  mediaDir = "/fun";
  stateDir = "/var/lib/nixarr";
  
  # Network configuration
  network = {
    domain = "orther.dev";
    ports = {
      sonarr = 8989;
      radarr = 7878;
      prowlarr = 9696;
      bazarr = 6767;
      transmission = 9091;
      jellyfin = 8096;
    };
  };
  
  # Service-specific settings
  sonarr = {
    enable = true;
    enhancedFeatures = true;  # Enables Dagger-specific enhancements
  };
  
  transmission = {
    enable = true;
    username = "orther";
    peerPort = 46634;  # Matches existing configuration
  };
  
  jellyfin = {
    enable = true;
    hardwareAcceleration = false;  # Enable if GPU available
  };
};
```

### Enhanced Features

```nix
services.dagger.nixarr = {
  # Enhanced monitoring
  monitoring = {
    enable = true;
    healthCheckInterval = "5m";
    alerting = false;  # Can be enabled with notification system
  };
  
  # Enhanced backup
  backup = {
    enable = true;
    schedule = "daily";
    retention = "30d";
  };
};
```

### Migration Settings

```nix
services.dagger.nixarr.migration = {
  enableCompatibilityMode = true;    # Allow side-by-side operation
  backupBeforeMigration = true;      # Create backups before migration
  autoRollbackOnFailure = false;    # Auto-rollback on migration failure
  dataImportPath = "/var/lib/nixarr"; # Import existing data
};
```

## SOPS Secrets Integration

The system integrates with your existing SOPS configuration:

```nix
sops.secrets = {
  # API keys for enhanced inter-service communication
  "nixarr/sonarr/api-key" = {
    owner = "dagger";
    group = "dagger";
    mode = "0440";
  };
  "nixarr/radarr/api-key" = {
    owner = "dagger";
    group = "dagger"; 
    mode = "0440";
  };
  "nixarr/prowlarr/api-key" = {
    owner = "dagger";
    group = "dagger";
    mode = "0440";
  };
  "nixarr/bazarr/api-key" = {
    owner = "dagger";
    group = "dagger";
    mode = "0440";
  };
  "nixarr/transmission/rpc-password" = {
    owner = "dagger";
    group = "dagger";
    mode = "0440";
  };
  "nixarr/jellyfin/api-key" = {
    owner = "dagger";
    group = "dagger";
    mode = "0440";
  };
};
```

## Migration Guide

### Check Current Status

```bash
# Check overall status
nixarr-migrate status

# View detailed integration status  
dagger-nixarr-summary

# Check for service conflicts
nixarr-migration-status
```

### Migrate Individual Services

```bash
# Migrate one service
sudo nixarr-migrate migrate sonarr

# Check if migration was successful
nixarr-migrate status

# Rollback if needed
sudo nixarr-migrate rollback sonarr
```

### Migrate All Services

```bash
# Backup current state first (automatic if enabled)
sudo systemctl start nixarr-pre-migration-backup

# Migrate all enabled services
sudo nixarr-migrate migrate all

# Verify all services are healthy
nixarr-migrate status
```

## Management Commands

### Service Management

```bash
# View all services
systemctl list-units "dagger-*"

# Control individual services
sudo systemctl start dagger-sonarr
sudo systemctl stop dagger-sonarr
sudo systemctl restart dagger-sonarr

# View service logs
journalctl -u dagger-sonarr -f
```

### Dagger Integration

```bash
# Access Dagger nixarr actions directly
dagger call nixarr services sonarr health check

# Run service orchestration
dagger call nixarr orchestration startup

# Run health monitoring
dagger call nixarr orchestration monitor

# Run backup workflow  
dagger call nixarr backup backup_all
```

### Monitoring and Troubleshooting

```bash
# View service logs
nixarr-logs  # Alias for journalctl -u "dagger-*nixarr*" -f

# Check health status
systemctl status dagger-nixarr-integration

# View integration status report
cat /var/lib/dagger/integration-status.txt

# Run comprehensive test suite
dagger call test nixarr run_all_tests
```

## File Locations

### Configuration and Data

- **Service configs**: `/var/lib/nixarr/` (unchanged from existing setup)
- **Media files**: `/fun/` (unchanged from existing setup)
- **Dagger config**: `/etc/dagger/config.cue`
- **Secrets**: `/run/dagger-secrets/`

### Logs and Status

- **Service logs**: `journalctl -u dagger-*`
- **Integration status**: `/var/lib/dagger/integration-status.txt`
- **Migration state**: `/var/lib/dagger/nixarr-migration-state.json`
- **Backups**: `/var/lib/dagger/backups/`

## Troubleshooting

### Common Issues

1. **Port Conflicts**
   ```bash
   # Check for conflicts
   nixarr-migrate status
   
   # Stop conflicting services
   sudo systemctl stop sonarr  # Stop legacy service
   sudo systemctl start dagger-sonarr  # Start Dagger service
   ```

2. **Service Won't Start**
   ```bash
   # Check logs
   journalctl -u dagger-sonarr -n 50
   
   # Check Dagger connectivity
   dagger version
   
   # Verify directories and permissions
   ls -la /var/lib/nixarr/sonarr/
   ```

3. **API Communication Issues**
   ```bash
   # Check API endpoints
   curl http://127.0.0.1:8989/ping
   
   # Verify secrets are available
   ls -la /run/dagger-secrets/sonarr/
   ```

4. **Migration Failures**
   ```bash
   # Check migration state
   cat /var/lib/dagger/nixarr-migration-state.json
   
   # Rollback to previous state
   sudo nixarr-migrate rollback <service>
   
   # Restore from backup
   ls /var/lib/dagger/backups/
   ```

### Performance Optimization

1. **Enable Hardware Acceleration**
   ```nix
   services.dagger.nixarr.jellyfin = {
     enable = true;
     hardwareAcceleration = true;
   };
   
   # Ensure GPU access
   hardware.opengl.enable = true;
   ```

2. **Optimize Storage**
   ```nix
   # Use fast storage for state directory
   services.dagger.nixarr.stateDir = "/fast-ssd/nixarr";
   
   # Keep media on larger, slower storage
   services.dagger.nixarr.mediaDir = "/bulk-storage/media";
   ```

## Integration with Existing Services

### Nginx Configuration

The integration automatically configures nginx virtual hosts with enhanced headers and security. Your existing nginx configuration will be preserved and enhanced.

### Backup Integration

If you have existing Kopia backups configured, the Dagger services will integrate with your backup schedule and retention policies.

### Monitoring Integration

The services integrate with your existing monitoring stack (netdata, etc.) and provide additional health endpoints for enhanced monitoring.

## Advanced Usage

### Custom Dagger Workflows

You can extend the services with custom Dagger workflows:

```cue
// custom-workflow.cue
package main

#CustomNixarrWorkflow: {
    config: #NixOSConfig
    
    // Your custom enhancements
    custom_process: bash.#Script & {
        script: """
            # Custom processing logic
            echo "Running custom nixarr workflow..."
        """
    }
}
```

### Service Dependencies

Configure service startup order and dependencies:

```nix
systemd.services.my-custom-service = {
  after = ["dagger-sonarr.service" "dagger-radarr.service"];
  wants = ["dagger-prowlarr.service"];
};
```

## Support

For issues and questions:

1. Check the troubleshooting section above
2. Review service logs: `journalctl -u dagger-*`
3. Run the test suite: `dagger call test nixarr run_all_tests`
4. Check the integration status: `dagger-nixarr-summary`

The system is designed to be compatible with your existing nixarr configuration while providing enhanced capabilities through Dagger container orchestration.