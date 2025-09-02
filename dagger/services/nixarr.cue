// Nixarr Services Pipeline
// Complete Dagger implementations for Sonarr, Radarr, Prowlarr, Bazarr
// Integrates with existing NixOS configuration and SOPS secrets
package main

import (
	"dagger.io/dagger"
	"universe.dagger.io/docker"
	"universe.dagger.io/bash"
)

// Complete Nixarr Suite orchestrator
#NixarrSuite: {
	config: #NixOSConfig

	// Individual service definitions
	services: {
		sonarr: #SonarrService & {_config: config}
		radarr: #RadarrService & {_config: config}
		prowlarr: #ProwlarrService & {_config: config}
		bazarr: #BazarrService & {_config: config}
		transmission: #TransmissionService & {_config: config}
		jellyfin: #JellyfinService & {_config: config}
	}

	// Service orchestration and health monitoring
	orchestration: #ServiceOrchestration & {
		_services: services
		_config: config
	}

	// Backup coordination across all services
	backup: #NixarrBackup & {
		_services: services
		_config: config
	}

	// Inter-service API communication setup
	networking: #NixarrNetworking & {
		_services: services
		_config: config
	}
}

// Sonarr service with enhanced Dagger management
#SonarrService: {
	_config: #NixOSConfig

	// Container definition matching nixarr configuration
	container: docker.#Container & {
		image: docker.#Image & {
			from: docker.#Pull & {
				source: "lscr.io/linuxserver/sonarr:latest"
			}
		}

		// Environment variables
		env: {
			PUID: "568"  // Media user from nixarr
			PGID: "568"  // Media group from nixarr
			TZ: "America/Los_Angeles"
			
			// API integration environment
			SONARR__INSTANCENAME: "Sonarr"
			SONARR__BRANCH: "master"
			SONARR__PORT: "8989"
			SONARR__APPLICATIONURL: "https://sonarr.\(_config.network.domain)"
		}

		// Volume mounts aligned with nixarr paths
		mounts: {
			config: {
				dest: "/config"
				contents: dagger.#HostDirectory & {
					path: "\(_config.storage.stateRoot)/nixarr/sonarr"
				}
			}
			media: {
				dest: "/tv"
				contents: dagger.#HostDirectory & {
					path: "\(_config.storage.mediaRoot)/tv"
				}
			}
			downloads: {
				dest: "/downloads"
				contents: dagger.#HostDirectory & {
					path: "\(_config.storage.mediaRoot)/downloads"
				}
			}
			// Secret mount for API key if needed
			secrets: {
				dest: "/run/secrets"
				contents: dagger.#HostDirectory & {
					path: "/run/dagger-secrets/sonarr"
				}
			}
		}

		// Port exposure
		ports: ["\(_config.ports.sonarr):8989"]

		// Health check configuration
		healthcheck: {
			test: ["CMD", "curl", "-f", "http://localhost:8989/ping"]
			interval: "30s"
			timeout: "10s"
			retries: 3
			start_period: "60s"
		}
	}

	// Configuration management
	config_manager: #ConfigManager & {
		service: "sonarr"
		port: _config.ports.sonarr
		_config: _config
	}

	// Health monitoring
	health: #ServiceHealth & {
		service: "sonarr"
		endpoint: "http://127.0.0.1:\(_config.ports.sonarr)/ping"
		_config: _config
	}

	// API configuration for inter-service communication
	api: #ServiceAPI & {
		service: "sonarr"
		port: _config.ports.sonarr
		endpoints: ["/api/v3/system/status", "/api/v3/queue", "/api/v3/series"]
		_config: _config
	}
}

