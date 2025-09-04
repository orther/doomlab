// A generated module for Doomlab functions

package main

import (
	"context"
	"fmt"
	"strings"

	"main/internal/dagger"
)

type Doomlab struct{}

// GetMachineList returns all available machine configurations
func (m *Doomlab) GetMachineList(
	ctx context.Context,
) string {
	nixOSMachines := []string{
		"noir", "zinc", "iso1chng",
	}
	
	darwinMachines := []string{
		"mair", "stud",
	}
	
	allMachines := append(nixOSMachines, darwinMachines...)
	return strings.Join(allMachines, "\n")
}

// Hello returns a greeting message
func (m *Doomlab) Hello(
	ctx context.Context,
	// Optional name to greet
	name string,
) string {
	if name == "" {
		name = "World"
	}
	return "Hello " + name + " from Doomlab!"
}

// BuildISO builds a custom NixOS installation ISO using optimized official Nix container
func (m *Doomlab) BuildISO(
	ctx context.Context,
	// Source directory containing the flake.nix
	source *dagger.Directory,
	// Optional: specify architecture (x86_64-linux or aarch64-linux, defaults to x86_64)
	// +optional
	arch string,
) *dagger.File {
	// Default to x86_64-linux for better compatibility with most PCs and Ventoy
	if arch == "" {
		arch = "x86_64-linux"
	}
	
	// Determine which ISO config to use
	isoTarget := "iso-aarch64"
	if arch == "x86_64-linux" {
		isoTarget = "iso1chng"
	}

	// Use platform-specific container selection for better compatibility
	var container *dagger.Container
	if arch == "x86_64-linux" {
		// Force x86_64 platform for x86_64 builds to avoid cross-compilation
		container = dag.Container(dagger.ContainerOpts{Platform: dagger.Platform("linux/amd64")}).
			From("nixos/nix:latest")
	} else {
		// Use ARM64 platform for aarch64 builds
		container = dag.Container(dagger.ContainerOpts{Platform: dagger.Platform("linux/arm64")}).
			From("nixos/nix:latest")
	}
	
	return container.
		// Show the actual architecture we're running on
		WithExec([]string{"sh", "-c", "echo 'Container arch:' $(uname -m); echo 'Target arch: " + arch + "'"}). 
		// Immediately clean up space and configure optimally
		WithExec([]string{"sh", "-c", `
# Clear any existing store and temporary files
nix-store --gc --max-freed 10000000000 || true
rm -rf /tmp/* /var/tmp/* ~/.cache/* || true
df -h

# Configure Nix for maximum space efficiency
cat > /etc/nix/nix.conf << 'EOF'
# Essential features
experimental-features = nix-command flakes

# Resource limits
max-jobs = 1
cores = 1

# Binary cache optimization
substituters = https://cache.nixos.org https://nix-community.cachix.org
trusted-public-keys = cache.nixos.org-1:6NCHdD59X431o0gWypbMrAURkbJ16ZPMQFGspcDShjY= nix-community.cachix.org-1:mB9FSh9qf2dCimDSUo8Zy7bkq5CX+/rkCWyvRCYg3Fs=

# Aggressive space management
auto-optimise-store = true
min-free = 5368709120
max-free = 10737418240
builders-use-substitutes = true
substitute = true

# Build optimizations
keep-going = false
show-trace = false

# Disable sandboxing to avoid seccomp issues in containers
sandbox = false
EOF
`}).
		WithMountedDirectory("/workspace", source).
		WithWorkdir("/workspace").
		// Build with comprehensive monitoring and error handling
		WithExec([]string{"sh", "-c", fmt.Sprintf(`
set -euo pipefail

echo "=== Pre-build system state ==="
df -h
echo ""

# Validate the flake quickly
echo "=== Validating flake ==="
if ! timeout 60 nix flake show . 2>/dev/null; then
    echo "ERROR: Flake validation failed or timed out"
    exit 1
fi

echo ""
echo "=== Building %s ISO (target: %s) ==="
echo "Starting build with aggressive space management..."

# Set up space monitoring
SPACE_CHECK_INTERVAL=30
{
    while sleep $SPACE_CHECK_INTERVAL; do
        available=$(df / | awk 'NR==2 {print $4}')
        if [ "$available" -lt 2097152 ]; then  # Less than 2GB
            echo "WARNING: Low disk space: ${available}KB available"
            nix-store --gc --max-freed 2000000000 || true
        fi
    done
} &
MONITOR_PID=$!

# Build the ISO with careful resource management
echo "Attempting to build the ISO..."
if nix build \
    '.#nixosConfigurations.%s.config.system.build.isoImage' \
    --out-link result \
    --option max-jobs 1 \
    --option cores 1 \
    --option keep-going false \
    --option sandbox false \
    --show-trace; then
    
    # Kill the monitoring process
    kill $MONITOR_PID 2>/dev/null || true
    
    echo ""
    echo "=== Build completed successfully ==="
    
else
    # Kill the monitoring process
    kill $MONITOR_PID 2>/dev/null || true
    
    echo ""
    echo "=== BUILD FAILED ==="
    echo "System state at failure:"
    df -h
    echo ""
    echo "Nix store size:"
    du -sh /nix/store 2>/dev/null || echo "Cannot measure store size"
    exit 1
fi

# Locate and validate the ISO
echo "Searching for ISO file..."
echo "Build result structure:"
ls -la result/ || echo "Result symlink not found"
echo ""
echo "Looking for ISO files everywhere in result:"
find result -name '*.iso' -type f 2>/dev/null | head -10
echo ""
echo "All files in result (first 30):"
find result -type f 2>/dev/null | head -30

# Try multiple search strategies
iso_path=""
if [ -L "result" ]; then
    echo "Following result symlink..."
    result_target=$(readlink -f result)
    echo "Result points to: $result_target"
    iso_path=$(find "$result_target" -name '*.iso' -type f 2>/dev/null | head -1)
fi

if [ -z "$iso_path" ]; then
    echo "Searching more broadly..."
    iso_path=$(find . -name '*.iso' -type f 2>/dev/null | head -1)
fi

if [ -z "$iso_path" ]; then
    echo "ERROR: No ISO file found anywhere"
    echo "Current directory contents:"
    ls -la .
    exit 1
fi

echo "Found ISO: $iso_path"
iso_size=$(du -h "$iso_path" | cut -f1)
echo "ISO size: $iso_size"

# Copy to output location
cp "$iso_path" /tmp/nixos.iso
echo "=== Success: ISO created ==="
ls -lh /tmp/nixos.iso

echo ""
echo "=== Final system state ==="
df -h

`, arch, isoTarget, isoTarget)}).
		File("/tmp/nixos.iso")
}

