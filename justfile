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

# Legacy aliases (deprecated - use new names above)
sopsedit: secrets-edit
sopsrotate: secrets-rotate  
sopsupdate: secrets-update
fix-sop-keystxt: fix-sops-keys
