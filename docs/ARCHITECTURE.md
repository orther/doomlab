# Architecture Guide

This guide explains the design principles, directory structure, and module organization of the doomlab configuration.

## Overview

The doomlab configuration is built on a **modular, declarative architecture** that manages 11 different machines across multiple platforms. The design emphasizes reusability, maintainability, and clear separation of concerns.

## Core Principles

### 1. Declarative Configuration
Everything is defined in Nix files - from system packages to service configurations to user dotfiles. The entire system state can be reproduced from these files.

### 2. Modular Design  
Configuration is broken into focused, reusable modules that can be mixed and matched across machines.

### 3. Separation of Concerns
- **Machines**: Host-specific configuration
- **Modules**: Reusable functionality 
- **Services**: Self-hosted application configs
- **Secrets**: Encrypted sensitive data

### 4. Stateless by Design
Most systems use impermanence (root on tmpfs) to ensure reproducible, stateless operation.

## Directory Structure

```
doomlab/
├── flake.nix              # Main entry point, defines all machines and inputs
├── flake.lock             # Locked dependency versions  
├── justfile               # Task runner with common operations
├── install.sh             # Automated installation script
│
├── machines/              # Host-specific configurations (11 total)
│   ├── macos/            # M1 MacBook Air (nix-darwin)
│   ├── noir/             # Main homelab server (NixOS) 
│   ├── wsl/              # Windows Subsystem for Linux
│   ├── iso1chng/         # Custom NixOS installer ISO
│   ├── desktop/          # AMD Ryzen desktop
│   ├── proxmox/          # Proxmox VE server
│   ├── nuc/              # Intel NUC mini server
│   └── ...               # Additional specialized configs
│
├── modules/               # Reusable configuration modules
│   ├── nixos/            # NixOS-specific modules
│   │   ├── base.nix      # Common NixOS settings
│   │   ├── users.nix     # User account configuration  
│   │   ├── impermanence.nix # Root on tmpfs setup
│   │   └── auto-update.nix  # Automatic system updates
│   ├── darwin/           # macOS-specific modules (nix-darwin)
│   │   ├── base.nix      # Common macOS settings
│   │   └── homebrew.nix  # Homebrew package management
│   └── shared/           # Cross-platform modules
│       ├── packages.nix  # Common packages
│       └── home.nix      # Home Manager configuration
│
├── services/             # Self-hosted application configurations
│   ├── nextcloud.nix     # File sync and sharing
│   ├── jellyfin.nix      # Media server
│   ├── tailscale.nix     # VPN mesh network
│   ├── nginx.nix         # Reverse proxy
│   ├── acme.nix          # Let's Encrypt certificates
│   └── ...               # Additional services
│
├── secrets/              # Encrypted secrets management
│   ├── secrets.yaml      # Main secrets file (SOPS encrypted)
│   └── ...               # Additional secret files
│
└── docs/                 # Documentation
    ├── SETUP.md          # Installation guide
    ├── ARCHITECTURE.md   # This file  
    ├── SECRETS.md        # Secrets management
    └── TROUBLESHOOTING.md # Common issues
```

## Key Technologies

### Nix Flakes
The entire configuration is managed as a Nix flake, providing:
- **Reproducible builds**: Locked dependencies in `flake.lock`
- **Input management**: External dependencies declared in `flake.nix`
- **Multi-system support**: Single flake manages all platforms

### Home Manager
Manages user-level configuration:
- Dotfiles and shell configuration
- User-specific packages
- Application settings
- Cross-platform user environment

### SOPS (Secrets OPerationS)
Encrypted secrets management:
- Age/GPG encryption
- Integration with Nix
- Machine-specific secret access
- Git-friendly encrypted storage

## Machine Types

### Production Servers
- **noir**: Main homelab server (Intel NUC)
  - Services: Nextcloud, Jellyfin, Tailscale
  - Storage: NFS mounts, Docker volumes
  - Security: Firewall, fail2ban, automated updates
  
- **proxmox**: Proxmox VE hypervisor
  - Manages multiple VMs
  - Backup and disaster recovery
  - Hardware passthrough

### Development Machines  
- **macos**: M1 MacBook Air
  - nix-darwin configuration
  - Development tools and environments
  - Homebrew integration for GUI apps

- **desktop**: AMD Ryzen workstation  
  - Gaming and development
  - GPU acceleration
  - Multiple monitor setup

### Specialized Configs
- **wsl**: Windows Subsystem for Linux
  - Minimal NixOS for development
  - Windows integration
  - Lightweight package set

- **iso1chng**: Custom NixOS installer
  - Pre-configured for remote installation
  - SSH keys embedded
  - Automated partitioning scripts

## Module System

### Base Modules

**nixos/base.nix**: Common NixOS settings
```nix
{
  # Essential system configuration
  nix.settings.experimental-features = [ "nix-command" "flakes" ];
  
  # Security hardening
  security.sudo.wheelNeedsPassword = false; # TODO: Fix this
  
  # Automatic garbage collection
  nix.gc = {
    automatic = true;
    dates = "weekly";
    options = "--delete-older-than 7d";
  };
}
```

**shared/packages.nix**: Cross-platform packages
```nix
{
  # Common utilities available everywhere
  environment.systemPackages = with pkgs; [
    git vim curl wget jq
    tmux htop tree ripgrep
  ];
}
```

