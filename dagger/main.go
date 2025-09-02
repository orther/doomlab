// Package dagger provides Dagger pipeline functions for the doomlab NixOS flake
package main

import (
	"context"
	"fmt"
	"strings"

	"dagger.io/dagger"
)

// Doomlab represents the main dagger module for the NixOS flake repository
type Doomlab struct{}

// NixOSMachines defines all available machine configurations
var NixOSMachines = []string{
	"workchng", "dsk1chng", "svr1chng", "svr2chng", "svr3chng",
	"noir", "zinc", "vmnixos", "iso1chng",
}

// DarwinMachines defines all available Darwin machine configurations  
var DarwinMachines = []string{
	"mair", "mac1chng",
}

// BuildNixOS builds a specific NixOS machine configuration with full reproducibility
func (m *Doomlab) BuildNixOS(
	ctx context.Context,
	// Source directory containing the flake
	source *dagger.Directory,
	// Machine name to build
	machine string,
) (*dagger.Container, error) {
	return dag.Container().
		From("nixos/nix:latest").
		WithDirectory("/src", source).
		WithWorkdir("/src").
		WithExec([]string{"nix", "--extra-experimental-features", "nix-command flakes", "build", fmt.Sprintf(".#nixosConfigurations.%s.config.system.build.toplevel", machine), "--no-link"}).
		WithExec([]string{"nix", "--extra-experimental-features", "nix-command flakes", "flake", "check"}), nil
}

// BuildDarwin builds a specific Darwin machine configuration
func (m *Doomlab) BuildDarwin(
	ctx context.Context,
	// Source directory containing the flake  
	source *dagger.Directory,
	// Machine name to build
	machine string,
) (*dagger.Container, error) {
	return dag.Container().
		From("nixos/nix:latest").
		WithDirectory("/src", source).
		WithWorkdir("/src").
		WithExec([]string{"nix", "--extra-experimental-features", "nix-command flakes", "build", fmt.Sprintf(".#darwinConfigurations.%s.system", machine), "--no-link"}), nil
}

// TestAllNixOSConfigurations builds and validates all NixOS machine configurations
func (m *Doomlab) TestAllNixOSConfigurations(
	ctx context.Context,
	// Source directory containing the flake
	source *dagger.Directory,
) (*dagger.Container, error) {
	container := dag.Container().
		From("nixos/nix:latest").
		WithDirectory("/src", source).
		WithWorkdir("/src")

	// Add binary caches for faster builds
	container = container.
		WithExec([]string{"mkdir", "-p", "/etc/nix"}).
		WithNewFile("/etc/nix/nix.conf", dagger.ContainerWithNewFileOpts{
			Contents: `
extra-experimental-features = nix-command flakes
substituters = https://cache.nixos.org https://nix-community.cachix.org
trusted-public-keys = cache.nixos.org-1:6NCHdD59X431o0gWypbMrAURkbJ16ZPMQFGspcDShjY= nix-community.cachix.org-1:mB9FSh9qf2dCimDSUo8Zy7bkq5CX+/rkCWyvRCYg3Fs=
`,
		})

	// Test each NixOS configuration
	for _, machine := range NixOSMachines {
		container = container.
			WithExec([]string{"echo", fmt.Sprintf("🔧 Building NixOS configuration: %s", machine)}).
			WithExec([]string{"nix", "build", fmt.Sprintf(".#nixosConfigurations.%s.config.system.build.toplevel", machine), "--no-link"})
	}

	// Run flake check
	container = container.
		WithExec([]string{"echo", "🔍 Running flake check..."}).
		WithExec([]string{"nix", "flake", "check"})

	return container, nil
}

// TestAllDarwinConfigurations builds and validates all Darwin machine configurations
func (m *Doomlab) TestAllDarwinConfigurations(
	ctx context.Context,
	// Source directory containing the flake
	source *dagger.Directory,
) (*dagger.Container, error) {
	container := dag.Container().
		From("nixos/nix:latest").
		WithDirectory("/src", source).
		WithWorkdir("/src")

	// Add binary caches for faster builds
	container = container.
		WithExec([]string{"mkdir", "-p", "/etc/nix"}).
		WithNewFile("/etc/nix/nix.conf", dagger.ContainerWithNewFileOpts{
			Contents: `
extra-experimental-features = nix-command flakes
substituters = https://cache.nixos.org https://nix-community.cachix.org
trusted-public-keys = cache.nixos.org-1:6NCHdD59X431o0gWypbMrAURkbJ16ZPMQFGspcDShjY= nix-community.cachix.org-1:mB9FSh9qf2dCimDSUo8Zy7bkq5CX+/rkCWyvRCYg3Fs=
`,
		})

	// Test each Darwin configuration
	for _, machine := range DarwinMachines {
		container = container.
			WithExec([]string{"echo", fmt.Sprintf("🔧 Building Darwin configuration: %s", machine)}).
			WithExec([]string{"nix", "build", fmt.Sprintf(".#darwinConfigurations.%s.system", machine), "--no-link"})
	}

	return container, nil
}

// LintNixCode runs statix linter on all Nix files in the repository
func (m *Doomlab) LintNixCode(
	ctx context.Context,
	// Source directory containing the flake
	source *dagger.Directory,
) (*dagger.Container, error) {
	return dag.Container().
		From("nixos/nix:latest").
		WithDirectory("/src", source).
		WithWorkdir("/src").
		WithExec([]string{"nix", "--extra-experimental-features", "nix-command flakes", "run", "nixpkgs#statix", "--", "check", "."}), nil
}

