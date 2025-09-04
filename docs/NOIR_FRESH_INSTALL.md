# Noir Fresh Install

Concise, repeatable steps to rebuild noir from scratch and restore access to encrypted secrets.

## Prerequisites
- Network access on the installer.
- This repo available on your workstation (with git access).
- Ability to decrypt secrets via any existing recipient (e.g., `zinc`) or a backup personal age key. If not, see Troubleshooting.

## 1) Install NixOS on Noir
1. Boot the official NixOS installer ISO on the target machine.
2. Run the guided installer script:
   ```bash
   bash -c "$(curl -fsSL https://raw.githubusercontent.com/orther/doomlab/main/install.sh)"
   ```
   What it does:
   - Partitions and sets up LUKS, tmpfs root, and a persistent `/nix`.
   - Generates initrd SSH host key at `/mnt/nix/secret/initrd/ssh_host_ed25519_key`.
   - Prints an Age public key derived from the SSH key (starts with `age1...`). Copy/save this key.
3. Install the system and reboot:
   ```bash
   sudo nixos-install --no-root-passwd --root /mnt --flake github:orther/doomlab#noir
   reboot
   ```

## 2) Wire SOPS Secrets (Workstation)
1. Update `.sops.yaml` with the new noir Age recipient:
   - Replace the `&noir` value with the new `age1...` printed in step 1.
2. Re-encrypt secrets with updated recipients:
   ```bash
   just secrets-update
   ```
3. Commit and push:
   ```bash
   git add .sops.yaml secrets/*
   git commit -m "noir: update age recipient and re-encrypt"
   git push
   ```

## 3) First Boot Checks (On Noir)
- Log in as `orther` (password from `secrets/user-password`).
- Verify secrets are decrypted and exposed by sops-nix:
  ```bash
  systemctl status sops-nix
  ls -la /run/secrets
  ```
- Verify Tailscale (uses `tailscale-authkey` from secrets):
  ```bash
  sudo systemctl status tailscaled
  tailscale status || true
  ```
- Confirm persistent keys survive reboot:
  ```bash
  ls -la /nix/secret/initrd/ssh_host_ed25519_key
  ```

## 4) Deploy From Workstation
- LAN or Tailscale deployment:
  ```bash
  just deploy noir 10.4.0.26
  ```

## 5) Optional: Enable SOPS Editing On Noir
Install the Age key material for `sops` CLI on noir:
```bash
just fix-sops-keys
```

## Troubleshooting
- Can’t decrypt secrets locally?
  - Use another machine/recipient still listed in `.sops.yaml` (e.g., `zinc`) to run `just secrets-update`.
  - Or add your personal Age key:
    ```bash
    age-keygen -o ~/.config/sops/age/keys.txt
    # Add the public key to .sops.yaml under keys + creation_rules
    just secrets-update
    git commit -am "add personal recipient, update keys" && git push
    ```
- No valid recipients available: restore secrets from backup or recreate them, then encrypt with the new noir key in `.sops.yaml`.