### Service Modules

Each service is self-contained with:
- Enable/disable options
- Configuration parameters  
- Dependencies and requirements
- Security settings

**Example: services/tailscale.nix**
```nix
{ config, lib, pkgs, ... }:

with lib;

{
  options.services.tailscale = {
    enable = mkEnableOption "Tailscale VPN";
    authKeyFile = mkOption {
      type = types.path;
      description = "Path to Tailscale auth key file";
    };
  };

  config = mkIf config.services.tailscale.enable {
    services.tailscale = {
      enable = true;
      authKeyFile = config.services.tailscale.authKeyFile;
    };
    
    networking.firewall = {
      checkReversePath = "loose";
      trustedInterfaces = [ "tailscale0" ];
    };
  };
}
```

## Data Flow

### 1. Flake Entry Point
`flake.nix` defines all machine configurations and their inputs:

```nix
{
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-24.05";
    home-manager.url = "github:nix-community/home-manager/release-24.05";
    sops-nix.url = "github:Mic92/sops-nix";
  };

  outputs = { self, nixpkgs, ... }@inputs: {
    nixosConfigurations = {
      noir = nixpkgs.lib.nixosSystem {
        system = "x86_64-linux";
        modules = [ ./machines/noir ];
        specialArgs = { inherit inputs; };
      };
    };
  };
}
```

### 2. Machine Configuration
Each machine imports relevant modules:

```nix
# machines/noir/configuration.nix
{
  imports = [
    ./hardware-configuration.nix
    ../../modules/nixos/base.nix
    ../../modules/nixos/impermanence.nix
    ../../services/nextcloud.nix
    ../../services/tailscale.nix
  ];
  
  networking.hostName = "noir";
  services.nextcloud.enable = true;
  services.tailscale.enable = true;
}
```

### 3. Module Execution
Modules provide options and implement functionality:
- Options define configurable parameters
- Config sections implement the actual system changes
- Dependencies are automatically resolved

## Security Architecture

### Network Security
- **Tailscale VPN**: Encrypted mesh network between all machines
- **Firewall**: Restrictive rules, only necessary ports open
- **Fail2ban**: Automatic IP blocking for suspicious activity

### Secrets Management
- **SOPS encryption**: All secrets encrypted with age/GPG
- **Machine-specific access**: Each machine can only decrypt its secrets
- **Git integration**: Encrypted secrets safely stored in version control

### System Security
- **Impermanence**: Root filesystem on tmpfs, persistent data explicitly managed
- **Automatic updates**: Daily security updates via systemd timers
- **Minimal attack surface**: Only necessary services enabled

## Development Workflow

### 1. Local Development
```bash
# Make changes to configuration
$EDITOR machines/your-machine/configuration.nix

# Test changes locally
just deploy your-machine

# Verify deployment
systemctl status nginx
```

### 2. Remote Deployment
```bash
# Deploy to remote machine
just deploy noir 10.4.0.26

# Check status
ssh orther@10.4.0.26 systemctl status --failed
```

### 3. Updates and Maintenance
```bash
# Update all inputs
just up

# Deploy updates to all machines
just deploy noir 10.4.0.26
just deploy macos
```

## Extension Points

### Adding New Machines
1. Create `machines/new-hostname/` directory
2. Add `configuration.nix` and `hardware-configuration.nix`
3. Update `flake.nix` with new machine entry
4. Configure secrets access in `.sops.yaml`

### Creating New Modules
1. Create module file in appropriate subdirectory
2. Define options using `mkOption`
3. Implement functionality in `config` section
4. Import in relevant machine configurations

### Adding Services
1. Create service module in `services/`
2. Define service-specific options
3. Configure dependencies and security
4. Enable in machine configurations

## Performance Considerations

### Build Performance
- **Binary cache**: Uses cache.nixos.org and community caches
- **Distributed builds**: Large builds can use remote builders
- **Incremental builds**: Only changed components are rebuilt

### Runtime Performance  
- **Minimal systems**: Only necessary packages installed
- **Service optimization**: Resource limits and performance tuning
- **Storage efficiency**: Nix store deduplication saves space

## Monitoring and Observability

### System Health
- **Systemd status**: Service health monitoring
- **Log aggregation**: Centralized logging with journald
- **Performance metrics**: System resource monitoring

### Deployment Tracking
- **Git history**: All changes tracked in version control
- **Generation management**: Easy rollbacks to previous configurations
- **Build logs**: Detailed information about deployments

## Best Practices

### Configuration Organization
- Keep modules focused and single-purpose
- Use descriptive names for options and modules
- Document complex configurations with comments
- Separate machine-specific from reusable code

### Security Practices
- Regularly rotate secrets and keys
- Review firewall rules periodically  
- Keep systems updated with automatic updates
- Use principle of least privilege for services

### Maintenance
- Monitor disk usage (Nix store can grow large)
- Regular garbage collection of old generations
- Test deployments on non-critical machines first
- Keep backups of important persistent data

---

This architecture provides a solid foundation for managing complex, multi-machine infrastructure with Nix. The modular design makes it easy to adapt and extend for different use cases while maintaining security and reliability.
