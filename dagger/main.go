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