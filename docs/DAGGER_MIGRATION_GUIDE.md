# NixOS + Dagger Migration Guide

This guide walks you through migrating your existing Docker Compose services to NixOS + Dagger while maintaining all existing functionality.

## Overview

The migration introduces Dagger.io as a modern CI/CD pipeline system that complements your existing NixOS infrastructure. Key benefits:

- **Enhanced CI/CD**: Reproducible build pipelines with intelligent caching
- **Container orchestration**: Better lifecycle management than plain Podman  
- **Monitoring integration**: Built-in health checks and observability
- **Backup coordination**: Seamless integration with existing Kopia backups
- **Gradual migration**: Services can be migrated incrementally

## Architecture

### Before (Current)
```
┌─────────────────┐    ┌──────────────────┐    ┌─────────────────┐
│   NixOS Host    │    │  Podman/OCI      │    │  systemd        │
│                 │    │  Containers      │    │  Services       │
│ • SOPS Secrets  │───▶│ • homebridge     │───▶│ • podman-*      │
│ • Nginx Proxy   │    │ • scrypted       │    │ • backup-*      │
│ • Persistence   │    │ • Manual config  │    │ • timers        │
└─────────────────┘    └──────────────────┘    └─────────────────┘
```

### After (With Dagger)
```
┌─────────────────┐    ┌──────────────────┐    ┌─────────────────┐
│   NixOS Host    │    │  Dagger Engine   │    │  systemd        │
│                 │    │  (CUE workflows) │    │  Integration    │
│ • SOPS Bridge   │───▶│ • automation     │───▶│ • dagger-*      │
│ • Nginx Proxy   │    │ • media          │    │ • backup coord  │
│ • Persistence   │    │ • infrastructure │    │ • health checks │
└─────────────────┘    └──────────────────┘    └─────────────────┘
```

## Prerequisites

1. **Current working NixOS setup** with services in `/services/`
2. **SOPS-nix configured** for secrets management
3. **Podman/OCI containers** currently working
4. **Backup system** with Kopia (if desired)

## Migration Steps

### Phase 1: Foundation Setup

#### 1.1 Add Dagger Input to Flake
```nix
# flake.nix
{
  inputs = {
    # ... existing inputs ...
    
    # Add Dagger support
    dagger = {
      url = "github:dagger/dagger";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };
}
```

#### 1.2 Install Base Dagger Services
```bash
# Copy the provided Dagger files
cp -r ./dagger /your/project/
cp -r ./services/dagger /your/project/services/

# Add to a server configuration
# Example: machines/svr2chng/configuration.nix
{
  imports = [
    # ... existing imports ...
    ./../../services/dagger/base.nix
    ./../../services/dagger/secrets.nix
  ];
  
  # Enable Dagger service management
  services.dagger = {
    enable = true;
    services = []; # Start with empty list
    enableBackupIntegration = true;
    enableMonitoring = true;
  };
}
```

#### 1.3 Initialize Dagger Project
```bash
# Navigate to your project root
cd /path/to/doomlab-corrupted

# Initialize Dagger
cd dagger
dagger project init

# Test basic functionality
dagger call --help
```

### Phase 2: Service Migration

#### 2.1 Migrate Homebridge (Example)

**Before**: `/services/homebridge.nix` with OCI containers
**After**: `/services/dagger/homebridge.nix` with Dagger orchestration

1. **Disable existing service**:
```nix
# In your server configuration
# Comment out or remove:
# ./../../services/homebridge.nix
```

2. **Enable Dagger-managed version**:
```nix
# In your server configuration
imports = [
  # ... other imports ...
  ./../../services/dagger/homebridge.nix
];

services.dagger.homebridge = {
  enable = true;
  enableBackup = true;
  enableMonitoring = true;
};
```

3. **Deploy and verify**:
```bash
# Rebuild NixOS configuration
sudo nixos-rebuild switch

# Check service status
systemctl status dagger-automation-homebridge
systemctl status dagger-coordinator

# Verify container is running
podman ps | grep homebridge

# Test web interface
curl -f http://localhost:8581
```

#### 2.2 Migrate Scrypted (Similar Process)

1. Create `/services/dagger/scrypted.nix` following the Homebridge pattern
2. Update CUE definitions in `/dagger/services/automation.cue`
3. Test deployment pipeline

#### 2.3 Migrate Media Processing

Media services (nixarr) should generally stay as NixOS systemd services since they're well-integrated. However, you can add Dagger workflows for:

- Advanced transcoding pipelines
- Enhanced monitoring  
- Coordinated backups
- Custom media processing

### Phase 3: Enhanced Features

#### 3.1 CI/CD Pipeline Integration

Add to `.github/workflows/` or your CI system:

```yaml
name: NixOS + Dagger CI
on: [push, pull_request]

jobs:
  build-and-test:
    runs-on: self-hosted  # Your NixOS runner
    steps:
      - uses: actions/checkout@v4
      
      - name: Build NixOS configurations
        run: |
          cd dagger
          dagger call pipeline.build
      
      - name: Run tests
        run: |
          cd dagger  
          dagger call pipeline.test
      
      - name: Security scan
        run: |
          cd dagger
          dagger call pipeline.security.scan
```

