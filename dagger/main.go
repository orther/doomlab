// A generated module for Doomlab functions
//
// This module has been generated via dagger init and serves as a reference to
// basic module structure as you get started with Dagger.
//
// Two functions have been pre-created. You can modify, delete, or add to them,
// as needed. They demonstrate usage of arguments and return types using simple
// echo and grep commands. The functions can be called from the dagger CLI or
// from one of the SDKs.
//
// The first line in this comment block is a short description line and the
// rest is a long description with more detail on the module's purpose or usage,
// if appropriate. All modules should have a short description.

package main

import (
	"context"
	"strings"
)

type Doomlab struct{}

// NixOSMachines defines all available machine configurations
var nixOSMachines = []string{
	"workchng", "dsk1chng", "svr1chng", "svr2chng", "svr3chng",
	"noir", "zinc", "vmnixos", "iso1chng",
}

// DarwinMachines defines all available Darwin machine configurations  
var darwinMachines = []string{
	"mair", "mac1chng",
}

// Lint runs nix flake check to validate all configurations
func (m *Doomlab) Lint(
	ctx context.Context,
	// Source directory containing the flake
	source *Directory,
) *Container {
	return dag.Container().
		From("nixos/nix:latest").
		WithDirectory("/src", source).
		WithWorkdir("/src").
		WithExec([]string{"mkdir", "-p", "/etc/nix"}).
		WithNewFile("/etc/nix/nix.conf", `
extra-experimental-features = nix-command flakes
substituters = https://cache.nixos.org https://nix-community.cachix.org
trusted-public-keys = cache.nixos.org-1:6NCHdD59X431o0gWypbMrAURkbJ16ZPMQFGspcDShjY= nix-community.cachix.org-1:mB9FSh9qf2dCimDSUo8Zy7bkq5CX+/rkCWyvRCYg3Fs=
`).
		WithExec([]string{"nix", "flake", "check", "--no-build"})
}

// CheckFormat checks if Nix code is properly formatted
func (m *Doomlab) CheckFormat(
	ctx context.Context,
	// Source directory containing the flake
	source *Directory,
) *Container {
	return dag.Container().
		From("nixos/nix:latest").
		WithDirectory("/src", source).
		WithWorkdir("/src").
		WithExec([]string{"mkdir", "-p", "/etc/nix"}).
		WithNewFile("/etc/nix/nix.conf", `
extra-experimental-features = nix-command flakes
substituters = https://cache.nixos.org https://nix-community.cachix.org
trusted-public-keys = cache.nixos.org-1:6NCHdD59X431o0gWypbMrAURkbJ16ZPMQFGspcDShjY= nix-community.cachix.org-1:mB9FSh9qf2dCimDSUo8Zy7bkq5CX+/rkCWyvRCYg3Fs=
`).
		WithExec([]string{"cp", "-r", "/src", "/src-original"}).
		WithExec([]string{"nix", "fmt"}).
		WithExec([]string{"diff", "-r", "/src-original", "/src"})
}

// GetMachineList returns all available machine configurations
func (m *Doomlab) GetMachineList(ctx context.Context) string {
	allMachines := append(nixOSMachines, darwinMachines...)
	return strings.Join(allMachines, "\n")
}