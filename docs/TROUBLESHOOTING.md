# Troubleshooting Guide

Common issues and solutions when working with the doomlab configuration.

## Installation Issues

### Nix Installation Fails

**Error**: `curl: command not found` or installer script fails

**Solutions**:
```bash
# On macOS - install command line tools first
xcode-select --install

# On Linux - install curl
sudo apt install curl    # Debian/Ubuntu
sudo dnf install curl    # Fedora
sudo pacman -S curl      # Arch

# Try alternative installer
sh <(curl -L https://nixos.org/nix/install) --daemon
```

**Error**: "Permission denied" during installation

**Solutions**:
```bash
# Ensure you have sudo privileges
sudo -v

# For macOS, grant Full Disk Access to Terminal
# System Preferences → Security & Privacy → Full Disk Access
```

### Flake Evaluation Errors

**Error**: `error: experimental Nix feature 'flakes' is disabled`

**Solution**:
```bash
# Enable flakes system-wide
echo "experimental-features = nix-command flakes" | sudo tee -a /etc/nix/nix.conf

# Or user-specific
mkdir -p ~/.config/nix
echo "experimental-features = nix-command flakes" > ~/.config/nix/nix.conf

# Restart Nix daemon
sudo systemctl restart nix-daemon  # Linux
sudo launchctl kickstart -k system/org.nixos.nix-daemon  # macOS
```

**Error**: `error: getting status of '/nix/store/...': No such file or directory`

**Solution**:
```bash
# Clear evaluation cache
nix flake update --refresh

# Or rebuild with fresh evaluation
just deploy --refresh your-machine
```

## Deployment Issues

### Build Failures

**Error**: Package fails to build or compile

**Solutions**:
```bash
# Check specific build logs
nix log /nix/store/failed-package

# Try with verbose output
just deploy --verbose your-machine

# Use substituters to avoid building
nix-build --option substitute true
```

**Error**: `error: builder for '/nix/store/...' failed with exit code 1`

**Solutions**:
```bash
# Identify the failing package
nix show-derivation /nix/store/failing-derivation

# Try building individually  
nix build nixpkgs#failing-package

# Check for system-specific issues
nix-info -m
```

### Permission Errors

**Error**: `Permission denied` during deployment

**Solutions**:
```bash
# Ensure sudo access
sudo -v

# For NixOS, check if sudo is properly configured
# In your machine config:
security.sudo.wheelNeedsPassword = false;  # Or set up proper sudoers

# For remote deployment, check SSH key auth
ssh-add ~/.ssh/id_ed25519
ssh orther@target-machine
```

**Error**: Secret files have wrong permissions

**Solutions**:
```bash
# Check SOPS secret permissions
ls -la /run/secrets/

# Restart SOPS service
sudo systemctl restart sops-nix

# Verify service user exists
id service-username
```

### Network Issues

**Error**: Network timeouts during build

**Solutions**:
```bash
# Check network connectivity
ping cache.nixos.org

# Configure proxy if needed
export https_proxy=http://proxy:port
export http_proxy=http://proxy:port

# Use different substituters
nix build --option substituters "https://mirror.example.com"
```

## Service Issues

### Systemd Service Failures

**Error**: Service fails to start after deployment

**Diagnosis**:
```bash
# Check service status
systemctl status service-name

# View recent logs
journalctl -u service-name -f

# Check service dependencies
systemctl list-dependencies service-name
```

**Common Solutions**:
```bash
# Restart failed services
sudo systemctl restart service-name

# Check configuration syntax
nixos-rebuild dry-build --flake .#your-machine

# Verify secrets are available
sudo ls -la /run/secrets/service-*
```

### Nginx Configuration Issues

**Error**: Nginx fails to start or reload

**Solutions**:
```bash
# Test nginx configuration
sudo nginx -t

# Check for port conflicts
sudo netstat -tulpn | grep :80
sudo netstat -tulpn | grep :443

# Verify certificate files exist
ls -la /var/lib/acme/*/
```

**Error**: SSL certificate issues

**Solutions**:
```bash
# Check ACME service status
systemctl status acme-your-domain.service

# Manually request certificate
sudo systemctl start acme-your-domain.service

# Check DNS configuration
dig your-domain.com
```

### Docker/Container Issues

**Error**: Docker containers fail to start

**Solutions**:
```bash
# Check Docker daemon
systemctl status docker

# Check container logs
docker logs container-name

# Verify mount points exist
ls -la /mnt/docker-data/
```

## Hardware-Specific Issues

### Boot Issues

**Error**: System fails to boot after deployment

**Recovery**:
```bash
# Boot from previous generation (GRUB menu)
# Select older generation from boot menu

# Or rollback remotely
ssh orther@machine sudo /nix/var/nix/profiles/system/bin/switch-to-configuration switch

# Rollback locally
sudo nixos-rebuild switch --rollback
```

**Error**: Disk encryption fails to unlock

**Solutions**:
```bash
# Check SSH service in initrd
systemctl status sshd  # From rescue system

# Verify SSH keys are correct
ssh-keyscan your-server-ip

# Manual unlock via SSH
ssh root@server-ip
cryptsetup luksOpen /dev/disk/by-uuid/... root
```

### Network Configuration

**Error**: Network interface not found

**Solutions**:
```bash
# List available interfaces
ip link show

# Update hardware-configuration.nix
sudo nixos-generate-config --show-hardware-config

# Check interface naming
dmesg | grep eth
dmesg | grep wlan
```

