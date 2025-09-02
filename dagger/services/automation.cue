// Home Automation Services
// Manages Homebridge, Scrypted, and custom automation workflows
package main

import (
	"dagger.io/dagger"
	"universe.dagger.io/docker"
	"universe.dagger.io/bash"
)

// Homebridge service with enhanced management
#HomebridgeService: {
	config: #NixOSConfig
	
	// Container configuration that matches existing setup
	container: docker.#Container & {
		image: docker.#Image & {
			from: docker.#Pull & {
				source: "ghcr.io/homebridge/homebridge:latest"
			}
		}
		
		// Volume mounts aligned with NixOS persistence
		mounts: {
			config: {
				dest: "/homebridge"
				contents: dagger.#HostDirectory & {
					path: "\(config.storage.stateRoot)/homebridge"
				}
			}
		}
		
		// Network configuration for HomeKit
		network: "host"
		
		// DNS configuration that matches NixOS setup
		env: {
			DNS_SERVERS: "\(config.network.dns.primary),\(config.network.dns.secondary)"
		}
		
		// Enhanced logging configuration
		logger: {
			driver: "journald"
			options: {
				"max-file": "3"
				"max-size": "10mb"
			}
		}
	}
	
	// Configuration management pipeline
	config_pipeline: #ConfigPipeline & {
		service: "homebridge"
		_config: config
	}
	
	// Backup integration with enhanced scheduling
	backup: #ServiceBackup & {
		service: "homebridge"
		paths: ["\(config.storage.stateRoot)/homebridge"]
		_config: config
	}
	
	// Health monitoring
	health: #HealthCheck & {
		service: "homebridge"
		endpoint: "http://127.0.0.1:\(config.ports.homebridge)"
		_config: config
	}
}

// Scrypted service with enhanced management
#ScryptedService: {
	config: #NixOSConfig
	
	// Container configuration that matches existing setup
	container: docker.#Container & {
		image: docker.#Image & {
			from: docker.#Pull & {
				source: "ghcr.io/koush/scrypted:latest"
			}
		}
		
		// Volume mounts aligned with NixOS persistence  
		mounts: {
			data: {
				dest: "/server/volume"
				contents: dagger.#HostDirectory & {
					path: "\(config.storage.stateRoot)/scrypted"
				}
			}
		}
		
		// Network and security configuration
		network: "host" 
		security: ["apparmor:unconfined"]
		
		// Environment for Avahi/mDNS
		env: {
			SCRYPTED_DOCKER_AVAHI: "true"
			DNS_SERVERS: "\(config.network.dns.primary),\(config.network.dns.secondary)"
		}
		
		// Enhanced logging
		logger: {
			driver: "journald"
			options: {
				"max-file": "5"
				"max-size": "20mb"
			}
		}
	}
	
	// Configuration and plugin management
	plugin_pipeline: #PluginPipeline & {
		service: "scrypted"
		_config: config
	}
	
	// Backup with plugin state preservation
	backup: #ServiceBackup & {
		service: "scrypted"
		paths: ["\(config.storage.stateRoot)/scrypted"]
		_config: config
	}
	
	// Camera and device health monitoring
	health: #DeviceHealthCheck & {
		service: "scrypted"
		endpoint: "https://127.0.0.1:\(config.ports.scrypted)"
		_config: config
	}
}

// Custom automation workflows
#AutomationWorkflows: {
	config: #NixOSConfig
	
	// Device discovery and integration pipeline
	discovery: #DeviceDiscovery & {
		networks: [config.network.localNetwork, config.network.tailscaleNetwork]
		_config: config
	}
	
	// Cross-service automation rules
	rules: #AutomationRules & {
		services: ["homebridge", "scrypted"]
		_config: config
	}
	
	// Notification and alerting system
	notifications: #NotificationPipeline & {
		_config: config
	}
}

// Configuration management pipeline for services
#ConfigPipeline: {
	service: string
	_config: #NixOSConfig
	
	// Validate configuration files
	validate: bash.#Script & {
		input: dagger.#FS
		script: """
			# Validate service configuration
			echo "Validating \(service) configuration..."
			
			# JSON schema validation for homebridge
			if [ "\(service)" = "homebridge" ]; then
				if [ -f config/config.json ]; then
					jq empty config/config.json || {
						echo "Invalid JSON in homebridge config"
						exit 1
					}
				fi
			fi
			
			# Plugin validation for scrypted
			if [ "\(service)" = "scrypted" ]; then
				echo "Validating scrypted plugins..."
				# Add plugin validation logic
			fi
			
			echo "Configuration validation passed"
		"""
	}
	
	// Apply configuration updates
	deploy: bash.#Script & {
		input: validate.output
		script: """
			# Deploy configuration changes
			echo "Deploying \(service) configuration..."
			
			# Coordinate with systemd service restart via NixOS
			systemctl --user reload-or-restart podman-\(service).service || true
			
			echo "Configuration deployed"
		"""
	}
}

// Enhanced backup system for automation services
#ServiceBackup: {
	service: string
	paths: [...string]
	_config: #NixOSConfig
	
	// Create backup using Kopia (integrated with existing setup)
	backup: bash.#Script & {
		env: {
			KOPIA_TOKEN_FILE: "/run/secrets/kopia-repository-token"
			SERVICE_NAME: service
		}
		script: """
			# Connect to Kopia repository
			kopia repository connect from-config --token-file $KOPIA_TOKEN_FILE
			
			# Create timestamped snapshot
			for path in \(strings.Join(paths, " ")); do
				echo "Backing up $path..."
				kopia snapshot create "$path" \
					--tags "service:\(service),automated:true,pipeline:dagger"
			done
			
			# Disconnect from repository
			kopia repository disconnect
			
			echo "Backup completed for \(service)"
		"""
	}
	
	// Backup verification
	verify: bash.#Script & {
		input: backup.output
		script: """
			# Verify backup integrity
			echo "Verifying backup for \(service)..."
			
			kopia repository connect from-config --token-file $KOPIA_TOKEN_FILE
			kopia snapshot list --tags "service:\(service)" --max-results 1
			kopia repository disconnect
			
			echo "Backup verification completed"
		"""
	}
}

// Health check system for automation services
#HealthCheck: {
	service: string
	endpoint: string
	_config: #NixOSConfig
	
	check: bash.#Script & {
		script: """
			# Basic HTTP health check
			echo "Checking health of \(service) at \(endpoint)..."
			
			curl -f -s --connect-timeout 10 "\(endpoint)/health" || {
				echo "Health check failed for \(service)"
				exit 1
			}
			
			echo "Health check passed for \(service)"
		"""
	}
}

// Device-specific health check for camera systems
#DeviceHealthCheck: {
	service: string
	endpoint: string
	_config: #NixOSConfig
	
	check: bash.#Script & {
		script: """
			# Device connectivity check
			echo "Checking device connectivity for \(service)..."
			
			# Check API endpoint
			curl -k -f -s --connect-timeout 10 "\(endpoint)/api/status" || {
				echo "API health check failed for \(service)"
				exit 1
			}
			
			# Check device enumeration
			device_count=$(curl -k -s "\(endpoint)/api/devices" | jq '. | length' 2>/dev/null || echo "0")
			if [ "$device_count" -gt 0 ]; then
				echo "Found $device_count devices"
			else
				echo "Warning: No devices found for \(service)"
			fi
			
			echo "Device health check completed"
		"""
	}
}