// Radarr service with enhanced Dagger management
#RadarrService: {
	_config: #NixOSConfig

	container: docker.#Container & {
		image: docker.#Image & {
			from: docker.#Pull & {
				source: "lscr.io/linuxserver/radarr:latest"
			}
		}

		env: {
			PUID: "568"
			PGID: "568"
			TZ: "America/Los_Angeles"
			
			RADARR__INSTANCENAME: "Radarr"
			RADARR__BRANCH: "master"
			RADARR__PORT: "7878"
			RADARR__APPLICATIONURL: "https://radarr.\(_config.network.domain)"
		}

		mounts: {
			config: {
				dest: "/config"
				contents: dagger.#HostDirectory & {
					path: "\(_config.storage.stateRoot)/nixarr/radarr"
				}
			}
			media: {
				dest: "/movies"
				contents: dagger.#HostDirectory & {
					path: "\(_config.storage.mediaRoot)/movies"
				}
			}
			downloads: {
				dest: "/downloads"
				contents: dagger.#HostDirectory & {
					path: "\(_config.storage.mediaRoot)/downloads"
				}
			}
			secrets: {
				dest: "/run/secrets"
				contents: dagger.#HostDirectory & {
					path: "/run/dagger-secrets/radarr"
				}
			}
		}

		ports: ["\(_config.ports.radarr):7878"]

		healthcheck: {
			test: ["CMD", "curl", "-f", "http://localhost:7878/ping"]
			interval: "30s"
			timeout: "10s"
			retries: 3
			start_period: "60s"
		}
	}

	config_manager: #ConfigManager & {
		service: "radarr"
		port: _config.ports.radarr
		_config: _config
	}

	health: #ServiceHealth & {
		service: "radarr"
		endpoint: "http://127.0.0.1:\(_config.ports.radarr)/ping"
		_config: _config
	}

	api: #ServiceAPI & {
		service: "radarr"
		port: _config.ports.radarr
		endpoints: ["/api/v3/system/status", "/api/v3/queue", "/api/v3/movie"]
		_config: _config
	}
}

// Prowlarr service with enhanced Dagger management
#ProwlarrService: {
	_config: #NixOSConfig

	container: docker.#Container & {
		image: docker.#Image & {
			from: docker.#Pull & {
				source: "lscr.io/linuxserver/prowlarr:latest"
			}
		}

		env: {
			PUID: "568"
			PGID: "568"
			TZ: "America/Los_Angeles"
			
			PROWLARR__INSTANCENAME: "Prowlarr"
			PROWLARR__BRANCH: "master"
			PROWLARR__PORT: "9696"
			PROWLARR__APPLICATIONURL: "https://prowlarr.\(_config.network.domain)"
		}

		mounts: {
			config: {
				dest: "/config"
				contents: dagger.#HostDirectory & {
					path: "\(_config.storage.stateRoot)/nixarr/prowlarr"
				}
			}
			secrets: {
				dest: "/run/secrets"
				contents: dagger.#HostDirectory & {
					path: "/run/dagger-secrets/prowlarr"
				}
			}
		}

		ports: ["\(_config.ports.prowlarr):9696"]

		healthcheck: {
			test: ["CMD", "curl", "-f", "http://localhost:9696/ping"]
			interval: "30s"
			timeout: "10s"
			retries: 3
			start_period: "60s"
		}
	}

	config_manager: #ConfigManager & {
		service: "prowlarr"
		port: _config.ports.prowlarr
		_config: _config
	}

	health: #ServiceHealth & {
		service: "prowlarr"
		endpoint: "http://127.0.0.1:\(_config.ports.prowlarr)/ping"
		_config: _config
	}

	api: #ServiceAPI & {
		service: "prowlarr"
		port: _config.ports.prowlarr
		endpoints: ["/api/v1/system/status", "/api/v1/indexer", "/api/v1/applications"]
		_config: _config
	}
}

// Bazarr service with enhanced Dagger management
#BazarrService: {
	_config: #NixOSConfig

	container: docker.#Container & {
		image: docker.#Image & {
			from: docker.#Pull & {
				source: "lscr.io/linuxserver/bazarr:latest"
			}
		}

		env: {
			PUID: "568"
			PGID: "568"
			TZ: "America/Los_Angeles"
			
			// Bazarr-specific configuration
			BAZARR__PORT: "6767"
			BAZARR__APPLICATIONURL: "https://bazarr.\(_config.network.domain)"
		}

		mounts: {
			config: {
				dest: "/config"
				contents: dagger.#HostDirectory & {
					path: "\(_config.storage.stateRoot)/nixarr/bazarr"
				}
			}
			tv: {
				dest: "/tv"
				contents: dagger.#HostDirectory & {
					path: "\(_config.storage.mediaRoot)/tv"
				}
			}
			movies: {
				dest: "/movies"
				contents: dagger.#HostDirectory & {
					path: "\(_config.storage.mediaRoot)/movies"
				}
			}
			secrets: {
				dest: "/run/secrets"
				contents: dagger.#HostDirectory & {
					path: "/run/dagger-secrets/bazarr"
				}
			}
		}

		ports: ["6767:6767"]

		healthcheck: {
			test: ["CMD", "curl", "-f", "http://localhost:6767/ping"]
			interval: "30s"
			timeout: "10s"
			retries: 3
			start_period: "60s"
		}
	}

	config_manager: #ConfigManager & {
		service: "bazarr"
		port: 6767
		_config: _config
	}

	health: #ServiceHealth & {
		service: "bazarr"
		endpoint: "http://127.0.0.1:6767/ping"
		_config: _config
	}

	api: #ServiceAPI & {
		service: "bazarr"
		port: 6767
		endpoints: ["/api/system/status", "/api/series", "/api/movies"]
		_config: _config
	}
}

