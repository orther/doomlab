# Dagger Integration Guide

This repository uses [Dagger](https://dagger.io/) for modern, reproducible CI/CD pipelines that combine the power of Nix with containerized build environments.

## Overview

The Dagger integration provides:
- **Reproducible builds** across all environments (local, CI, production)
- **Parallel testing** of all machine configurations
- **Security scanning** and compliance checks
- **Preview environments** for testing changes
- **Intelligent caching** combining Nix and Dagger cache systems

## Quick Start

### Prerequisites

1. Install Dagger CLI:
   ```bash
   curl -L https://dl.dagger.io/dagger/install.sh | sh
   ```

2. Ensure Docker is running:
   ```bash
   docker info
   ```

### Basic Commands

```bash
# Test all machine configurations
just test-all

# Test specific machine
just test-machine workchng

# Run security scan
just security-scan

# Run full pipeline
just pipeline

# Build ISO with Dagger
just build-iso-dagger

# Get list of machines
just machines
```

## Available Dagger Functions

### Build Functions

- `build-nix-o-s --machine=NAME` - Build specific NixOS configuration
- `build-darwin --machine=NAME` - Build specific Darwin configuration
- `build-i-s-o` - Build custom installation ISO

### Test Functions

- `test-all-nix-o-s-configurations` - Test all NixOS machines
- `test-all-darwin-configurations` - Test all Darwin machines
- `test-service-configurations` - Validate service configurations

### Quality Functions

- `lint-nix-code` - Lint all Nix files with statix
- `format-nix-code` - Format all Nix files with alejandra
- `security-scan` - Run security scanning with Trivy
- `validate-secrets` - Validate SOPS encrypted files

### Utility Functions

- `get-machine-list` - List all available machines
- `run-full-pipeline` - Execute complete CI/CD pipeline
- `deploy-preview --machine=NAME` - Create preview environment

## GitHub Actions Integration

### Workflows

1. **`dagger-ci.yml`** - Main CI/CD pipeline
   - Runs on push, PR, and manual trigger
   - Parallel testing of all configurations
   - Security scanning and compliance checks
   - Artifact building for releases

2. **`dagger-schedule.yml`** - Scheduled health checks
   - Daily validation of all configurations
   - Performance monitoring
   - Automatic issue creation on failures

3. **Enhanced existing workflows**:
   - `flake.yml` - Now validates updates with Dagger
   - `release.yml` - Full pipeline validation before releases

### Manual Triggers

You can manually trigger workflows with specific machines:

```bash
# Via GitHub CLI
gh workflow run dagger-ci.yml -f machine=workchng

# Via GitHub web interface
# Go to Actions -> Dagger CI/CD Pipeline -> Run workflow
```

## Local Development

### Testing Changes

Before pushing changes, test them locally:

```bash
# Test all configurations
just test-all

# Test specific machine you're working on  
just test-machine workchng

# Run security scan
just security-scan

# Format code
just fmt-dagger
```

### Preview Environments

Create isolated preview environments to test changes:

```bash
# Create preview for specific machine
just preview workchng

# The preview environment will be accessible via SSH
```

## Advanced Usage

### Custom Pipeline Functions

The Dagger module (`dagger/main.go`) can be extended with custom functions:

```go
// Add your custom pipeline function
func (m *Doomlab) CustomCheck(
    ctx context.Context,
    source *dagger.Directory,
) (*dagger.Container, error) {
    return dag.Container().
        From("nixos/nix:latest").
        WithDirectory("/src", source).
        WithExec([]string{"echo", "Custom check logic here"}), nil
}
```

### Caching Strategy

The integration uses multiple caching layers:

1. **Dagger cache mounts** - For build dependencies
2. **Nix binary cache** - For Nix packages and closures  
3. **GitHub Actions cache** - For workflow artifacts

### Environment Variables

Configure Dagger behavior with environment variables:

```bash
# Use custom Dagger engine version
export DAGGER_ENGINE_VERSION=v0.18.16

# Configure binary caches
export NIX_CONFIG="substituters = https://cache.nixos.org https://nix-community.cachix.org"
```

## Troubleshooting

### Common Issues

1. **Docker not running**:
   ```bash
   systemctl start docker  # Linux
   # or restart Docker Desktop
   ```

2. **Permission errors**:
   ```bash
   sudo usermod -aG docker $USER
   newgrp docker
   ```

3. **Build timeouts**:
   - Increase timeout in workflow files
   - Check binary cache availability
   - Monitor resource usage

### Debug Mode

Run Dagger with debug output:

```bash
dagger call --debug test-all-nix-o-s-configurations --source=.
```

### Performance Monitoring

Monitor build performance:

```bash
time dagger call build-nix-o-s --source=. --machine=workchng
```

## Security Considerations

- Secrets are never passed to Dagger context (see `.daggerignore`)
- Security scanning runs on every pipeline execution
- Preview environments are isolated and ephemeral
- All builds run in containerized environments

## Migration from Legacy CI

The Dagger integration works alongside existing workflows:

- **Justfile commands** - Enhanced with Dagger equivalents
- **GitHub Actions** - Upgraded to use Dagger for validation
- **Manual processes** - Can gradually adopt Dagger functions

Old commands remain functional while new Dagger-powered alternatives are available.

## Support

For issues related to:
- **Dagger integration**: Check this documentation and GitHub issues
- **NixOS configurations**: See `docs/ARCHITECTURE.md`
- **Secrets management**: See `docs/SECRETS.md`
- **General setup**: See `docs/SETUP.md`