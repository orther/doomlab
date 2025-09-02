# Secrets Management Guide

This guide covers the complete workflow for managing encrypted secrets in the doomlab configuration using SOPS (Secrets OPerationS) with age encryption.

## Overview

The doomlab configuration uses **SOPS** for secrets management, providing:
- **Age/GPG encryption** for secure storage
- **Machine-specific access** control  
- **Git-friendly** encrypted files
- **Nix integration** for seamless deployment

## Prerequisites

Before working with secrets, ensure you have:
- SOPS installed (`nix-shell -p sops`)
- Age key configured (see [Initial Setup](#initial-setup))
- SSH access to target machines
- Understanding of which secrets each machine needs

## Initial Setup

### 1. Generate Age Keys

Each machine needs an age key derived from its SSH host key:

```bash
# On the target machine, extract age key from SSH host key
sudo ssh-to-age -private-key -i /etc/ssh/ssh_host_ed25519_key

# Save this key for configuration
```

### 2. Configure SOPS

The `.sops.yaml` file controls which machines can decrypt which secrets:

```yaml
keys:
  - &orther_key age1... # Your personal age key
  - &noir_key age1...   # noir machine key
  - &macos_key age1...  # macOS machine key

creation_rules:
  - path_regex: secrets/.*\.yaml$
    key_groups:
      - age:
          - *orther_key
          - *noir_key
          - *macos_key
```

### 3. Set Up Personal Age Key

Create your personal age key for editing secrets:

```bash
# Generate personal age key
age-keygen -o ~/.config/sops/age/keys.txt

# Add public key to .sops.yaml
```

## Working with Secrets

### Creating New Secrets

1. **Edit the secrets file**:
   ```bash
   just secrets-edit
   # This opens secrets/secrets.yaml in your editor
   ```

2. **Add your secrets** in YAML format:
   ```yaml
   # Example secrets structure
   users:
     orther:
       password: "$6$rounds=500000$..."  # mkpasswd generated hash
   
   services:
     nextcloud:
       admin_password: "secure_password_here"
       db_password: "database_password"
   
   api_keys:
     tailscale: "tskey-auth-..."
     cloudflare: "your_api_token"
   ```

3. **Save and commit**:
   ```bash
   git add secrets/secrets.yaml
   git commit -m "Add new secrets"
   ```

### Using Secrets in Configuration

Reference secrets in your Nix configuration:

```nix
# In a machine configuration
{
  sops = {
    defaultSopsFile = ../../secrets/secrets.yaml;
    age.keyFile = "/nix/secret/age-key"; # Machine-specific location
    
    secrets = {
      # Define which secrets this machine needs
      "users/orther/password" = {};
      "services/nextcloud/admin_password" = {
        owner = "nextcloud";
        group = "nextcloud";
        mode = "0440";
      };
      "api_keys/tailscale" = {};
    };
  };

  # Use secrets in service configuration
  services.nextcloud = {
    enable = true;
    config = {
      adminpassFile = config.sops.secrets."services/nextcloud/admin_password".path;
    };
  };
  
  users.users.orther = {
    hashedPasswordFile = config.sops.secrets."users/orther/password".path;
  };
}
```

## Machine-Specific Secrets

### Adding a New Machine

1. **Get the machine's age key**:
   ```bash
   # On the new machine
   sudo ssh-to-age -private-key -i /etc/ssh/ssh_host_ed25519_key
   ```

2. **Add to .sops.yaml**:
   ```yaml
   keys:
     - &new_machine_key age1...  # Add the new key
   
   creation_rules:
     - path_regex: secrets/.*\.yaml$
       key_groups:
         - age:
             - *orther_key
             - *noir_key
             - *new_machine_key  # Add to key group
   ```

3. **Update all secret files**:
   ```bash
   just secrets-update
   # This re-encrypts all secrets with the new key
   ```

### Machine-Specific Secret Files

For secrets that only specific machines need:

1. **Create targeted secret file**:
   ```yaml
   # .sops.yaml - add specific rule
   creation_rules:
     - path_regex: secrets/noir-only\.yaml$
       key_groups:
         - age:
             - *orther_key
             - *noir_key  # Only noir can decrypt
   ```

2. **Create the secret file**:
   ```bash
   sops secrets/noir-only.yaml
   ```

3. **Reference in machine config**:
   ```nix
   sops = {
     defaultSopsFile = ../../secrets/noir-only.yaml;
     secrets = {
       "database/root_password" = {};
     };
   };
   ```

## Common Workflows

### Rotating Secrets

When you need to change secret values:

1. **Edit secrets**:
   ```bash
   just secrets-edit
   # Update the values you need to change
   ```

2. **Deploy changes**:
   ```bash
   just deploy machine-name
   # Services will automatically get new secret values
   ```

### Rotating Age Keys

When SSH host keys change or you want to rotate encryption keys:

1. **Generate new keys on affected machines**:
   ```bash
   # On each machine that changed
   sudo ssh-to-age -private-key -i /etc/ssh/ssh_host_ed25519_key
   ```

2. **Update .sops.yaml** with new public keys

3. **Re-encrypt all secrets**:
   ```bash
   just secrets-rotate  # Rotate encryption keys
   just secrets-update  # Update with new keys
   ```

4. **Fix age keys on machines**:
   ```bash
   # Run on each affected machine after deployment
   just fix-sops-keys
   ```

### Adding New Service Secrets

For a new service that needs secrets:

1. **Add secrets to secrets.yaml**:
   ```yaml
   services:
     new_service:
       api_key: "secret_api_key"
       password: "secure_password"
   ```

2. **Configure in service module**:
   ```nix
   # services/new-service.nix
   { config, lib, ... }:
   
   {
     sops.secrets = {
       "services/new_service/api_key" = {
         owner = "new-service";
         group = "new-service";  
       };
     };
     
     services.new-service = {
       apiKeyFile = config.sops.secrets."services/new_service/api_key".path;
     };
   }
   ```

## Security Best Practices

### Key Management

1. **Secure key storage**:
   - Personal keys: `~/.config/sops/age/keys.txt` (mode 600)
   - Machine keys: `/nix/secret/age-key` (managed by system)
   
2. **Key rotation**:
   - Rotate personal keys annually
   - Rotate machine keys when SSH keys change
   - Use `just secrets-rotate` regularly

3. **Access control**:
   - Only grant machine access to needed secrets
   - Use separate secret files for different security domains
   - Regularly audit `.sops.yaml` access rules

### Secret Values

1. **Generate strong secrets**:
   ```bash
   # Generate random passwords
   openssl rand -base64 32
   
   # Generate user password hashes
   echo "password" | mkpasswd -m SHA-512 -s
   ```

2. **Never commit plaintext secrets**:
   - Always encrypt with SOPS before committing
   - Use `git status` to verify files are encrypted
   - Set up git hooks to prevent accidents

3. **Minimize secret scope**:
   - Use service-specific secrets when possible
   - Avoid sharing secrets between unrelated services
   - Use short-lived tokens where supported

### File Permissions

SOPS automatically sets secure permissions, but verify:

```nix
sops.secrets."service/password" = {
  owner = "service-user";    # Service user owns the secret
  group = "service-group";   # Service group can read
  mode = "0440";             # Read-only for owner/group
};
```

## Troubleshooting

### Common Issues

1. **"Failed to decrypt" errors**:
   ```bash
   # Check age key is correct
   sudo cat /nix/secret/age-key
   
   # Verify machine key in .sops.yaml
   grep "$(ssh-to-age -private-key -i /etc/ssh/ssh_host_ed25519_key)" .sops.yaml
   ```

2. **Permission errors**:
   ```bash
   # Check secret file permissions
   ls -la /run/secrets/
   
   # Verify service user/group exists
   id service-user
   ```

3. **Secrets not updating**:
   ```bash
   # Force secret reload
   sudo systemctl restart sops-nix
   sudo systemctl restart affected-service
   ```

### Debugging Commands

```bash
# Check SOPS configuration
sops --version
sops -d secrets/secrets.yaml  # Decrypt and display

# Verify age key format
age -version  
ssh-to-age -private-key -i /etc/ssh/ssh_host_ed25519_key

# Check Nix SOPS integration
systemctl status sops-nix
journalctl -u sops-nix
```

### Recovery Procedures

**If you lose access to secrets**:

1. **Emergency access** (if you have sudo on the machine):
   ```bash
   # View decrypted secrets
   sudo cat /run/secrets/secret-name
   ```

2. **Re-encrypt with new keys**:
   ```bash
   # Decrypt with old key, re-encrypt with new
   sops -d secrets/secrets.yaml > /tmp/plaintext
   # Edit .sops.yaml with new keys  
   sops -e /tmp/plaintext > secrets/secrets.yaml
   rm /tmp/plaintext  # Clean up immediately
   ```

3. **Restore from backup**:
   ```bash
   # If you have a backup of age keys
   cp backup/keys.txt ~/.config/sops/age/
   sops -d secrets/secrets.yaml  # Should work now
   ```

## Advanced Usage

### Multiple Secret Files

Organize secrets by domain:

```bash
secrets/
├── secrets.yaml          # Common secrets
├── production.yaml       # Production-only secrets  
├── development.yaml      # Development secrets
└── personal.yaml         # Personal machine secrets
```

### Binary Secrets

For binary files (certificates, keys):

```bash
# Encrypt binary file
sops -e certificate.pem > secrets/certificate.pem.enc

# Use in configuration
sops.secrets."certificate" = {
  sopsFile = ../../secrets/certificate.pem.enc;
  format = "binary";
};
```

### Conditional Secrets

Load secrets based on machine type:

```nix
{
  sops.secrets = lib.mkMerge [
    # Common secrets for all machines
    { "users/orther/password" = {}; }
    
    # Server-specific secrets
    (lib.mkIf config.services.nextcloud.enable {
      "services/nextcloud/admin_password" = {};
    })
  ];
}
```

---

This secrets management system provides strong security while maintaining usability and automation. Regular key rotation and access audits will keep your secrets secure over time.