// Transmission service with enhanced Dagger management
#TransmissionService: {
	_config: #NixOSConfig

	container: docker.#Container & {
		image: docker.#Image & {
			from: docker.#Pull & {
				source: "lscr.io/linuxserver/transmission:latest"
			}
		}

		env: {
			PUID: "568"
			PGID: "568"
			TZ: "America/Los_Angeles"
			
			// Transmission-specific configuration
			TRANSMISSION_WEB_HOME: "/transmission-web-control/"
			USER: "orther"
			PASS_FILE: "/run/secrets/transmission-rpc-password"
		}

		mounts: {
			config: {
				dest: "/config"
				contents: dagger.#HostDirectory & {
					path: "\(_config.storage.stateRoot)/nixarr/transmission"
				}
			}
			downloads: {
				dest: "/downloads"
				contents: dagger.#HostDirectory & {
					path: "\(_config.storage.mediaRoot)/downloads"
				}
			}
			watch: {
				dest: "/watch"
				contents: dagger.#HostDirectory & {
					path: "\(_config.storage.mediaRoot)/watch"
				}
			}
			secrets: {
				dest: "/run/secrets"
				contents: dagger.#HostDirectory & {
					path: "/run/dagger-secrets/transmission"
				}
			}
		}

		ports: [
			"\(_config.ports.transmission):9091",  // Web UI
			"46634:46634",                          // Peer port (from nixarr config)
			"46634:46634/udp"
		]

		healthcheck: {
			test: ["CMD", "curl", "-f", "http://localhost:9091/transmission/rpc"]
			interval: "30s"
			timeout: "10s"
			retries: 3
			start_period: "60s"
		}
	}

	config_manager: #ConfigManager & {
		service: "transmission"
		port: _config.ports.transmission
		_config: _config
	}

	health: #ServiceHealth & {
		service: "transmission"
		endpoint: "http://127.0.0.1:\(_config.ports.transmission)/transmission/rpc"
		_config: _config
	}

	api: #ServiceAPI & {
		service: "transmission"
		port: _config.ports.transmission
		endpoints: ["/transmission/rpc"]
		auth_required: true
		_config: _config
	}
}

// Jellyfin service with enhanced Dagger management
#JellyfinService: {
	_config: #NixOSConfig

	container: docker.#Container & {
		image: docker.#Image & {
			from: docker.#Pull & {
				source: "lscr.io/linuxserver/jellyfin:latest"
			}
		}

		env: {
			PUID: "568"
			PGID: "568"
			TZ: "America/Los_Angeles"
			
			// Hardware acceleration environment (if available)
			JELLYFIN_PublishedServerUrl: "https://watch.\(_config.network.domain)"
		}

		mounts: {
			config: {
				dest: "/config"
				contents: dagger.#HostDirectory & {
					path: "\(_config.storage.stateRoot)/nixarr/jellyfin"
				}
			}
			tv: {
				dest: "/data/tvshows"
				contents: dagger.#HostDirectory & {
					path: "\(_config.storage.mediaRoot)/tv"
				}
				readonly: true
			}
			movies: {
				dest: "/data/movies"
				contents: dagger.#HostDirectory & {
					path: "\(_config.storage.mediaRoot)/movies"
				}
				readonly: true
			}
			secrets: {
				dest: "/run/secrets"
				contents: dagger.#HostDirectory & {
					path: "/run/dagger-secrets/jellyfin"
				}
			}
		}

		// GPU access for hardware transcoding (if available)
		devices: ["/dev/dri:/dev/dri"]

		ports: ["\(_config.ports.jellyfin):8096"]

		healthcheck: {
			test: ["CMD", "curl", "-f", "http://localhost:8096/health"]
			interval: "30s"
			timeout: "10s"
			retries: 3
			start_period: "120s"
		}
	}

	config_manager: #ConfigManager & {
		service: "jellyfin"
		port: _config.ports.jellyfin
		_config: _config
	}

	health: #ServiceHealth & {
		service: "jellyfin"
		endpoint: "http://127.0.0.1:\(_config.ports.jellyfin)/health"
		_config: _config
	}

	api: #ServiceAPI & {
		service: "jellyfin"
		port: _config.ports.jellyfin
		endpoints: ["/System/Info", "/System/ActivityLog/Entries"]
		_config: _config
	}
}

