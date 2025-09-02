// Networking Infrastructure for Dagger Services
// Provides container networking that integrates with existing NixOS network configuration
// Maintains compatibility with Nginx reverse proxy and Tailscale
package main

import (
	"dagger.io/dagger"
	"universe.dagger.io/bash"
	"universe.dagger.io/docker"
)

// Network management system for Dagger containers
#NetworkManager: {
	config: #NixOSConfig
	
	// Network definitions that align with NixOS configuration
	networks: {
		// Default Dagger network with DNS resolution
		default: #Network & {
			name: "dagger-default"
			driver: "bridge"
			dns_enabled: true
			internal: false
			_config: config
		}
		
		// Isolated network for sensitive services
		secure: #Network & {
			name: "dagger-secure"
			driver: "bridge"
			dns_enabled: true
			internal: true
			_config: config
		}
		
		// Host network for services requiring direct host access
		host: #Network & {
			name: "host"
			driver: "host"
			dns_enabled: false
			internal: false
			_config: config
		}
	}
	
	// Network setup and management
	setup: #NetworkSetup & {
		_networks: networks
		_config: config
	}
	
	// DNS configuration for containers
	dns: #DNSConfig & {
		_config: config
	}
	
	// Firewall integration
	firewall: #FirewallIntegration & {
		_config: config
	}
}

// Individual network definition
#Network: {
	name: string
	driver: "bridge" | "host" | "macvlan"
	dns_enabled: bool
	internal: bool
	_config: #NixOSConfig
	
	// Subnet configuration for bridge networks
	if driver == "bridge" {
		subnet?: string
		gateway?: string
	}
	
	// Additional options
	options?: [string]: string
	
	// Create the network
	create: bash.#Script & {
		script: """
			#!/bin/bash
			set -euo pipefail
			
			echo "Creating network: \(name)"
			
			# Check if network already exists
			if podman network exists \(name); then
				echo "Network \(name) already exists"
				exit 0
			fi
			
			# Build network creation command
			cmd="podman network create"
			cmd="$cmd --driver \(driver)"
			
			if [ "\(driver)" = "bridge" ]; then
				cmd="$cmd --dns-enabled=\(dns_enabled)"
				cmd="$cmd --internal=\(internal)"
				
				# Add subnet if specified
				if [ -n "\(subnet // "")" ]; then
					cmd="$cmd --subnet \(subnet)"
				fi
				
				# Add gateway if specified
				if [ -n "\(gateway // "")" ]; then
					cmd="$cmd --gateway \(gateway)"
				fi
			fi
			
			# Add additional options
			\(
				// Convert options to command line arguments
				if options != _|_ {
					strings.Join([for k, v in options {"-o \(k)=\(v)"}], " ")
				} else {
					""
				}
			)
			
			cmd="$cmd \(name)"
			
			echo "Executing: $cmd"
			eval "$cmd"
			
			echo "Network \(name) created successfully"
		"""
	}
	
	// Remove the network
	remove: bash.#Script & {
		script: """
			#!/bin/bash
			set -euo pipefail
			
			echo "Removing network: \(name)"
			
			if podman network exists \(name); then
				podman network rm \(name)
				echo "Network \(name) removed"
			else
				echo "Network \(name) does not exist"
			fi
		"""
	}
	
	// Inspect network configuration
	inspect: bash.#Script & {
		script: """
			#!/bin/bash
			set -euo pipefail
			
			echo "Inspecting network: \(name)"
			
			if podman network exists \(name); then
				podman network inspect \(name)
			else
				echo "Network \(name) does not exist"
				exit 1
			fi
		"""
	}
}

