# NixOS VM Setup on Mac Studio Ultra

This guide walks you through setting up a NixOS virtual machine on your Mac Studio Ultra and integrating it with the doomlab infrastructure.

## Prerequisites

- Mac Studio Ultra with sufficient resources (recommend 8GB+ RAM for VM)
- Administrative privileges on your macOS system
- Internet connection for downloads

## Step 1: Choose VM Software

### Option A: UTM (Recommended - Free)

UTM is the recommended free virtualization solution for Apple Silicon and Intel Macs.

1. **Download UTM:**
   ```bash
   # Install via Homebrew (easiest)
   brew install --cask utm
   
   # Or download directly from https://mac.getutm.app/
   ```

2. **Launch UTM** from Applications folder

### Option B: Parallels Desktop (Paid - Best Performance)

If you already have Parallels Desktop:

1. Open Parallels Desktop
2. Go to File → New to create a new VM

### Option C: VMware Fusion (Paid Alternative)

1. Download VMware Fusion from VMware website
2. Install and launch VMware Fusion

## Step 2: Get NixOS ISO

You have two options for getting the NixOS ISO:

### Option A: Use Doomlab Custom ISO (Recommended)

The doomlab project can build a custom ISO with your SSH keys pre-configured:

1. **Clone the doomlab repository** (if you haven't already):
   ```bash
   cd ~/code
   git clone https://github.com/orther/doomlab.git
   cd doomlab
   ```

2. **Build custom ISO:**
   ```bash
   # Traditional method
   just build-iso
   
   # Or using Dagger (modern method)
   just build-iso-dagger
   ```

3. **Locate the ISO:**
   ```bash
   # Traditional build - ISO will be in result/ directory
   ls -la result/iso/
   
   # Dagger build - ISO will be named nixos.iso
   ls -la nixos.iso
   ```

### Option B: Download Official NixOS ISO

1. Go to https://nixos.org/download.html
2. Download the **Minimal ISO** for x86_64-linux
3. Save to your Downloads folder

## Step 3: Create VM in UTM

### VM Configuration

1. **Start VM Creation:**
   - Click "Create a New Virtual Machine"
   - Select "Virtualize"

2. **Operating System:**
   - Select "Linux"
   - Click "Use ISO Image"
   - Browse and select your NixOS ISO file

3. **Hardware Configuration:**
   ```
   RAM: 4GB minimum, 8GB recommended
   CPU: 4 cores recommended
   Storage: 50GB minimum, 100GB recommended
   ```

4. **Network:**
   - Leave default (Shared Network)
   - This allows internet access and SSH from host

5. **Name your VM:**
   ```
   Name: doomlab-vm
   ```

## Step 4: Install NixOS

1. **Start the VM:**
   - Click the Play button in UTM
   - VM should boot to NixOS installer

2. **Initial Setup:**
   ```bash
   # Set root password for installation
   sudo passwd root
   
   # Enable SSH for remote access during install
   sudo systemctl start sshd
   
   # Find VM's IP address
   ip addr show
   ```

3. **Partition the disk:**
   ```bash
   # List available disks
   lsblk
   
   # Partition the disk (assuming /dev/sda)
   sudo fdisk /dev/sda
   # Create new partition table (g for GPT)
   # Create EFI partition (n, default, default, +512M, t, 1)
   # Create root partition (n, default, default, default)
   # Write changes (w)
   ```

4. **Format partitions:**
   ```bash
   # Format EFI partition
   sudo mkfs.fat -F 32 /dev/sda1
   
   # Format root partition
   sudo mkfs.ext4 /dev/sda2
   ```

5. **Mount filesystems:**
   ```bash
   # Mount root
   sudo mount /dev/sda2 /mnt
   
   # Create EFI directory and mount
   sudo mkdir -p /mnt/boot
   sudo mount /dev/sda1 /mnt/boot
   ```

6. **Generate configuration:**
   ```bash
   # Generate hardware configuration
   sudo nixos-generate-config --root /mnt
   ```

## Step 5: Configure for Doomlab Integration

1. **Create machine directory:**
   ```bash
   # On your Mac (in another terminal)
   cd ~/code/doomlab
   mkdir -p machines/vm
   ```

2. **Copy generated hardware config:**
   ```bash
   # From the VM
   cat /mnt/etc/nixos/hardware-configuration.nix
   ```

3. **Create VM configuration on your Mac:**
   ```bash
   # Create configuration.nix
   cat > machines/vm/configuration.nix << 'EOF'
   {
     config,
     lib,
     pkgs,
     inputs,
     outputs,
     ...
   }: {
     imports = [
       ./hardware-configuration.nix
       ../../modules/nixos/base.nix
       inputs.home-manager.nixosModules.home-manager
     ];
   
     # System configuration
     networking.hostName = "doomlab-vm";
     time.timeZone = "America/Los_Angeles";
   
     # User configuration
     users.users.orther = {
       isNormalUser = true;
       extraGroups = ["wheel" "networkmanager"];
       openssh.authorizedKeys.keys = [
         # Add your SSH public key here
         "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAI... your-key-here"
       ];
     };
   
     # SSH configuration
     services.openssh = {
       enable = true;
       settings.PasswordAuthentication = false;
       settings.PermitRootLogin = "no";
     };
   
     # Home Manager
     home-manager = {
       extraSpecialArgs = {inherit inputs outputs;};
       users.orther = import ../../modules/home-manager/nixos.nix;
     };
   
     system.stateVersion = "24.11";
   }
   EOF
   ```

4. **Copy hardware configuration:**
   ```bash
   # Create hardware-configuration.nix with the content from the VM
   cat > machines/vm/hardware-configuration.nix << 'EOF'
   # Paste the content from /mnt/etc/nixos/hardware-configuration.nix here
   EOF
   ```

## Step 6: Add VM to Flake Configuration

1. **Edit flake.nix:**
   ```bash
   # Add VM to nixosConfigurations section
   # Find the nixosConfigurations = { section and add:
   ```

2. **Add the VM configuration:**
   ```nix
   vm = nixpkgs.lib.nixosSystem {
     system = "x86_64-linux";
     specialArgs = {inherit inputs outputs;};
     modules = [./machines/vm/configuration.nix];
   };
   ```

## Step 7: Deploy to VM

1. **Initial installation from VM:**
   ```bash
   # From inside the VM, install with basic config
   sudo nixos-install
   
   # Reboot
   sudo reboot
   ```

2. **Deploy doomlab configuration:**
   ```bash
   # From your Mac, deploy to the VM
   just deploy vm 192.168.XX.XX  # Use VM's IP address
   ```

3. **Test the deployment:**
   ```bash
   # Test the configuration
   just test-machine vm
   ```

## Step 8: VM Network Configuration

### Enable SSH Access from Host

1. **In UTM, configure port forwarding:**
   - VM Settings → Network → Advanced
   - Add port forwarding: Host port 2222 → Guest port 22

2. **SSH from your Mac:**
   ```bash
   ssh -p 2222 orther@localhost
   ```

### Static IP Configuration (Optional)

For easier access, configure a static IP:

1. **Edit VM network configuration:**
   ```nix
   networking = {
     interfaces.enp0s1.ipv4.addresses = [{
       address = "192.168.100.10";
       prefixLength = 24;
     }];
     defaultGateway = "192.168.100.1";
     nameservers = ["1.1.1.1" "8.8.8.8"];
   };
   ```

## Performance Optimization

### For Mac Studio Ultra

1. **VM Settings Optimization:**
   ```
   CPU: 8 cores (max 12 for Ultra)
   RAM: 16GB (adjust based on your system)
   GPU: Metal acceleration enabled
   ```

2. **Enable hardware acceleration:**
   ```nix
   # In your VM configuration
   hardware.opengl.enable = true;
   ```

## Troubleshooting

### VM Won't Boot
- Verify ISO integrity
- Check VM has sufficient RAM (4GB minimum)
- Ensure virtualization is enabled

### Network Issues
- Check UTM network settings
- Verify SSH service is running: `sudo systemctl status sshd`
- Check firewall settings

### Deployment Failures
- Verify SSH key configuration
- Check network connectivity: `ping 8.8.8.8`
- Test with: `just test-machine vm`

### Build Issues
```bash
# Clear cache and rebuild
nix-collect-garbage -d
just deploy vm
```

## Integration with Doomlab Services

Once your VM is running, you can:

1. **Add services:**
   ```nix
   # In machines/vm/configuration.nix
   imports = [
     ../../services/tailscale.nix
     ../../services/monitoring.nix
   ];
   ```

2. **Configure secrets:**
   ```bash
   # Add VM to SOPS configuration
   just secrets-edit
   ```

3. **Set up monitoring:**
   ```nix
   services.prometheus.exporters.node.enable = true;
   ```

## Next Steps

- Configure additional services as needed
- Set up backups for important data
- Consider VM snapshots before major changes
- Integrate with your existing doomlab infrastructure

## Useful Commands

```bash
# VM management
just deploy vm IP_ADDRESS     # Deploy configuration
just test-machine vm          # Test configuration
just build-iso               # Build custom ISO

# Inside VM
sudo nixos-rebuild switch    # Apply local changes
systemctl status service     # Check service status
journalctl -u service        # View logs
```

Your NixOS VM is now ready and integrated with the doomlab infrastructure!