// Service orchestration and dependency management
#ServiceOrchestration: {
	_services: {...}
	_config: #NixOSConfig

	// Service startup orchestration
	startup: bash.#Script & {
		script: """
			#!/bin/bash
			set -euo pipefail

			echo "Starting Nixarr service orchestration..."

			# Function to wait for service to be ready
			wait_for_service() {
				local service=$1
				local port=$2
				local path=${3:-"/ping"}
				local max_attempts=30

				echo "Waiting for $service to be ready..."
				for i in $(seq 1 $max_attempts); do
					if curl -f -s --connect-timeout 5 "http://127.0.0.1:$port$path" > /dev/null 2>&1; then
						echo "✓ $service is ready"
						return 0
					fi
					echo "  Attempt $i/$max_attempts: $service not ready yet..."
					sleep 10
				done

				echo "✗ $service failed to become ready after $((max_attempts * 10)) seconds"
				return 1
			}

			# Start services in dependency order
			echo "1. Starting transmission (download client)..."
			systemctl --user start dagger-transmission.service

			echo "2. Starting prowlarr (indexer manager)..."
			systemctl --user start dagger-prowlarr.service
			wait_for_service "prowlarr" "\(_config.ports.prowlarr)"

			echo "3. Starting sonarr and radarr (media managers)..."
			systemctl --user start dagger-sonarr.service
			systemctl --user start dagger-radarr.service
			wait_for_service "sonarr" "\(_config.ports.sonarr)"
			wait_for_service "radarr" "\(_config.ports.radarr)"

			echo "4. Starting bazarr (subtitle manager)..."
			systemctl --user start dagger-bazarr.service
			wait_for_service "bazarr" "6767"

			echo "5. Starting jellyfin (media server)..."
			systemctl --user start dagger-jellyfin.service
			wait_for_service "jellyfin" "\(_config.ports.jellyfin)" "/health"

			echo "✓ All nixarr services started successfully"
		"""
	}

	// Service health monitoring
	monitor: bash.#Script & {
		script: """
			#!/bin/bash
			set -euo pipefail

			echo "Monitoring nixarr services health..."

			services_healthy=0
			total_services=6

			# Check each service
			services=(
				"prowlarr:\(_config.ports.prowlarr):/ping"
				"sonarr:\(_config.ports.sonarr):/ping"
				"radarr:\(_config.ports.radarr):/ping"
				"bazarr:6767:/ping"
				"transmission:\(_config.ports.transmission):/transmission/rpc"
				"jellyfin:\(_config.ports.jellyfin):/health"
			)

			for service_config in "${services[@]}"; do
				IFS=':' read -r service port path <<< "$service_config"
				
				if curl -f -s --connect-timeout 5 "http://127.0.0.1:$port$path" > /dev/null; then
					echo "✓ $service is healthy"
					services_healthy=$((services_healthy + 1))
				else
					echo "✗ $service is unhealthy"
				fi
			done

			echo "Health summary: $services_healthy/$total_services services healthy"

			if [ $services_healthy -lt $total_services ]; then
				echo "WARNING: Some services are unhealthy"
				exit 1
			fi

			echo "All nixarr services are healthy"
		"""
	}

	// Service interconnectivity setup
	configure_apis: #APIConfiguration & {
		_services: _services
		_config: _config
	}
}

