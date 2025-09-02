# Setup Guide

This guide walks through setting up the doomlab configuration from scratch, including prerequisites and troubleshooting common issues.

## Prerequisites

Before starting, ensure you have:
- **Admin/sudo privileges** on your machine
- **Git** installed (comes with macOS dev tools, included in most Linux distros)
- **Basic terminal knowledge** (navigating directories, running commands)
- **Stable internet connection** for downloading packages

## Step-by-Step Installation

### 1. Quick Install (Recommended)

The fastest way to get started:

```bash
bash -c "$(curl -fsSL https://raw.githubusercontent.com/orther/doomlab/main/install.sh)"
```

**What this script does:**
1. Detects your platform (macOS, Linux, WSL)
2. Installs Nix using the Determinate Systems installer
3. Enables flakes and experimental features
4. Clones this repository to `~/doomlab`
5. Applies the appropriate configuration for your machine

### 2. Manual Installation

If you prefer more control or the quick install fails:

#### Step 1: Install Nix

```bash
# Use the Determinate Systems installer (recommended)
curl --proto '=https' --tlsv1.2 -sSf -L https://install.determinate.systems/nix | sh -s -- install
```

#### Step 2: Enable Flakes

Add to `~/.config/nix/nix.conf` (create if doesn't exist):
```
experimental-features = nix-command flakes
```

#### Step 3: Clone Repository

```bash
git clone https://github.com/orther/doomlab.git ~/doomlab
cd ~/doomlab
```

#### Step 4: Apply Configuration

```bash
# macOS
darwin-rebuild switch --flake .#macos

# NixOS (replace 'hostname' with your machine name)
sudo nixos-rebuild switch --flake .#hostname
```

## Platform-Specific Setup

### macOS Additional Steps

1. **Grant Terminal Full Disk Access**:
   - System Preferences → Security & Privacy → Privacy → Full Disk Access
   - Add your terminal application (Terminal.app, iTerm2, etc.)

2. **Install Command Line Tools** (if not already installed):
   ```bash
   xcode-select --install
   ```

3. **First deployment** may take 10-15 minutes as it downloads and compiles packages.

### NixOS Custom Machine Setup

To use this configuration on your own hardware:

1. **Create your machine configuration**:
   ```bash
   mkdir machines/your-hostname
   cp machines/noir/configuration.nix machines/your-hostname/
   cp machines/noir/hardware-configuration.nix machines/your-hostname/
   ```

2. **Update hardware configuration**:
   ```bash
   # Generate hardware config for your machine
   sudo nixos-generate-config --show-hardware-config > machines/your-hostname/hardware-configuration.nix
   ```

3. **Add to flake.nix**:
   ```nix
   nixosConfigurations = {
     # ... existing configs
     your-hostname = lib.nixosSystem {
       inherit system;
       modules = [ ./machines/your-hostname ];
       specialArgs = { inherit inputs outputs; };
     };
   };
   ```

4. **Configure secrets** (see [Secrets Management](SECRETS.md))

### WSL Additional Setup

1. **Enable WSL Features**:
   ```powershell
   # Run in PowerShell as Administrator
   dism.exe /online /enable-feature /featurename:Microsoft-Windows-Subsystem-Linux /all /norestart
   dism.exe /online /enable-feature /featurename:VirtualMachinePlatform /all /norestart
   ```

2. **Set WSL 2 as default**:
   ```powershell
   wsl --set-default-version 2
   ```

3. **Import the tarball** (download from [releases](https://github.com/orther/doomlab/releases)):
   ```powershell
   wsl --import NixOS $env:USERPROFILE\NixOS\ nixos-wsl.tar.gz
   ```

## Post-Installation

### 1. Verify Installation

```bash
# Check Nix is working
nix --version

# Check flakes are enabled
nix flake metadata github:NixOS/nixpkgs

# List available commands
just --list
```

### 2. Test Deployment

```bash
# Make a small change and test deployment
just deploy macos        # macOS
just deploy your-machine # NixOS
```

### 3. Set Up Development Environment

```bash
# Update to latest packages
just up

# Install development tools (optional)
nix-shell -p statix alejandra sops
```

## First Steps After Installation

### Understanding the System

1. **Explore the structure**:
   ```bash
   ls -la ~/doomlab
   cat ~/doomlab/flake.nix  # Main configuration entry point
   ```

2. **Check your machine config**:
   ```bash
   # macOS
   ls ~/doomlab/machines/macos/
   
   # NixOS
   ls ~/doomlab/machines/your-hostname/
   ```

3. **Review available services**:
   ```bash
   ls ~/doomlab/services/
   ```

### Making Your First Changes

1. **Edit your machine config**:
   ```bash
   # Add packages to your system
   $EDITOR ~/doomlab/machines/your-machine/configuration.nix
   ```

2. **Deploy changes**:
   ```bash
   just deploy your-machine
   ```

3. **Check the result**:
   ```bash
   # New packages should be available immediately
   which neovim
   ```

## Customization

### Adding Packages

**System-wide packages** (available to all users):
```nix
# In machines/your-machine/configuration.nix
environment.systemPackages = with pkgs; [
  vim
  git
  curl
];
```

**User packages** (via home-manager):
```nix
# In machines/your-machine/home.nix
home.packages = with pkgs; [
  firefox
  discord
  vscode
];
```

### Adding Services

1. **Enable existing services**:
   ```nix
   # In machines/your-machine/configuration.nix
   imports = [
     ../../services/tailscale.nix
     ../../services/nextcloud.nix
   ];
   ```

2. **Configure service-specific options**:
   ```nix
   services.tailscale.enable = true;
   services.nextcloud.enable = true;
   ```

### Secrets Management

See the dedicated [Secrets Management Guide](SECRETS.md) for complete setup instructions.

## Performance Tips

### First Deployment

- **macOS**: First deployment takes 10-15 minutes
- **NixOS**: First deployment takes 5-30 minutes depending on hardware
- **Subsequent deployments**: Usually 1-5 minutes

### Optimizations

1. **Enable binary cache**:
   ```nix
   nix.settings = {
     substituters = [
       "https://cache.nixos.org/"
       "https://nix-community.cachix.org"
     ];
     trusted-public-keys = [
       "cache.nixos.org-1:6NCHdD59X431o0gWypbMrAURkbJ16ZPMQFGspcDShjY="
       "nix-community.cachix.org-1:mB9FSh9qf2dCimDSUo8Zy7bkq5CX+/rkCWyvRCYg3Fs="
     ];
   };
   ```

2. **Use local builds for small changes**:
   ```bash
   # Skip downloading substitutes for small configs
   just deploy --option substitute false your-machine
   ```

## Next Steps

1. **Read the [Architecture Guide](ARCHITECTURE.md)** to understand the system design
2. **Set up secrets** with the [Secrets Management Guide](SECRETS.md)  
3. **Customize your configuration** by exploring the `machines/` and `services/` directories
4. **Join the community** by opening [discussions](https://github.com/orther/doomlab/discussions)

## Getting Help

- **Common issues**: Check [Troubleshooting](TROUBLESHOOTING.md)
- **Questions**: Open a [discussion](https://github.com/orther/doomlab/discussions)
- **Bugs**: Report an [issue](https://github.com/orther/doomlab/issues)
- **Learning resources**: See main [README](../README.md#-learning-resources)