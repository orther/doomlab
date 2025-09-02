# List available commands
default:
  @just --list

# Deploy system configuration locally or remotely
# Examples:
#   just deploy macos                    # Deploy macOS config locally  
#   just deploy nixos-machine           # Deploy NixOS config locally
#   just deploy noir 10.4.0.10         # Deploy to remote machine
deploy machine ip='':
  #!/usr/bin/env sh
  echo "🚀 Deploying {{machine}}..."
  if [ {{machine}} = "macos" ]; then
    darwin-rebuild switch --flake .
  elif [ -z "{{ip}}" ]; then
    sudo nixos-rebuild switch --fast --flake ".#{{machine}}"
  else
    nixos-rebuild switch --fast --flake ".#{{machine}}" --use-remote-sudo --target-host "orther@{{ip}}" --build-host "orther@{{ip}}"
  fi
  echo "✅ Deployment complete!"

# Update flake inputs to latest versions (like npm update)
up:
  @echo "📦 Updating flake inputs..."
  nix flake update
  @echo "✅ Flake updated! Run 'just deploy MACHINE' to apply changes"

# Check Nix code for issues using statix linter
lint:
  @echo "🔍 Linting Nix code..."
  statix check .

# Garbage collect old system generations (keeps 7 days)
gc:
  @echo "🗑️  Cleaning up old generations and store paths..."
  sudo nix profile wipe-history --profile /nix/var/nix/profiles/system --older-than 7d && sudo nix store gc
  @echo "✅ Garbage collection complete!"

# Verify and repair Nix store integrity
repair:
  @echo "🔧 Verifying and repairing Nix store..."
  sudo nix-store --verify --check-contents --repair

# Edit encrypted secrets file with SOPS
secrets-edit:
  @echo "🔐 Opening encrypted secrets for editing..."
  sops secrets/secrets.yaml

# Rotate age keys for all secret files
secrets-rotate:
  @echo "🔄 Rotating keys for all secrets..."
  for file in secrets/*; do sops --rotate --in-place "$file"; done
  @echo "✅ Key rotation complete!"
  
# Update keys for all secret files after adding/removing machines
secrets-update:
  @echo "🔑 Updating keys for all secrets..."
  for file in secrets/*; do sops updatekeys "$file"; done
  @echo "✅ Keys updated for all files!"

# Build custom NixOS installation ISO
build-iso:
  @echo "💿 Building custom NixOS ISO..."
  nix build .#nixosConfigurations.iso1chng.config.system.build.isoImage
  @echo "✅ ISO built! Check result/ directory"

# Fix SOPS age keys after SSH host key changes
fix-sops-keys:
  @echo "🔧 Fixing SOPS age keys..."
  mkdir -p ~/.config/sops/age
  sudo nix-shell --extra-experimental-features flakes -p ssh-to-age --run 'ssh-to-age -private-key -i /nix/secret/initrd/ssh_host_ed25519_key -o /home/orther/.config/sops/age/keys.txt'
  sudo chown -R orther:users ~/.config/sops/age
  @echo "✅ Age keys fixed!"

# Manually trigger automated secrets rotation
secrets-rotate-now:
  @echo "🔄 Triggering manual secrets rotation..."
  sudo systemctl start secrets-rotation.service
  @echo "✅ Rotation initiated! Check status: just secrets-status"

# Check secrets rotation service status and logs
secrets-status:
  @echo "📊 Secrets rotation service status:"
  sudo systemctl status secrets-rotation.service --no-pager || true
  @echo ""
  @echo "📋 Recent rotation logs:"
  sudo journalctl -u secrets-rotation.service --no-pager -n 20 || true
  @echo ""
  @echo "⏰ Next scheduled rotation:"
  sudo systemctl list-timers secrets-rotation.timer --no-pager || true

# Check binary cache statistics and performance
cache-stats:
  @echo "📊 Binary cache statistics:"
  @echo "Cache substituters:"
  nix show-config | grep substituters || true
  @echo ""
  @echo "💾 Nix store statistics:"
  du -sh /nix/store 2>/dev/null || echo "Unable to check store size"
  @echo ""
  @echo "🔢 Store path count:"
  find /nix/store -maxdepth 1 -type d | wc -l 2>/dev/null || echo "Unable to count paths"
  @echo ""
  @echo "⚡ Recent cache hits (from logs):"
  journalctl -u nix-daemon --since "1 day ago" --no-pager | grep -i "substitut" | tail -5 || echo "No recent cache activity found"

# Test binary cache connectivity and performance
cache-test:
  @echo "🧪 Testing binary cache connectivity..."
  @echo "Testing cache.nixos.org:"
  curl -I https://cache.nixos.org/ || echo "❌ Official cache unreachable"
  @echo ""
  @echo "Testing nix-community.cachix.org:"
  curl -I https://nix-community.cachix.org/ || echo "❌ Community cache unreachable"
  @echo ""
  @echo "🏗️ Testing substitution with a common package:"
  nix-store --realize /nix/store/$(nix-instantiate --eval -E 'with import <nixpkgs> {}; hello' | tr -d '"' | cut -d'-' -f1)-hello* --dry-run 2>/dev/null || echo "Test substitution complete"

# Monitor system resource usage in real-time
monitor:
  @echo "🖥️  System Resource Monitor"
  @echo "Press Ctrl+C to exit"
  @echo ""
  sudo systemd-cgtop

# Show detailed service resource usage
service-resources:
  @echo "📊 Service Resource Usage:"
  @echo ""
  @echo "=== Memory Usage by Service ==="
  systemctl status --no-pager | grep -E "(●|├|└)" | head -20 || true
  @echo ""
  @echo "=== Top Memory Consumers ==="
  sudo systemctl --type=service --state=running --no-pager | head -10
  @echo ""
  @echo "=== Resource Limits Status ==="
  sudo systemctl show --property=MemoryMax,CPUQuotaPerSecUSec,TasksMax nginx.service docker.service tailscaled.service sshd.service 2>/dev/null || echo "Some services not found"

# View system resource monitoring logs
resource-logs:
  @echo "📋 System Resource Monitoring Logs:"
  @echo ""
  @echo "=== Recent Resource Usage ==="
  tail -n 50 /var/log/system-resources.log 2>/dev/null || echo "No monitoring logs found yet"
  @echo ""
  @echo "=== System Monitor Service Status ==="
  systemctl status system-monitor.service --no-pager || true

# Show current resource usage summary
resource-summary:
  @echo "💾 Current System Resource Usage:"
  @echo ""
  @echo "=== Memory ==="
  free -h
  @echo ""
  @echo "=== CPU Load ==="
  uptime
  @echo ""
  @echo "=== Disk Usage ==="
  df -h /
  @echo ""
  @echo "=== Top Processes ==="
  ps aux --sort=-%mem | head -6

# Legacy aliases (deprecated - use new names above)
sopsedit: secrets-edit
sopsrotate: secrets-rotate  
sopsupdate: secrets-update
fix-sop-keystxt: fix-sops-keys
