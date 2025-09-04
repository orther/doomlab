# Fresh macOS Install - Mac Studio Ultra (Apple Silicon)

This guide provides step-by-step instructions for setting up doomlab on a fresh Mac Studio Ultra running Apple Silicon (M1/M2 processors).

## Prerequisites

- Fresh macOS installation (Ventura 13.0+ or Sonoma 14.0+ recommended)
- Administrative privileges
- Internet connection
- Apple ID for App Store (if using GUI applications)

## Step 1: Initial macOS Setup

### Complete macOS Setup Assistant
1. **Language and Region**: Set your preferred language and region
2. **User Account**: Create admin account (recommend username: `orther` to match doomlab config)
3. **Apple ID**: Sign in or skip (can be done later)
4. **Screen Time**: Skip or configure as preferred
5. **Siri**: Enable or disable as preferred

### Enable Development Features
1. **Open Terminal** (Applications → Utilities → Terminal)
2. **Install Xcode Command Line Tools**:
   ```bash
   xcode-select --install
   ```
   - Click "Install" when prompted
   - Wait for installation to complete (5-10 minutes)

## Step 2: Automated Doomlab Installation (Recommended)

The doomlab project provides a one-liner installer that handles everything automatically:

### Quick Install
```bash
# Run the automated installer
bash -c "$(curl -fsSL https://raw.githubusercontent.com/orther/doomlab/main/install.sh)"
```

**What this does:**
1. Installs Nix using the Determinate Systems installer (optimized for Apple Silicon)
2. Clones the doomlab repository to `~/code/doomlab`
3. Applies the macOS configuration for your system
4. Sets up Home Manager for user dotfiles and applications
5. Configures shell environment

### Post-Installation
After the installer completes:

1. **Restart Terminal** to load new environment
2. **Verify installation**:
   ```bash
   # Check Nix installation
   nix --version
   
   # Check doomlab installation
   cd ~/code/doomlab
   just --list
   ```

## Step 3: Manual Installation (Advanced Users)

If you prefer manual control or the automated installer fails:

### Install Nix
```bash
# Install Nix with flakes and nix-command enabled
curl --proto '=https' --tlsv1.2 -sSf -L https://install.determinate.systems/nix | sh -s -- install
```

### Source Nix Environment
```bash
# Restart terminal or source the profile
source /nix/var/nix/profiles/default/etc/profile.d/nix-daemon.sh
```

### Clone Doomlab Repository
```bash
# Create code directory and clone repo
mkdir -p ~/code
cd ~/code
git clone https://github.com/orther/doomlab.git
cd doomlab
```

### Install Just Task Runner
```bash
# Install just for task management
nix profile install nixpkgs#just
```

## Step 4: Configure Stud Machine

### Update Machine Configuration
1. **Review stud configuration**:
   ```bash
   cat machines/stud/configuration.nix
   ```

2. **Update hardware configuration if needed**:
   ```bash
   # Check current hardware
   system_profiler SPHardwareDataType
   
   # Edit hardware config if needed
   nano machines/stud/hardware-configuration.nix
   ```

### Customize Configuration
Edit the stud configuration to match your preferences:

```bash
# Open stud configuration
nano machines/stud/configuration.nix
```

Key areas to customize:
- **Hostname**: Change if you want a different name
- **Home Manager modules**: Add/remove applications and configurations
- **Services**: Enable/disable system services

## Step 5: Deploy Configuration

### Initial Deployment
```bash
# Deploy the stud configuration
just deploy macos
```

This will:
- Apply all system-level configurations
- Install and configure applications via Home Manager
- Set up dotfiles and shell environment
- Configure macOS system preferences

### Verify Deployment
```bash
# Check system configuration
darwin-rebuild --version

# Verify Home Manager
home-manager --version

# List installed packages
nix profile list
```

## Step 6: Application Setup

### GUI Applications
The doomlab configuration uses a hybrid approach:
- **System packages**: Installed via Nix
- **GUI applications**: Managed via Homebrew integration

Common applications included:
- **Development**: VSCode, Docker Desktop, UTM
- **Productivity**: 1Password, Alfred, Rectangle
- **Communication**: Discord, Slack, Zoom
- **Media**: VLC, IINA

### Development Environment
After deployment, you'll have:
- **Shell**: Zsh with Oh My Zsh
- **Terminal**: Alacritty (configured)
- **Editor**: Neovim with custom configuration
- **Git**: Pre-configured with common aliases
- **SSH**: Key management setup