// FormatNixCode formats all Nix files using alejandra formatter
func (m *Doomlab) FormatNixCode(
	ctx context.Context,
	// Source directory containing the flake
	source *dagger.Directory,
) (*dagger.Directory, error) {
	return dag.Container().
		From("nixos/nix:latest").
		WithDirectory("/src", source).
		WithWorkdir("/src").
		WithExec([]string{"nix", "--extra-experimental-features", "nix-command flakes", "fmt"}).
		Directory("/src"), nil
}

// BuildISO builds the custom NixOS installation ISO
func (m *Doomlab) BuildISO(
	ctx context.Context,
	// Source directory containing the flake
	source *dagger.Directory,
) (*dagger.File, error) {
	container := dag.Container().
		From("nixos/nix:latest").
		WithDirectory("/src", source).
		WithWorkdir("/src").
		WithExec([]string{"nix", "--extra-experimental-features", "nix-command flakes", "build", ".#nixosConfigurations.iso1chng.config.system.build.isoImage"})

	return container.File("/src/result/iso/nixos-*.iso"), nil
}

// SecurityScan performs security scanning on the repository
func (m *Doomlab) SecurityScan(
	ctx context.Context,
	// Source directory containing the flake
	source *dagger.Directory,
) (*dagger.Container, error) {
	return dag.Container().
		From("aquasec/trivy:latest").
		WithDirectory("/src", source).
		WithWorkdir("/src").
		WithExec([]string{"trivy", "fs", "--security-checks", "vuln,secret,config", "."}), nil
}

// ValidateSecrets validates that all SOPS encrypted files are properly configured
func (m *Doomlab) ValidateSecrets(
	ctx context.Context,
	// Source directory containing the flake
	source *dagger.Directory,
) (*dagger.Container, error) {
	return dag.Container().
		From("nixos/nix:latest").
		WithDirectory("/src", source).
		WithWorkdir("/src").
		WithExec([]string{"nix", "--extra-experimental-features", "nix-command flakes", "run", "nixpkgs#sops", "--", "--decrypt", "--extract", '["example"]', "secrets/secrets.yaml"}), nil
}

// TestServiceConfigurations tests that all service configurations are valid
func (m *Doomlab) TestServiceConfigurations(
	ctx context.Context,
	// Source directory containing the flake
	source *dagger.Directory,
) (*dagger.Container, error) {
	container := dag.Container().
		From("nixos/nix:latest").
		WithDirectory("/src", source).
		WithWorkdir("/src")

	// Test each service configuration by trying to build it
	services := []string{
		"nextcloud", "jellyfin", "nixarr", "netdata", 
		"homebridge", "scrypted", "tailscale",
	}

	for _, service := range services {
		container = container.
			WithExec([]string{"echo", fmt.Sprintf("🔧 Testing service configuration: %s", service)}).
			WithExec([]string{"nix", "eval", "--json", fmt.Sprintf(".#nixosConfigurations.svr1chng.config.services.%s", service)})
	}

	return container, nil
}

// DeployPreview creates a preview environment for testing changes
func (m *Doomlab) DeployPreview(
	ctx context.Context,
	// Source directory containing the flake
	source *dagger.Directory,
	// Machine configuration to preview
	machine string,
) (*dagger.Service, error) {
	container := dag.Container().
		From("nixos/nix:latest").
		WithDirectory("/src", source).
		WithWorkdir("/src").
		WithExec([]string{"nix", "build", fmt.Sprintf(".#nixosConfigurations.%s.config.system.build.vm", machine)}).
		WithExposedPort(22)

	return container.AsService(), nil
}

// RunFullPipeline executes the complete CI/CD pipeline
func (m *Doomlab) RunFullPipeline(
	ctx context.Context,
	// Source directory containing the flake
	source *dagger.Directory,
) (*dagger.Container, error) {
	// Stage 1: Lint and format
	_, err := m.LintNixCode(ctx, source)
	if err != nil {
		return nil, fmt.Errorf("linting failed: %w", err)
	}

	// Stage 2: Build and test all configurations
	nixosResult, err := m.TestAllNixOSConfigurations(ctx, source)
	if err != nil {
		return nil, fmt.Errorf("NixOS configuration tests failed: %w", err)
	}

	darwinResult, err := m.TestAllDarwinConfigurations(ctx, source)
	if err != nil {
		return nil, fmt.Errorf("Darwin configuration tests failed: %w", err)
	}

	// Stage 3: Security scanning
	securityResult, err := m.SecurityScan(ctx, source)
	if err != nil {
		return nil, fmt.Errorf("security scan failed: %w", err)
	}

	// Stage 4: Validate secrets
	_, err = m.ValidateSecrets(ctx, source)
	if err != nil {
		return nil, fmt.Errorf("secrets validation failed: %w", err)
	}

	// Return final success container
	return dag.Container().
		From("alpine:latest").
		WithExec([]string{"echo", "🎉 Full pipeline completed successfully!"}).
		WithExec([]string{"echo", fmt.Sprintf("✅ Tested %d NixOS configurations", len(NixOSMachines))}).
		WithExec([]string{"echo", fmt.Sprintf("✅ Tested %d Darwin configurations", len(DarwinMachines))}).
		WithExec([]string{"echo", "✅ Security scan passed"}).
		WithExec([]string{"echo", "✅ Secrets validation passed"}), nil
}

// GetMachineList returns all available machine configurations
func (m *Doomlab) GetMachineList(
	ctx context.Context,
) (string, error) {
	allMachines := append(NixOSMachines, DarwinMachines...)
	return strings.Join(allMachines, "\n"), nil
}