// BuildISOSimple builds a NixOS ISO using a simpler approach to avoid seccomp issues
func (m *Doomlab) BuildISOSimple(
	ctx context.Context,
	// Source directory containing the flake.nix
	source *dagger.Directory,
) *dagger.File {
	// Use the official NixOS container with forced x86_64 platform
	return dag.Container(dagger.ContainerOpts{Platform: dagger.Platform("linux/amd64")}).
		From("nixpkgs/nix:nixos-24.11").
		WithMountedDirectory("/workspace", source).
		WithWorkdir("/workspace").
		// Configure Nix to avoid sandboxing issues
		WithExec([]string{"sh", "-c", `
mkdir -p /etc/nix
cat > /etc/nix/nix.conf << 'EOF'
experimental-features = nix-command flakes
sandbox = false
restrict-eval = false
allow-unsafe-native-code-during-evaluation = true
substituters = https://cache.nixos.org
trusted-public-keys = cache.nixos.org-1:6NCHdD59X431o0gWypbMrAURkbJ16ZPMQFGspcDShjY=
EOF
		`}).
		// Simple build without complex monitoring
		WithExec([]string{"sh", "-c", `
set -e
echo "Building x86_64 NixOS ISO..."
nix build '.#nixosConfigurations.iso1chng.config.system.build.isoImage' \
    --out-link result \
    --option sandbox false \
    --option restrict-eval false

# Find and copy the ISO
find result -name '*.iso' -type f -exec cp {} /tmp/nixos.iso \;
ls -lh /tmp/nixos.iso
		`}).
		File("/tmp/nixos.iso")
}