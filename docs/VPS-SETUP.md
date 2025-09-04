# NixOS VPS Setup Guide

This comprehensive guide covers setting up a NixOS-based Virtual Private Server (VPS) and integrating it with your doomlab infrastructure for self-hosted services and remote development.

## Prerequisites

- Credit card or payment method for VPS provider
- SSH key pair (we'll help you create one if needed)
- Local doomlab repository cloned and configured
- Basic familiarity with command line

## Step 1: Choose VPS Provider

### Recommended Providers

#### Hetzner Cloud (Recommended - Best Value)
- **Cost**: Starting at €3.79/month (CX11: 1 vCPU, 2GB RAM, 20GB SSD)
- **Locations**: Germany, Finland, USA
- **Features**: Excellent performance, IPv6, API access
- **NixOS Support**: Official NixOS images available

#### DigitalOcean
- **Cost**: Starting at $6/month (1 vCPU, 1GB RAM, 25GB SSD)
- **Locations**: Global presence
- **Features**: Extensive documentation, marketplace apps
- **NixOS Support**: Custom ISO upload required

#### Linode (Akamai)
- **Cost**: Starting at $5/month (1 vCPU, 1GB RAM, 25GB SSD)
- **Locations**: Global presence
- **Features**: Good performance, competitive pricing
- **NixOS Support**: Custom deployment needed

#### Vultr
- **Cost**: Starting at $2.50/month (1 vCPU, 512MB RAM, 10GB SSD)
- **Locations**: Global presence
- **Features**: Hourly billing, good API
- **NixOS Support**: Custom ISO upload supported

### Minimum Requirements
```
CPU: 1 vCPU (2+ recommended for builds)
RAM: 2GB minimum (4GB+ recommended)
Storage: 20GB minimum (50GB+ recommended)
Bandwidth: 1TB/month minimum
IPv4: Required
IPv6: Recommended
```

## Step 2: VPS Deployment Methods

### Method A: Hetzner with Official NixOS (Easiest)

#### Create Hetzner Account
1. Go to https://console.hetzner.cloud/
2. Sign up for new account
3. Add payment method
4. Create new project: "doomlab"

#### Deploy NixOS Server
1. **Click "Add Server"**
2. **Choose Location**: Closest to you or target users
3. **Choose Image**: "NixOS" (under Linux distributions)
4. **Choose Type**: CX21 (2 vCPU, 4GB RAM) recommended for builds
5. **Add SSH Key**:
   ```bash
   # Generate SSH key if you don't have one
   ssh-keygen -t ed25519 -C "your-email@example.com"
   
   # Copy public key
   cat ~/.ssh/id_ed25519.pub
   ```
   Paste the public key content into Hetzner console

6. **Name**: "doomlab-vps"
7. **Click "Create & Buy Now"**

#### Initial Connection
```bash
# Connect to your VPS (IP provided in Hetzner console)
ssh root@YOUR.VPS.IP.ADDRESS

# Update system
nixos-rebuild switch --upgrade
```

### Method B: Other Providers with nixos-infect

For providers without native NixOS support, use nixos-infect:

#### Deploy Base System
1. **Create server** with Ubuntu 20.04+ or Debian 11+
2. **Connect via SSH**:
   ```bash
   ssh root@YOUR.VPS.IP.ADDRESS
   ```

#### Install NixOS using nixos-infect
```bash
# Download and run nixos-infect
curl https://raw.githubusercontent.com/elitak/nixos-infect/master/nixos-infect | bash
```

**Wait 5-10 minutes** for the conversion to complete. The server will reboot automatically.

#### Reconnect to NixOS
```bash
# Server should now be running NixOS
ssh root@YOUR.VPS.IP.ADDRESS

# Verify NixOS installation
nixos-version
```

### Method C: Custom ISO Upload

For providers supporting custom ISO uploads:

1. **Download NixOS ISO**:
   ```bash
   # Get latest minimal ISO
   wget https://releases.nixos.org/nixos/24.11/nixos-minimal-24.11.latest-x86_64-linux.iso
   ```

2. **Upload ISO** via provider console
3. **Boot from ISO** and perform manual installation
4. Follow standard NixOS installation procedures

## Step 3: Initial Server Configuration

### Create User Account
```bash
# Still connected as root
# Create your user account
useradd -m -G wheel orther
passwd orther

# Add your SSH key
mkdir -p /home/orther/.ssh
cp ~/.ssh/authorized_keys /home/orther/.ssh/
chown -R orther:orther /home/orther/.ssh
chmod 700 /home/orther/.ssh
chmod 600 /home/orther/.ssh/authorized_keys

# Enable sudo for wheel group
echo "wheel ALL=(ALL) NOPASSWD: ALL" > /etc/sudoers.d/wheel
```

### Test User Connection
```bash
# From your local machine, test connection
ssh orther@YOUR.VPS.IP.ADDRESS
sudo ls  # Should work without password
```

## Step 4: Add VPS to Doomlab Configuration

### Create VPS Machine Configuration

1. **Create machine directory**:
   ```bash
   # On your local machine in doomlab repo
   cd ~/code/doomlab
   mkdir -p machines/vps
   ```

2. **Generate hardware configuration**:
   ```bash
   # On the VPS, generate hardware config
   sudo nixos-generate-config --show-hardware-config > /tmp/hardware-config.nix
   cat /tmp/hardware-config.nix
   ```

3. **Create hardware configuration file**:
   ```bash
   # Copy the output to your local machine
   cat > machines/vps/hardware-configuration.nix << 'EOF'
   # Paste the hardware configuration from the VPS here
   EOF
   ```

4. **Create main configuration**:
   ```bash
   cat > machines/vps/configuration.nix << 'EOF'
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
       ../../services/tailscale.nix
       inputs.home-manager.nixosModules.home-manager
       inputs.sops-nix.nixosModules.sops
     ];

     # System configuration
     networking.hostName = "doomlab-vps";
     time.timeZone = "UTC";  # Or your preferred timezone

     # User configuration  
     users.users.orther = {
       isNormalUser = true;
       extraGroups = ["wheel" "docker"];
       openssh.authorizedKeys.keys = [
         "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAI... your-key-here"
       ];
     };

     # SSH hardening
     services.openssh = {
       enable = true;
       settings = {
         PasswordAuthentication = false;
         PermitRootLogin = "no";
         X11Forwarding = false;
         MaxAuthTries = 3;
       };
       allowSFTP = false;
     };

     # Firewall configuration
     networking.firewall = {
       enable = true;
       allowedTCPPorts = [ 22 80 443 ];  # SSH, HTTP, HTTPS
       allowedUDPPorts = [ ];
       interfaces = {
         tailscale0 = {
           allowedTCPPorts = [ 22 ];  # Allow SSH over Tailscale
         };
       };
     };

     # Security hardening
     security = {
       sudo.wheelNeedsPassword = false;
       auditd.enable = true;
       apparmor.enable = true;
     };

     # Automatic updates
     system.autoUpgrade = {
       enable = true;
       flake = "github:orther/doomlab";
       flags = [
         "--update-input"
         "nixpkgs"
         "--no-write-lock-file"
         "-L" # print build logs
       ];
       dates = "02:00";
       randomizedDelaySec = "45min";
     };

     # Garbage collection
     nix.gc = {
       automatic = true;
       dates = "weekly";
       options = "--delete-older-than 30d";
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

### Add to Flake Configuration

1. **Edit flake.nix**:
   ```bash
   nano flake.nix
   ```

2. **Add VPS to nixosConfigurations**:
   ```nix
   nixosConfigurations = {
     # ... existing configurations ...
     vps = nixpkgs.lib.nixosSystem {
       system = "x86_64-linux";
       specialArgs = {inherit inputs outputs;};
       modules = [./machines/vps/configuration.nix];
     };
   };
   ```

## Step 5: Deploy to VPS

### Initial Deployment
```bash
# From your local machine
just deploy vps YOUR.VPS.IP.ADDRESS
```

This will:
- Build the configuration locally
- Copy it to the VPS
- Apply the new configuration
- Set up all services and security hardening

### Verify Deployment
```bash
# Check system status
ssh orther@YOUR.VPS.IP.ADDRESS
systemctl status
free -h
df -h
```

## Step 6: Security Hardening

### Fail2Ban Setup
Add fail2ban for additional security:

```bash
# Add to your VPS configuration
cat >> machines/vps/configuration.nix << 'EOF'

  # Intrusion prevention
  services.fail2ban = {
    enable = true;
    maxretry = 3;
    ignoreIP = [
      "127.0.0.0/8"
      "10.0.0.0/8"
      "172.16.0.0/12"
      "192.168.0.0/16"
    ];
    bantime = "1h";
    bantime-increment = {
      enable = true;
      multipliers = "1 2 4 8 16 32 64";
      maxtime = "168h";
      overalljails = true;
    };
  };
EOF
```

### Monitoring Setup
Add basic monitoring:

```bash
# Add monitoring to VPS configuration
cat >> machines/vps/configuration.nix << 'EOF'

  # System monitoring
  services.prometheus.exporters = {
    node = {
      enable = true;
      enabledCollectors = ["systemd"];
      port = 9100;
    };
  };

  # Log monitoring
  services.journalbeat = {
    enable = true;
    extraConfig = ''
      journalbeat.inputs:
      - paths: ["/var/log/journal"]
    '';
  };
EOF
```

### Redeploy with Security Features
```bash
just deploy vps YOUR.VPS.IP.ADDRESS
```

## Step 7: Service Configuration

### Web Server Setup (Caddy)
```bash
# Add web server to VPS config
cat >> machines/vps/configuration.nix << 'EOF'

  # Web server
  services.caddy = {
    enable = true;
    virtualHosts."your-domain.com" = {
      extraConfig = ''
        root * /var/www/html
        file_server
        
        # Security headers
        header {
          # Enable HSTS
          Strict-Transport-Security max-age=31536000;
          # Prevent MIME sniffing
          X-Content-Type-Options nosniff
          # Clickjacking protection
          X-Frame-Options DENY
          # XSS protection
          X-XSS-Protection "1; mode=block"
        }
      '';
    };
  };

  # Open HTTP/HTTPS ports
  networking.firewall.allowedTCPPorts = [ 80 443 ];
EOF
```

### Database Setup (PostgreSQL)
```bash
# Add PostgreSQL to VPS config
cat >> machines/vps/configuration.nix << 'EOF'

  # Database
  services.postgresql = {
    enable = true;
    package = pkgs.postgresql_15;
    ensureDatabases = [ "myapp" ];
    ensureUsers = [
      {
        name = "orther";
        ensureDBOwnership = true;
      }
    ];
    authentication = ''
      local all all trust
      host all all 127.0.0.1/32 trust
      host all all ::1/128 trust
    '';
  };
EOF
```

### Container Runtime (Docker)
```bash
# Add Docker to VPS config
cat >> machines/vps/configuration.nix << 'EOF'

  # Container runtime
  virtualisation.docker = {
    enable = true;
    enableOnBoot = true;
    autoPrune = {
      enable = true;
      dates = "weekly";
    };
  };
EOF
```

## Step 8: Domain and DNS Setup

### Domain Configuration
1. **Purchase domain** from registrar (Cloudflare, Namecheap, etc.)
2. **Configure DNS records**:
   ```
   A     @           YOUR.VPS.IP.ADDRESS
   A     www         YOUR.VPS.IP.ADDRESS  
   AAAA  @           YOUR.VPS.IPv6.ADDRESS (if available)
   ```

### SSL Certificate (Automatic with Caddy)
Caddy automatically obtains Let's Encrypt certificates when:
- Domain points to your VPS
- Port 80/443 are open
- Valid email in configuration

## Step 9: Backup Strategy

### Automated Backups
```bash
# Add backup configuration
cat >> machines/vps/configuration.nix << 'EOF'

  # Backup service
  services.borgbackup.jobs.vps-backup = {
    paths = [
      "/home"
      "/var/lib"
      "/etc/nixos"
    ];
    exclude = [
      "*/tmp"
      "*/.cache"
      "*/node_modules"
    ];
    repo = "/backup/borg-repo";
    encryption.mode = "repokey-blake2";
    compression = "auto,zstd";
    startAt = "daily";
    prune.keep = {
      daily = 7;
      weekly = 4;  
      monthly = 12;
    };
  };
EOF
```

### Off-site Backup (Optional)
Configure backup to external service:
- **Backblaze B2**: Cost-effective cloud storage
- **AWS S3**: Enterprise-grade with Glacier archival
- **Hetzner Storage Box**: Included with some plans

## Step 10: Monitoring and Maintenance

### Health Check Script
```bash
# Create health check script
cat > /usr/local/bin/vps-health-check << 'EOF'
#!/usr/bin/env bash
set -euo pipefail

echo "=== VPS Health Check ===" 
echo "Date: $(date)"
echo "Uptime: $(uptime)"
echo "Memory: $(free -h)"
echo "Disk: $(df -h /)"
echo "Load: $(cat /proc/loadavg)"
echo "Failed services: $(systemctl --failed --no-legend | wc -l)"
EOF

chmod +x /usr/local/bin/vps-health-check
```

### Automated Monitoring
```bash
# Add monitoring timer
cat >> machines/vps/configuration.nix << 'EOF'

  # Health monitoring
  systemd.services.vps-health-check = {
    description = "VPS Health Check";
    serviceConfig = {
      Type = "oneshot";
      ExecStart = "/usr/local/bin/vps-health-check";
      User = "root";
    };
  };

  systemd.timers.vps-health-check = {
    description = "Run VPS Health Check";
    wantedBy = [ "timers.target" ];
    timerConfig = {
      OnCalendar = "hourly";
      Persistent = true;
    };
  };
EOF
```

## Troubleshooting

### Common Issues

#### Connection Issues
```bash
# Check SSH connectivity
ssh -v orther@YOUR.VPS.IP.ADDRESS

# Check firewall status
sudo ufw status  # If using ufw
sudo iptables -L # Check iptables directly
```

#### Deployment Failures
```bash
# Check build locally first
nix build .#nixosConfigurations.vps.config.system.build.toplevel

# Test configuration
just test-machine vps

# Force rebuild on VPS
ssh orther@YOUR.VPS.IP.ADDRESS
sudo nixos-rebuild switch --show-trace
```

#### Service Issues
```bash
# Check service status
systemctl status service-name
journalctl -u service-name -f

# Restart services
sudo systemctl restart service-name
```

### Resource Monitoring
```bash
# Monitor resources
htop                    # Interactive process viewer
iostat 1               # I/O statistics  
iotop                  # I/O by process
nethogs                # Network usage by process
```

## Cost Optimization

### Monitoring Costs
- Set billing alerts with your provider
- Monitor resource usage regularly
- Use `just resource-summary` for system metrics

### Resource Optimization
```bash
# Optimize Nix store
nix store optimize --verbose

# Clean up container images
docker system prune -a

# Monitor disk usage
ncdu /                 # Interactive disk usage analyzer
```

## Scaling and Advanced Features

### Load Balancing
For high availability, consider:
- Multiple VPS instances
- Load balancer (HAProxy, nginx)
- Database replication

### Container Orchestration
Advanced setups might include:
- Kubernetes (k3s for lightweight)
- Docker Swarm
- Nomad

### Infrastructure as Code
Extend with:
- Terraform for provider management
- Ansible for additional automation
- Monitoring stack (Prometheus, Grafana)

## Useful Commands

```bash
# VPS Management
just deploy vps IP              # Deploy configuration
just test-machine vps           # Test configuration
ssh orther@YOUR.VPS.IP.ADDRESS  # Connect to VPS

# System Maintenance
sudo nixos-rebuild switch       # Apply config changes
systemctl status               # Check all services
journalctl -f                  # View live logs
nix-collect-garbage -d         # Clean up old generations

# Monitoring
htop                          # Process monitor
df -h                         # Disk usage
free -h                       # Memory usage
ss -tuln                      # Network connections
```

Your NixOS VPS is now fully configured, secure, and integrated with the doomlab infrastructure!