## Step 7: macOS System Preferences

### Security & Privacy
1. **Full Disk Access**: Grant to Terminal and development tools
2. **Developer Tools**: Allow unsigned applications if needed
3. **Firewall**: Configure as needed for development

### System Preferences
The doomlab configuration handles many system preferences automatically:
- **Dock**: Configured for development workflow
- **Mission Control**: Optimized settings
- **Keyboard**: Development-friendly shortcuts
- **Trackpad**: Enhanced gestures

## Step 8: Additional Configuration

### SSH Key Setup
```bash
# Generate SSH key if needed
ssh-keygen -t ed25519 -C "your-email@example.com"

# Add to SSH agent
ssh-add ~/.ssh/id_ed25519

# Copy public key for GitHub/servers
pbcopy < ~/.ssh/id_ed25519.pub
```

### Git Configuration
```bash
# Configure Git (if not already done)
git config --global user.name "Your Name"
git config --global user.email "your-email@example.com"
```

### Development Directories
```bash
# Create standard development directories
mkdir -p ~/code
mkdir -p ~/projects
mkdir -p ~/workspace
```

## Apple Silicon Specific Optimizations

### Rosetta 2 (If Needed)
Some tools may require Rosetta 2 for x86_64 compatibility:
```bash
# Install Rosetta 2 if needed
sudo softwareupdate --install-rosetta
```

### Performance Settings
The doomlab configuration includes optimizations for Apple Silicon:
- **Memory management**: Optimized for unified memory
- **CPU scheduling**: Apple Silicon specific settings
- **Power management**: Balanced performance/battery

## Troubleshooting

### Common Issues

#### Nix Installation Fails
```bash
# Clean previous installation attempts
sudo rm -rf /etc/nix /nix ~/.nix*

# Try installation again
curl --proto '=https' --tlsv1.2 -sSf -L https://install.determinate.systems/nix | sh -s -- install
```

#### Permission Issues
```bash
# Fix Nix store permissions
sudo chown -R root:nixbld /nix
sudo chmod 1775 /nix/store
```

#### Home Manager Errors
```bash
# Rebuild Home Manager configuration
home-manager switch --flake .#orther@stud
```

#### Application Installation Issues
```bash
# Update Homebrew and retry
brew update && brew upgrade

# Force reinstall problematic apps
brew reinstall --cask application-name
```

### Getting Help
- Check logs: `journalctl -u nix-daemon`
- Nix community: [Discourse](https://discourse.nixos.org/)
- Doomlab issues: [GitHub Issues](https://github.com/orther/doomlab/issues)

## System Maintenance

### Regular Updates
```bash
# Update flake inputs
just up

# Apply updates
just deploy macos

# Cleanup old generations
nix-collect-garbage -d
```

### Backup Important Data
Consider backing up:
- SSH keys (`~/.ssh/`)
- Personal projects (`~/code/`, `~/projects/`)
- Application data (varies by app)

## Customization

### Adding Applications
1. **Edit Home Manager configuration**:
   ```bash
   nano modules/home-manager/macos.nix
   ```

2. **Add to homebrew casks**:
   ```nix
   homebrew.casks = [
     "new-application"
   ];
   ```

3. **Deploy changes**:
   ```bash
   just deploy macos
   ```

### Modifying System Settings
1. **Edit macOS base configuration**:
   ```bash
   nano modules/macos/base.nix
   ```

2. **Apply changes**:
   ```bash
   just deploy macos
   ```

## Performance Verification

### System Resources
```bash
# Check memory usage
memory_pressure

# Check CPU usage
top -n 5

# Check disk usage
df -h
```

### Nix Store Health
```bash
# Check store integrity
nix store verify --all

# Store statistics
du -sh /nix/store
```

## Mac Studio Ultra Specific Tips

### Utilize Maximum Performance
- **Memory**: Take advantage of unified memory architecture
- **Storage**: Use high-speed SSD for Nix store
- **CPU**: Multi-core builds are automatically optimized

### Thermal Management
- **Monitoring**: System automatically manages thermals
- **Workloads**: Heavy Nix builds utilize full CPU safely

## Next Steps

1. **Explore doomlab features**:
   ```bash
   just --list  # See all available commands
   ```

2. **Set up development environment** for your preferred languages

3. **Configure additional services** as needed

4. **Join the community** and contribute improvements

Your Mac Studio Ultra is now fully configured with doomlab and ready for development!