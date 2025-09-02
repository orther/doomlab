// A generated module for Doomlab functions

package main

import (
	"context"
	"strings"
)

type Doomlab struct{}

// GetMachineList returns all available machine configurations
func (m *Doomlab) GetMachineList(
	ctx context.Context,
) string {
	nixOSMachines := []string{
		"workchng", "dsk1chng", "svr1chng", "svr2chng", "svr3chng",
		"noir", "zinc", "vmnixos", "iso1chng",
	}
	
	darwinMachines := []string{
		"mair", "mac1chng",
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