#### 3.2 Enhanced Monitoring

The Dagger setup includes built-in monitoring:

- Health checks every 15 minutes
- Storage utilization alerts
- Service dependency tracking
- Integration with existing monitoring

#### 3.3 Backup Coordination

Enhanced backup system that coordinates with Kopia:

- Service-aware backup scheduling
- Backup verification and integrity checks
- Retention policy management
- Cross-service backup dependencies

## Configuration Reference

### Service Configuration

```nix
# services/dagger/homebridge.nix
services.dagger.homebridge = {
  enable = true;
  image = "ghcr.io/homebridge/homebridge:latest";
  dataDir = "/var/lib/homebridge";
  port = 8581;
  childBridgePorts = [ 50000 50001 50002 ];
  portRange = { from = 50100; to = 50200; };
  enableAutoUpdate = true;
  enableBackup = true;
  enableMonitoring = true;
  network = "host";
};
```

### Secrets Configuration

```nix
# Secrets are automatically bridged from SOPS
services.dagger.secrets = {
  enable = true;
  rotation.enable = true;
  runtime.secretsDir = "/run/dagger-secrets";
};
```

### Storage Configuration

```nix
# Storage volumes are created automatically
# Aligned with existing persistence patterns
services.dagger = {
  storage = {
    persistRoot = "/nix/persist";
    mediaRoot = "/fun";
    stateRoot = "/var/lib";
  };
};
```

## Troubleshooting

### Common Issues

#### 1. Container Fails to Start
```bash
# Check Dagger service logs
journalctl -u dagger-coordinator -f
journalctl -u dagger-automation-homebridge -f

# Check Podman status
podman ps -a
podman logs homebridge
```

#### 2. Secrets Not Available
```bash
# Check secret injection service
systemctl status dagger-secret-injection

# Verify secrets exist
ls -la /run/dagger-secrets/

# Check SOPS configuration
sops -d secrets/secrets.yaml
```

#### 3. Network Issues
```bash
# Check Dagger networks
podman network ls
podman network inspect dagger-default

# Check firewall rules
iptables -L nixos-fw -n

# Test connectivity
curl -f http://127.0.0.1:8581
```

#### 4. Storage Problems
```bash
# Check storage volumes
df -h /var/lib/dagger /nix/persist /fun

# Check permissions
ls -la /var/lib/homebridge /var/lib/scrypted

# Check persistence
systemctl status impermanence
```

### Performance Tuning

#### Container Resource Limits
```nix
# Adjust resource limits in service config
systemd.services."dagger-automation-homebridge".serviceConfig = {
  MemoryMax = "2G";
  CPUQuota = "200%";  
  TasksMax = "1000";
};
```

#### Storage Optimization
```bash
# Clean up old containers
podman system prune -af

# Monitor storage usage  
systemctl start dagger-storage-monitor

# Check cache utilization
du -sh /var/cache/dagger
```

## Migration Checklist

### Pre-Migration
- [ ] Backup all service data
- [ ] Document current service configurations
- [ ] Test NixOS rebuild process
- [ ] Verify SOPS secrets are working

### During Migration
- [ ] Add Dagger input to flake
- [ ] Copy Dagger project files
- [ ] Enable base Dagger services
- [ ] Test Dagger project initialization
- [ ] Migrate one service at a time
- [ ] Verify each service after migration

### Post-Migration
- [ ] Remove old OCI container configurations
- [ ] Update backup scripts if needed
- [ ] Test complete system rebuild
- [ ] Verify monitoring and health checks
- [ ] Update documentation

## Advanced Usage

### Custom Dagger Workflows

Create custom workflows by extending the CUE definitions:

```cue
// dagger/services/custom.cue
#CustomService: {
    config: #NixOSConfig
    
    // Your custom service definition
    container: docker.#Container & {
        // Custom configuration
    }
}
```

### Multi-Host Deployment

Extend for multi-host deployment:

```nix
# Deploy to multiple servers
services.dagger = {
  services = [ "automation.homebridge" ];
  remoteHosts = [ "svr2chng" "svr3chng" ];
};
```

### Integration with External Systems

Connect with external monitoring/alerting:

```bash
# Custom monitoring integration
dagger call services.monitoring.prometheus.configure \
  --endpoint="https://prometheus.example.com"
```

## Benefits Realized

After migration, you'll have:

1. **Improved CI/CD**: Reproducible builds with intelligent caching
2. **Better monitoring**: Built-in health checks and observability  
3. **Enhanced backups**: Service-aware backup coordination
4. **Easier maintenance**: Declarative service definitions
5. **Future flexibility**: Easy to add new services and workflows

## Support

For issues or questions:

1. Check service logs: `journalctl -u dagger-*`
2. Verify Dagger project: `dagger call --help`  
3. Test individual services: `dagger call services.automation.homebridge.health`
4. Consult Dagger documentation: https://docs.dagger.io/

The migration maintains all existing functionality while adding powerful new capabilities for container orchestration and CI/CD.