// Doomlab Homelab - Main Dagger Pipeline
// Integrates with NixOS flake-based infrastructure for declarative container management
package main

import (
	"dagger.io/dagger"
	"dagger.io/dagger/core"
	"universe.dagger.io/alpine"
	"universe.dagger.io/bash"
	"universe.dagger.io/docker"
)

// DoomlabServices represents the complete homelab service stack
#DoomlabServices: {
	// Core configuration from NixOS
	config: #NixOSConfig
	
	// Services managed by Dagger
	services: {
		// Media services (currently handled by nixarr)
		media: #MediaServices & {_config: config}
		
		// Home automation services  
		automation: #AutomationServices & {_config: config}
		
		// Infrastructure services
		infrastructure: #InfrastructureServices & {_config: config}
	}
	
	// Build and deployment pipeline
	pipeline: #Pipeline & {
		_services: services
		_config: config
	}
}

// NixOS configuration bridge - integrates with existing SOPS and networking
#NixOSConfig: {
	// Secrets management via SOPS bridge
	secrets: {
		// Cloudflare API for ACME certificates
		cloudflare: {
			email: string | *""
			apiKey: string | *""
		}
		
		// Kopia backup tokens
		kopia: {
			repositoryToken: string | *""
		}
		
		// Service-specific secrets
		transmission: {
			rpcPassword: string | *""
		}
	}
	
	// Network configuration that matches NixOS setup
	network: {
		domain: string | *"orther.dev"
		tailscaleNetwork: string | *"100.64.0.0/10"
		localNetwork: string | *"10.0.10.0/24" 
		
		// DNS configuration for containers
		dns: {
			primary: string | *"1.1.1.1"
			secondary: string | *"1.0.0.1"
		}
	}
	
	// Storage paths that align with NixOS persistence
	storage: {
		persistRoot: string | *"/nix/persist"
		mediaRoot: string | *"/fun"
		stateRoot: string | *"/var/lib"
	}
	
	// Service ports that match current nginx proxy config
	ports: {
		jellyfin: int | *8096
		prowlarr: int | *9696
		radarr: int | *7878
		sonarr: int | *8989
		transmission: int | *9091
		homebridge: int | *8581
		scrypted: int | *10443
	}
}

// Media services pipeline - enhanced nixarr services via Dagger
#MediaServices: {
	_config: #NixOSConfig
	
	// Complete nixarr suite with Dagger enhancements
	nixarr: #NixarrSuite & {config: _config}
	
	// Additional container-based services that benefit from Dagger management
	containers: {
		// Custom media processing workflows
		transcoding: #TranscodingPipeline & {config: _config}
		
		// Advanced monitoring and analytics  
		monitoring: #MediaMonitoring & {config: _config}
		
		// Backup orchestration
		backup: #BackupOrchestration & {config: _config}
	}
}

// Home automation services - replaces current podman containers
#AutomationServices: {
	_config: #NixOSConfig
	
	// Homebridge with enhanced CI/CD
	homebridge: #HomebridgeService & {config: _config}
	
	// Scrypted with enhanced management
	scrypted: #ScryptedService & {config: _config}
	
	// Custom automation workflows
	workflows: #AutomationWorkflows & {config: _config}
}

// Infrastructure services for enhanced operations
#InfrastructureServices: {
	_config: #NixOSConfig
	
	// Enhanced monitoring beyond netdata
	monitoring: #MonitoringStack & {config: _config}
	
	// Backup coordination across services
	backup: #BackupCoordinator & {config: _config}
	
	// Security scanning and compliance
	security: #SecurityServices & {config: _config}
}

// Main pipeline orchestrator
#Pipeline: {
	_services: {...}
	_config: #NixOSConfig
	
	// Build pipeline with Nix integration
	build: #BuildPipeline & {
		services: _services
		config: _config
	}
	
	// Deployment pipeline coordinated with NixOS
	deploy: #DeployPipeline & {
		services: _services 
		config: _config
	}
	
	// Testing pipeline with container validation
	test: #TestPipeline & {
		services: _services
		config: _config
	}
}

// Expose main dagger actions
dagger.#Plan & {
	actions: {
		// Build all services
		build: _services.pipeline.build
		
		// Deploy services (coordinates with NixOS systemd)
		deploy: _services.pipeline.deploy
		
		// Run tests
		test: _services.pipeline.test
		
		// Individual service management
		services: {
			media: _services.services.media
			automation: _services.services.automation
			infrastructure: _services.services.infrastructure
		}
		
		// Direct nixarr service access
		nixarr: _services.services.media.nixarr
	}
}

// Default configuration for development
_services: #DoomlabServices & {
	config: {
		secrets: {
			// These will be injected from SOPS via NixOS bridge
			cloudflare: {
				email: ""
				apiKey: ""
			}
		}
		network: {
			domain: "orther.dev"
		}
	}
}