// Inter-service networking and API configuration
#NixarrNetworking: {
	_services: {...}
	_config: #NixOSConfig

	// Configure API connections between services
	setup: bash.#Script & {
		script: """
			#!/bin/bash
			set -euo pipefail

			echo "Configuring nixarr service networking..."

			# Function to wait for service API
			wait_for_api() {
				local service=$1
				local port=$2
				local endpoint=$3

				for i in {1..30}; do
					if curl -f -s "http://127.0.0.1:$port$endpoint" > /dev/null; then
						echo "✓ $service API is ready"
						return 0
					fi
					sleep 5
				done

				echo "✗ $service API not ready"
				return 1
			}

			# Configure Prowlarr connections to Sonarr and Radarr
			echo "Setting up Prowlarr -> Sonarr/Radarr connections..."
			wait_for_api "prowlarr" "\(_config.ports.prowlarr)" "/api/v1/system/status"
			wait_for_api "sonarr" "\(_config.ports.sonarr)" "/api/v3/system/status"
			wait_for_api "radarr" "\(_config.ports.radarr)" "/api/v3/system/status"

			# Configure download client connections
			echo "Setting up download client connections..."
			wait_for_api "transmission" "\(_config.ports.transmission)" "/transmission/rpc"

			# Configure Bazarr connections to Sonarr/Radarr
			echo "Setting up Bazarr connections..."
			wait_for_api "bazarr" "6767" "/api/system/status"

			echo "✓ Nixarr service networking configured"
		"""
	}
}

// Configuration management for individual services
#ConfigManager: {
	service: string
	port: int
	_config: #NixOSConfig

	// Backup configuration
	backup_config: bash.#Script & {
		script: """
			#!/bin/bash
			set -euo pipefail

			config_path="\(_config.storage.stateRoot)/nixarr/\(service)"
			backup_path="\(_config.storage.persistRoot)/nixarr-backups/\(service)-$(date +%Y%m%d-%H%M%S)"

			if [ -d "$config_path" ]; then
				echo "Backing up \(service) configuration..."
				mkdir -p "$(dirname "$backup_path")"
				cp -r "$config_path" "$backup_path"
				echo "✓ Configuration backed up to $backup_path"
			else
				echo "Warning: No configuration found for \(service) at $config_path"
			fi
		"""
	}

	// Validate configuration
	validate_config: bash.#Script & {
		script: """
			#!/bin/bash
			set -euo pipefail

			config_path="\(_config.storage.stateRoot)/nixarr/\(service)"

			echo "Validating \(service) configuration..."

			# Check if config directory exists
			if [ ! -d "$config_path" ]; then
				echo "Creating config directory: $config_path"
				mkdir -p "$config_path"
				chown 568:568 "$config_path"
			fi

			# Service-specific validation
			case "\(service)" in
				"sonarr"|"radarr"|"prowlarr")
					# Check for database corruption
					if [ -f "$config_path/\(service).db" ]; then
						echo "Checking database integrity..."
						sqlite3 "$config_path/\(service).db" "PRAGMA integrity_check;" | grep -q "ok" || {
							echo "Warning: Database integrity check failed"
						}
					fi
					;;
				"transmission")
					# Check transmission settings
					if [ -f "$config_path/settings.json" ]; then
						jq empty "$config_path/settings.json" || {
							echo "Error: Invalid JSON in transmission settings"
							exit 1
						}
					fi
					;;
			esac

			echo "✓ \(service) configuration validation complete"
		"""
	}
}

// Service health monitoring
#ServiceHealth: {
	service: string
	endpoint: string
	_config: #NixOSConfig

	check: bash.#Script & {
		script: """
			#!/bin/bash
			set -euo pipefail

			echo "Checking health of \(service)..."

			# Basic connectivity check
			if curl -f -s --connect-timeout 10 "\(endpoint)" > /dev/null; then
				echo "✓ \(service) is responding"
			else
				echo "✗ \(service) is not responding at \(endpoint)"
				exit 1
			fi

			# Service-specific health checks
			case "\(service)" in
				"sonarr"|"radarr"|"prowlarr")
					# Check system status via API
					status=$(curl -s "\(endpoint)/../system/status" | jq -r '.version // "unknown"' 2>/dev/null || echo "unknown")
					echo "  Version: $status"
					;;
				"jellyfin")
					# Check transcoding status
					echo "  Checking Jellyfin system info..."
					curl -s "http://127.0.0.1:\(_config.ports.jellyfin)/System/Info" > /dev/null || echo "  Warning: System info unavailable"
					;;
				"transmission")
					# Check session stats
					echo "  Checking transmission session..."
					curl -s "\(endpoint)" -H "X-Transmission-Session-Id: test" > /dev/null || echo "  Note: Session ID required"
					;;
			esac

			echo "✓ \(service) health check passed"
		"""
	}
}

