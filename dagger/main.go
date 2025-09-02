// Package main provides Dagger pipeline functions for the doomlab NixOS flake
package main

import (
	"context"
	"fmt"
	"strings"
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

// Lint runs nix flake check to validate all configurations
func (m *Doomlab) Lint(
	ctx context.Context,
	// Source directory containing the flake
	source any,
) any {
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

// CheckFormat checks if Nix code is properly formatted by formatting and checking for differences
func (m *Doomlab) CheckFormat(
	ctx context.Context,
	// Source directory containing the flake
	source any,
) any {
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
func (m *Doomlab) GetMachineList(
	ctx context.Context,
) string {
	allMachines := append(NixOSMachines, DarwinMachines...)
	return strings.Join(allMachines, "\n")
}