**Error**: Static IP not applying

**Solutions**:
```bash
# Check network configuration
ip addr show
ip route show

# Verify systemd-networkd
systemctl status systemd-networkd
networkctl status
```

## Secrets Management Issues

### SOPS Decryption Failures

**Error**: `Failed to get data key`

**Solutions**:
```bash
# Check age key exists and is readable
sudo cat /nix/secret/age-key

# Verify machine key in .sops.yaml
ssh-to-age -private-key -i /etc/ssh/ssh_host_ed25519_key
grep "age1your_key_here" .sops.yaml

# Re-generate age key
just fix-sops-keys
```

**Error**: `no age key found`

**Solutions**:
```bash
# Check age key file location
ls -la ~/.config/sops/age/keys.txt
sudo ls -la /nix/secret/age-key

# Generate new age key
age-keygen -o ~/.config/sops/age/keys.txt

# Update all secrets with new key
just secrets-update
```

### Secret File Permissions

**Error**: Service can't read secret file

**Solutions**:
```bash
# Check secret ownership
ls -la /run/secrets/

# Verify service user/group
id service-user

# Update secret configuration
sops.secrets."service/secret" = {
  owner = "correct-user";
  group = "correct-group"; 
  mode = "0440";
};
```

## Development Issues

### Editor/IDE Problems

**Error**: Language server not working with Nix files

**Solutions**:
```bash
# Install nil (Nix language server)
nix-shell -p nil

# Or use nixd
nix-shell -p nixd

# Configure your editor to use the language server
# For VS Code: install "Nix IDE" extension
# For Neovim: configure nil/nixd in LSP config
```

### Git Integration Issues

**Error**: Large Nix store paths in git

**Solutions**:
```bash
# Add to .gitignore
echo "result*" >> .gitignore
echo ".direnv/" >> .gitignore

# Remove accidentally committed store paths
git rm --cached result
git commit -m "Remove Nix build results"
```

## Performance Issues

### Slow Builds

**Problem**: Builds take very long

**Solutions**:
```bash
# Enable all available cores
echo "max-jobs = auto" | sudo tee -a /etc/nix/nix.conf

# Use binary cache
nix build --option substituters "https://cache.nixos.org https://nix-community.cachix.org"

# Parallel evaluation
echo "eval-jobs = auto" | sudo tee -a /etc/nix/nix.conf
```

### High Memory Usage

**Problem**: System runs out of memory during builds

**Solutions**:
```bash
# Limit concurrent jobs
echo "max-jobs = 2" | sudo tee -a /etc/nix/nix.conf

# Enable swap
sudo swapon --show
# Add swap if needed

# Use remote builder
nix build --builders "ssh://builder-machine x86_64-linux"
```

### Disk Space Issues

**Problem**: `/nix/store` filling up disk

**Solutions**:
```bash
# Check disk usage
du -sh /nix/store
nix path-info --all --size | sort -k2 -n

# Aggressive cleanup
just gc
nix store optimise

# Remove old user profiles
nix-env --delete-generations old
nix-collect-garbage -d
```

## Emergency Procedures

### System Recovery

**If system is completely broken**:

1. **Boot from rescue media**:
   ```bash
   # Boot from NixOS ISO or previous generation
   ```

2. **Mount existing system**:
   ```bash
   sudo mount /dev/disk/by-label/nixos /mnt
   sudo nixos-enter
   ```

3. **Rollback to working generation**:
   ```bash
   nix-env --rollback --profile /nix/var/nix/profiles/system
   /nix/var/nix/profiles/system/bin/switch-to-configuration switch
   ```

### Remote Recovery

**If SSH access is lost**:

1. **Use out-of-band access** (IPMI, physical console)

2. **Check network configuration**:
   ```bash
   ip addr show
   systemctl status sshd
   ```

3. **Restore network/SSH**:
   ```bash
   systemctl restart systemd-networkd
   systemctl restart sshd
   ```

### Data Recovery

**For impermanence systems**:

1. **Important files are in `/persist`**:
   ```bash
   ls -la /persist/
   ```

2. **Backup before major changes**:
   ```bash
   sudo rsync -av /persist/ /backup/
   ```

3. **Restore from backup if needed**:
   ```bash
   sudo rsync -av /backup/ /persist/
   ```

## Getting Help

### Diagnostic Information

When asking for help, provide:

```bash
# System information
nix-info -m

# Flake information
nix flake show
nix flake metadata

# Error logs
journalctl -xe
nixos-rebuild switch --show-trace
```

### Community Resources

- **NixOS Discourse**: [discourse.nixos.org](https://discourse.nixos.org)
- **Matrix Chat**: `#nixos:nixos.org`
- **GitHub Issues**: For doomlab-specific issues
- **NixOS Manual**: [nixos.org/manual](https://nixos.org/manual)

### Documentation

- **NixOS Options**: [search.nixos.org/options](https://search.nixos.org/options)
- **Nix Pills**: [nixos.org/guides/nix-pills](https://nixos.org/guides/nix-pills)
- **Home Manager**: [nix-community.github.io/home-manager](https://nix-community.github.io/home-manager)

---

If you encounter issues not covered here, please open a [GitHub issue](https://github.com/orther/doomlab/issues) with:
1. **Clear description** of the problem
2. **Steps to reproduce**  
3. **Error messages** (full output)
4. **System information** (`nix-info -m`)
5. **Configuration snippets** (relevant parts)