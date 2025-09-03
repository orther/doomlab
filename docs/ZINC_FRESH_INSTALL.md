# Zinc Fresh Install

Concise, repeatable steps to rebuild zinc and restore access to encrypted secrets.

## Prerequisites
- Network access on the installer.
- This repo available on your workstation (with git access).
- Ability to decrypt secrets via an existing recipient (e.g., `noir`) or a backup personal age key.

## 1) Install NixOS on Zinc
1. Boot the official NixOS installer ISO on the target machine.
2. Run the guided installer script:
   ```bash
   bash -c "$(curl -fsSL https://raw.githubusercontent.com/orther/doomlab/main/install.sh)"
   ```
   What it does:
   - Partitions and sets up LUKS, tmpfs root, and a persistent `/nix`.
   - Generates initrd SSH host key at `/mnt/nix/secret/initrd/ssh_host_ed25519_key`.
   - Prints an Age public key derived from the SSH key. Copy/save this key.
3. Install the system and reboot:
   ```bash
   sudo nixos-install --no-root-passwd --root /mnt --flake github:orther/doomlab#zinc
   reboot
   ```

## 2) Wire SOPS Secrets (Workstation)
1. Update `.sops.yaml` with the new zinc Age recipient:
   - Replace the `&zinc` value with the new `age1...` from the installer step above.
2. Re-encrypt secrets with updated recipients:
   ```bash
   just secrets-update
   ```
3. Commit and push:
   ```bash
   git add .sops.yaml secrets/*
   git commit -m "zinc: update age recipient and re-encrypt"
   git push
   ```

## 3) First Boot Checks (On Zinc)
- Verify secrets are decrypted and exposed by sops-nix:
  ```bash
  systemctl status sops-nix
  ls -la /run/secrets
  ```
- Verify Tailscale:
  ```bash
  sudo systemctl status tailscaled
  tailscale status || true
  ```

## 4) Deploy From Workstation
```bash
just deploy zinc 10.4.0.24
```

## 5) Optional: Enable SOPS Editing On Zinc
Install the Age key material for `sops` CLI on zinc:
```bash
just fix-sops-keys
```

## Troubleshooting
Follow the same approaches as noir:
- Use a surviving recipient to run `just secrets-update`.
- Add your personal Age key temporarily to `.sops.yaml` and `just secrets-update`.
- If no recipients remain, recreate/restore secrets and encrypt to the new zinc key.