// Network setup and management pipeline
#NetworkSetup: {
	_networks: {...}
	_config: #NixOSConfig
	
	// Initialize all networks
	initialize: bash.#Script & {
		script: """
			#!/bin/bash
			set -euo pipefail
			
			echo "Initializing Dagger networks..."
			
			# Ensure Podman is running
			systemctl is-active --quiet podman.service || {
				echo "Starting Podman service..."
				systemctl start podman.service
			}
			
			# Create default bridge network with proper DNS
			if ! podman network exists dagger-default; then
				echo "Creating default Dagger network..."
				podman network create \
					--driver bridge \
					--dns-enabled=true \
					--internal=false \
					dagger-default
			fi
			
			# Create secure internal network  
			if ! podman network exists dagger-secure; then
				echo "Creating secure Dagger network..."
				podman network create \
					--driver bridge \
					--dns-enabled=true \
					--internal=true \
					dagger-secure
			fi
			
			# Verify networks
			echo "Available networks:"
			podman network ls
			
			echo "Network initialization completed"
		"""
	}
	
	// Cleanup networks
	cleanup: bash.#Script & {
		script: """
			#!/bin/bash
			set -euo pipefail
			
			echo "Cleaning up Dagger networks..."
			
			# Remove custom networks (preserve default networks)
			networks_to_remove=("dagger-default" "dagger-secure")
			
			for network in "''${networks_to_remove[@]}"; do
				if podman network exists "$network"; then
					# Stop any containers using the network first
					containers=$(podman ps -q --filter "network=$network" 2>/dev/null || true)
					if [ -n "$containers" ]; then
						echo "Stopping containers using network $network..."
						echo "$containers" | xargs -r podman stop
					fi
					
					echo "Removing network: $network"
					podman network rm "$network" 2>/dev/null || true
				fi
			done
			
			echo "Network cleanup completed"
		"""
	}
}

// DNS configuration for containers
#DNSConfig: {
	_config: #NixOSConfig
	
	// DNS servers that match NixOS configuration
	servers: [_config.network.dns.primary, _config.network.dns.secondary]
	
	// Search domains
	search: [_config.network.domain]
	
	// Generate DNS configuration for containers
	generateConfig: bash.#Script & {
		script: """
			#!/bin/bash
			set -euo pipefail
			
			echo "Generating DNS configuration for containers..."
			
			# Create DNS configuration
			cat > /tmp/dagger-dns-config << EOF
			# DNS configuration for Dagger containers
			# Generated from NixOS configuration
			
			nameserver \(_config.network.dns.primary)
			nameserver \(_config.network.dns.secondary)
			search \(_config.network.domain)
			
			# Options for better resolution
			options ndots:1
			options timeout:2
			options attempts:2
			EOF
			
			echo "DNS configuration generated:"
			cat /tmp/dagger-dns-config
		"""
	}
	
	// DNS options for container creation
	containerOptions: [
		"--dns=\(_config.network.dns.primary)",
		"--dns=\(_config.network.dns.secondary)",
		"--dns-search=\(_config.network.domain)",
	]
}

// Firewall integration for Dagger services
#FirewallIntegration: {
	_config: #NixOSConfig
	
	// Configure firewall rules for Dagger containers
	configureRules: bash.#Script & {
		script: """
			#!/bin/bash
			set -euo pipefail
			
			echo "Configuring firewall rules for Dagger containers..."
			
			# Allow container-to-container communication on Dagger networks
			# This integrates with existing NixOS firewall configuration
			
			# Get Dagger network subnets
			default_subnet=$(podman network inspect dagger-default --format '{{range .Subnets}}{{.Subnet}}{{end}}' 2>/dev/null || echo "")
			secure_subnet=$(podman network inspect dagger-secure --format '{{range .Subnets}}{{.Subnet}}{{end}}' 2>/dev/null || echo "")
			
			if [ -n "$default_subnet" ]; then
				echo "Allowing communication within Dagger default network: $default_subnet"
				# These rules are managed by NixOS firewall configuration
				# Just verify they're working
				iptables -C nixos-fw -s "$default_subnet" -d "$default_subnet" -j nixos-fw-accept 2>/dev/null || {
					echo "Note: Dagger network rules should be managed by NixOS firewall configuration"
				}
			fi
			
			# Allow access from local network to container services (matching existing homebridge/scrypted rules)
			local_network="\(_config.network.localNetwork)"
			echo "Verifying local network access rules for: $local_network"
			
			# These rules should be managed by the NixOS firewall configuration
			iptables -C nixos-fw -p tcp --source "$local_network" -j nixos-fw-accept 2>/dev/null && {
				echo "✓ Local network access rules are active"
			} || {
				echo "⚠ Local network access rules not found - ensure NixOS firewall is configured"
			}
			
			echo "Firewall integration check completed"
		"""
	}
}