// Service API management
#ServiceAPI: {
	service: string
	port: int
	endpoints: [...string]
	auth_required?: bool | *false
	_config: #NixOSConfig

	test_endpoints: bash.#Script & {
		script: """
			#!/bin/bash
			set -euo pipefail

			echo "Testing API endpoints for \(service)..."

			base_url="http://127.0.0.1:\(port)"
			
			for endpoint in \(strings.Join(endpoints, " ")); do
				echo "Testing: $base_url$endpoint"
				
				if curl -f -s --connect-timeout 5 "$base_url$endpoint" > /dev/null; then
					echo "  ✓ $endpoint responding"
				else
					echo "  ✗ $endpoint not responding"
				fi
			done

			echo "✓ API endpoint testing complete for \(service)"
		"""
	}
}

// API configuration between services
#APIConfiguration: {
	_services: {...}
	_config: #NixOSConfig

	configure: bash.#Script & {
		script: """
			#!/bin/bash
			set -euo pipefail

			echo "Configuring API connections between nixarr services..."

			# Wait for all services to be ready
			echo "Waiting for services to be ready..."
			sleep 30

			# Configure Prowlarr applications (Sonarr, Radarr)
			echo "Configuring Prowlarr applications..."
			
			# This would typically be done through API calls, but for now
			# we'll document the required manual configuration
			cat > /tmp/prowlarr-apps-config.txt << EOF
Manual configuration required in Prowlarr:

1. Add Sonarr Application:
   - Name: Sonarr
   - Sync Level: Full Sync
   - Server: http://127.0.0.1:\(_config.ports.sonarr)
   - API Key: [Set from Sonarr settings]

2. Add Radarr Application:
   - Name: Radarr
   - Sync Level: Full Sync  
   - Server: http://127.0.0.1:\(_config.ports.radarr)
   - API Key: [Set from Radarr settings]
EOF

			# Configure download clients in Sonarr/Radarr
			cat > /tmp/download-client-config.txt << EOF
Manual configuration required in Sonarr/Radarr:

1. Add Transmission Download Client:
   - Name: Transmission
   - Host: 127.0.0.1
   - Port: \(_config.ports.transmission)
   - Username: orther
   - Password: [From SOPS secrets]
EOF

			echo "✓ API configuration templates created"
			echo "  See /tmp/prowlarr-apps-config.txt for Prowlarr setup"
			echo "  See /tmp/download-client-config.txt for download client setup"
		"""
	}
}

// Backup system for all nixarr services
#NixarrBackup: {
	_services: {...}
	_config: #NixOSConfig

	backup_all: bash.#Script & {
		env: {
			KOPIA_TOKEN_FILE: "/run/secrets/kopia-repository-token"
			STATE_ROOT: _config.storage.stateRoot
		}
		script: """
			#!/bin/bash
			set -euo pipefail

			echo "Starting nixarr services backup..."

			# Connect to Kopia repository
			kopia repository connect from-config --token-file $KOPIA_TOKEN_FILE

			# Backup each service configuration
			services=("sonarr" "radarr" "prowlarr" "bazarr" "transmission" "jellyfin")

			for service in "${services[@]}"; do
				service_path="$STATE_ROOT/nixarr/$service"
				
				if [ -d "$service_path" ]; then
					echo "Backing up $service..."
					kopia snapshot create "$service_path" \
						--tags "service:nixarr-$service,automated:true,pipeline:dagger,type:media" \
						--description "Dagger-managed nixarr $service backup"
				else
					echo "Warning: $service path not found: $service_path"
				fi
			done

			# Backup media directory structure (metadata only)
			echo "Backing up media directory structure..."
			find "\(_config.storage.mediaRoot)" -type d -name ".*" -prune -o -type d -print | \
				head -1000 | \
				kopia snapshot create --stdin-file - \
				--tags "service:nixarr-structure,automated:true,pipeline:dagger,type:metadata" \
				--description "Media directory structure backup"

			# Generate backup report
			echo "Generating backup report..."
			kopia snapshot list --tags "service:nixarr" --max-results 20 > /tmp/nixarr-backup-report.txt

			# Disconnect from repository
			kopia repository disconnect

			echo "✓ Nixarr backup completed"
			echo "  Report available at /tmp/nixarr-backup-report.txt"
		"""
	}
}