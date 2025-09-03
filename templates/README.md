# Machine Templates

This directory contains templates for quickly setting up new machines with consistent configurations.

## Available Templates

### macOS Desktop (`macos-desktop/`)
For personal macOS machines with development tools and applications.

**Includes:**
- Homebrew package management
- Essential development tools (git, vs code, etc.)
- Personal applications (Discord, Obsidian, etc.)
- Home manager configuration

### NixOS Desktop (`nixos-desktop/`)
For personal Linux desktop/laptop machines.

**Includes:**
- Impermanence for security
- Home manager configuration
- Development tools
- SSH configuration

### Homelab Server (`homelab-server/`)
For servers running in your home network.

**Includes:**
- Impermanence for security
- Auto-updates
- Tailscale for remote access
- SSH hardening
- Optimized for server workloads

### VPS Server (`vps-server/`)
For cloud/VPS servers with additional security hardening.

**Includes:**
- All homelab server features
- Additional security hardening
- Unattended upgrades
- VPS-specific optimizations

## How to Add a New Machine

### Step 1: Copy Template
```bash
# For a new macOS machine called "studio"
cp -r templates/macos-desktop machines/studio

# For a new homelab server called "media"
cp -r templates/homelab-server machines/media

# For a new VPS called "web"
cp -r templates/vps-server machines/web
```

### Step 2: Customize Configuration
Edit `machines/YOUR_HOSTNAME/configuration.nix` and:
1. Replace all `CHANGEME` placeholders with actual values
2. Set the correct hostname
3. Enable/disable optional services as needed

For NixOS machines, also generate/update the hardware configuration:
```bash
# On the target machine, generate hardware config
nixos-generate-config --show-hardware-config > hardware-configuration.nix
# Then copy this to your repo
```

### Step 3: Add to Flake
Edit `flake.nix` and add your new machine to the appropriate section:

**For macOS machines:**
```nix
darwinConfigurations = {
  # ... existing machines ...
  studio = nix-darwin.lib.darwinSystem {
    system = "aarch64-darwin"; # or "x86_64-darwin"
    specialArgs = {inherit inputs outputs;};
    modules = [./machines/studio/configuration.nix];
  };
};
```

**For NixOS machines:**
```nix
nixosConfigurations = {
  # ... existing machines ...
  media = nixpkgs.lib.nixosSystem {
    system = "x86_64-linux";
    specialArgs = {inherit inputs outputs;};
    modules = [./machines/media/configuration.nix];
  };
};
```

### Step 4: Deploy
**For macOS:**
```bash
darwin-rebuild switch --flake .#studio
```

**For NixOS:**
```bash
nixos-rebuild switch --flake .#media
```

## Tips

- Always test your configuration with `--dry-run` first
- Keep machine-specific secrets in the `secrets/` directory
- Use meaningful hostnames that indicate the machine's purpose
- Consider using the naming pattern: `location-purpose` (e.g., `home-media`, `cloud-web`)