// Container network attachment helpers
#ContainerNetwork: {
	container: string
	network: string
	_config: #NixOSConfig
	
	// Attach container to network
	attach: bash.#Script & {
		script: """
			#!/bin/bash
			set -euo pipefail
			
			echo "Attaching container \(container) to network \(network)..."
			
			# Check if container exists
			if ! podman container exists \(container); then
				echo "Container \(container) does not exist"
				exit 1
			fi
			
			# Check if network exists
			if ! podman network exists \(network); then
				echo "Network \(network) does not exist"
				exit 1
			fi
			
			# Attach to network
			podman network connect \(network) \(container)
			echo "Container \(container) attached to network \(network)"
		"""
	}
	
	// Detach container from network
	detach: bash.#Script & {
		script: """
			#!/bin/bash
			set -euo pipefail
			
			echo "Detaching container \(container) from network \(network)..."
			
			if podman container exists \(container) && podman network exists \(network); then
				podman network disconnect \(network) \(container) 2>/dev/null || true
				echo "Container \(container) detached from network \(network)"
			else
				echo "Container or network does not exist, skipping detach"
			fi
		"""
	}
}

// Port mapping helpers that integrate with Nginx reverse proxy
#PortMapping: {
	service: string
	internal_port: int
	external_port: int
	_config: #NixOSConfig
	
	// Generate port mapping configuration
	generateMapping: {
		// Standard port mapping for Podman
		podman: "\(external_port):\(internal_port)"
		
		// Nginx upstream configuration (for reverse proxy integration)
		nginx: {
			upstream: "127.0.0.1:\(external_port)"
			server_name: "\(service).\(_config.network.domain)"
		}
		
		// Health check endpoint
		health_check: "http://127.0.0.1:\(external_port)/health"
	}
}

// Service discovery for Dagger containers
#ServiceDiscovery: {
	_config: #NixOSConfig
	
	// Register service for discovery
	register: {
		service: string
		port: int
		
		script: bash.#Script & {
			script: """
				#!/bin/bash
				set -euo pipefail
				
				echo "Registering service \(service) on port \(port)..."
				
				# Create service registry entry
				registry_dir="/var/lib/dagger/registry"
				mkdir -p "$registry_dir"
				
				cat > "$registry_dir/\(service).json" << EOF
				{
					"service": "\(service)",
					"port": \(port),
					"domain": "\(service).\(_config.network.domain)",
					"internal_endpoint": "http://127.0.0.1:\(port)",
					"external_endpoint": "https://\(service).\(_config.network.domain)",
					"registered_at": "$(date -Iseconds)"
				}
				EOF
				
				echo "Service \(service) registered successfully"
			"""
		}
	}
	
	// Discover available services
	discover: bash.#Script & {
		script: """
			#!/bin/bash
			set -euo pipefail
			
			echo "Discovering registered Dagger services..."
			
			registry_dir="/var/lib/dagger/registry"
			
			if [ -d "$registry_dir" ]; then
				echo "Registered services:"
				for service_file in "$registry_dir"/*.json; do
					if [ -f "$service_file" ]; then
						service=$(jq -r '.service' "$service_file")
						port=$(jq -r '.port' "$service_file")
						domain=$(jq -r '.domain' "$service_file")
						
						echo "  $service: $domain (port $port)"
					fi
				done
			else
				echo "No services registered yet"
			fi
		"""
	}
}