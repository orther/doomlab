// Media Services Pipeline
// Enhanced workflows for media processing, monitoring, and backup orchestration
// Complements existing nixarr systemd services with container-based enhancements
package main

import (
	"dagger.io/dagger"
	"universe.dagger.io/docker"
	"universe.dagger.io/bash"
	"universe.dagger.io/alpine"
)

// Advanced transcoding pipeline for media processing
#TranscodingPipeline: {
	config: #NixOSConfig
	
	// Hardware-accelerated transcoding container
	transcoder: docker.#Container & {
		image: docker.#Image & {
			from: docker.#Pull & {
				source: "linuxserver/ffmpeg:latest"
			}
		}
		
		// GPU access for hardware acceleration (if available)
		devices: ["/dev/dri:/dev/dri"]
		
		// Volume mounts for media processing
		mounts: {
			media: {
				dest: "/media"
				contents: dagger.#HostDirectory & {
					path: config.storage.mediaRoot
				}
			}
			temp: {
				dest: "/tmp/transcode"
				contents: dagger.#TempDirectory
			}
		}
		
		// Environment for processing pipeline
		env: {
			TRANSCODE_TEMP: "/tmp/transcode"
			MEDIA_ROOT: "/media"
			NVIDIA_VISIBLE_DEVICES: "all" // For NVIDIA GPU support
		}
	}
	
	// Batch processing workflow
	batch_process: #BatchTranscode & {
		_config: config
	}
	
	// Queue management for transcoding jobs
	queue: #TranscodeQueue & {
		_config: config
	}
}

// Media monitoring and analytics system
#MediaMonitoring: {
	config: #NixOSConfig
	
	// Prometheus metrics exporter for media services
	metrics: docker.#Container & {
		image: docker.#Image & {
			from: docker.#Pull & {
				source: "prom/node-exporter:latest"
			}
		}
		
		// System metrics collection
		args: [
			"--path.procfs=/host/proc",
			"--path.sysfs=/host/sys",
			"--path.rootfs=/host",
			"--collector.filesystem.mount-points-exclude=^/(sys|proc|dev|host|etc)($$|/)"
		]
		
		// Host system access for metrics
		mounts: {
			proc: {
				dest: "/host/proc"
				contents: dagger.#HostDirectory & {
					path: "/proc"
				}
				readonly: true
			}
			sys: {
				dest: "/host/sys"  
				contents: dagger.#HostDirectory & {
					path: "/sys"
				}
				readonly: true
			}
			root: {
				dest: "/host"
				contents: dagger.#HostDirectory & {
					path: "/"
				}
				readonly: true
			}
		}
		
		ports: ["9100:9100"]
	}
	
	// Custom media service health monitoring
	health_monitor: #MediaHealthMonitor & {
		_config: config
	}
	
	// Storage utilization tracking
	storage_monitor: #StorageMonitor & {
		_config: config
	}
}

// Orchestrated backup system for media services
#BackupOrchestration: {
	config: #NixOSConfig
	
	// Coordinated backup pipeline
	orchestrator: bash.#Script & {
		env: {
			KOPIA_TOKEN_FILE: "/run/secrets/kopia-repository-token"
			MEDIA_ROOT: config.storage.mediaRoot
			STATE_ROOT: config.storage.stateRoot
		}
		script: """
			#!/bin/bash
			set -euo pipefail
			
			echo "Starting media services backup orchestration..."
			
			# Connect to Kopia repository
			kopia repository connect from-config --token-file $KOPIA_TOKEN_FILE
			
			# Function to create backup with retry logic
			backup_with_retry() {
				local path=$1
				local service=$2
				local max_retries=3
				local retry_count=0
				
				while [ $retry_count -lt $max_retries ]; do
					if kopia snapshot create "$path" \
						--tags "service:$service,automated:true,pipeline:dagger,type:media"; then
						echo "Successfully backed up $path"
						return 0
					fi
					
					retry_count=$((retry_count + 1))
					echo "Backup attempt $retry_count failed for $path, retrying..."
					sleep 30
				done
				
				echo "Failed to backup $path after $max_retries attempts"
				return 1
			}
			
			# Backup media library (selective based on recent changes)
			echo "Backing up media library..."
			backup_with_retry "$MEDIA_ROOT" "media-library"
			
			# Backup nixarr state directories
			for service in jellyfin prowlarr radarr sonarr transmission; do
				service_path="$STATE_ROOT/nixarr/$service"
				if [ -d "$service_path" ]; then
					echo "Backing up $service state..."
					backup_with_retry "$service_path" "nixarr-$service"
				fi
			done
			
			# Generate backup report
			echo "Generating backup report..."
			kopia snapshot list --tags "type:media" --max-results 10 > /tmp/media_backup_report.txt
			
			# Disconnect from repository
			kopia repository disconnect
			
			echo "Media services backup orchestration completed"
		"""
	}
	
	// Backup verification and integrity checking
	verification: #BackupVerification & {
		_config: config
	}
	
	// Cleanup and retention management
	retention: #BackupRetention & {
		_config: config
	}
}

// Batch transcoding workflow
#BatchTranscode: {
	_config: #NixOSConfig
	
	process: bash.#Script & {
		script: """
			#!/bin/bash
			set -euo pipefail
			
			echo "Starting batch transcode processing..."
			
			# Find media files that need transcoding
			find /media -type f \( -name "*.mkv" -o -name "*.avi" -o -name "*.mov" \) \
				-not -path "*/transcoded/*" | while read -r file; do
				
				echo "Processing: $file"
				
				# Create output directory
				output_dir="/media/transcoded/$(dirname "$file" | sed 's|/media/||')"
				mkdir -p "$output_dir"
				
				# Transcode with hardware acceleration if available
				output_file="$output_dir/$(basename "$file" .mkv).mp4"
				
				if command -v nvidia-smi &> /dev/null; then
					# NVIDIA GPU transcoding
					ffmpeg -hwaccel nvdec -i "$file" \
						-c:v h264_nvenc -preset fast -crf 23 \
						-c:a aac -b:a 128k \
						"$output_file"
				elif [ -d /dev/dri ]; then
					# Intel/AMD GPU transcoding  
					ffmpeg -hwaccel vaapi -vaapi_device /dev/dri/renderD128 -i "$file" \
						-c:v h264_vaapi -preset fast -crf 23 \
						-c:a aac -b:a 128k \
						"$output_file"
				else
					# CPU transcoding fallback
					ffmpeg -i "$file" \
						-c:v libx264 -preset fast -crf 23 \
						-c:a aac -b:a 128k \
						"$output_file"
				fi
				
				echo "Completed: $output_file"
			done
			
			echo "Batch transcoding completed"
		"""
	}
}

// Media service health monitoring
#MediaHealthMonitor: {
	_config: #NixOSConfig
	
	monitor: bash.#Script & {
		script: """
			#!/bin/bash
			set -euo pipefail
			
			echo "Monitoring media service health..."
			
			# Function to check service health
			check_service() {
				local service=$1
				local port=$2
				local path=${3:-"/"}
				
				echo "Checking $service (port $port)..."
				
				if curl -f -s --connect-timeout 5 "http://127.0.0.1:$port$path" > /dev/null; then
					echo "✓ $service is healthy"
					return 0
				else
					echo "✗ $service is unhealthy"
					return 1
				fi
			}
			
			# Check all media services
			services_ok=0
			total_services=0
			
			# Jellyfin
			total_services=$((total_services + 1))
			check_service "jellyfin" "\(_config.ports.jellyfin)" "/health" && services_ok=$((services_ok + 1))
			
			# Prowlarr
			total_services=$((total_services + 1))
			check_service "prowlarr" "\(_config.ports.prowlarr)" "/ping" && services_ok=$((services_ok + 1))
			
			# Radarr
			total_services=$((total_services + 1))
			check_service "radarr" "\(_config.ports.radarr)" "/ping" && services_ok=$((services_ok + 1))
			
			# Sonarr
			total_services=$((total_services + 1))
			check_service "sonarr" "\(_config.ports.sonarr)" "/ping" && services_ok=$((services_ok + 1))
			
			# Transmission
			total_services=$((total_services + 1))
			check_service "transmission" "\(_config.ports.transmission)" "/transmission/rpc" && services_ok=$((services_ok + 1))
			
			echo "Health check summary: $services_ok/$total_services services healthy"
			
			# Alert if any services are down
			if [ $services_ok -lt $total_services ]; then
				echo "WARNING: Some media services are unhealthy"
				exit 1
			fi
			
			echo "All media services are healthy"
		"""
	}
}

// Storage utilization monitoring
#StorageMonitor: {
	_config: #NixOSConfig
	
	monitor: bash.#Script & {
		script: """
			#!/bin/bash
			set -euo pipefail
			
			echo "Monitoring storage utilization..."
			
			# Check media storage usage
			media_usage=$(df -h "\(_config.storage.mediaRoot)" | awk 'NR==2 {print $5}' | sed 's/%//')
			echo "Media storage usage: $media_usage%"
			
			# Check state storage usage
			state_usage=$(df -h "\(_config.storage.stateRoot)" | awk 'NR==2 {print $5}' | sed 's/%//')
			echo "State storage usage: $state_usage%"
			
			# Check persistence storage usage
			persist_usage=$(df -h "\(_config.storage.persistRoot)" | awk 'NR==2 {print $5}' | sed 's/%//')
			echo "Persistence storage usage: $persist_usage%"
			
			# Alert thresholds
			if [ "$media_usage" -gt 90 ]; then
				echo "CRITICAL: Media storage usage above 90%"
				exit 2
			elif [ "$media_usage" -gt 80 ]; then
				echo "WARNING: Media storage usage above 80%"
			fi
			
			if [ "$state_usage" -gt 85 ]; then
				echo "WARNING: State storage usage above 85%"
			fi
			
			echo "Storage monitoring completed"
		"""
	}
}

// Backup verification system
#BackupVerification: {
	_config: #NixOSConfig
	
	verify: bash.#Script & {
		env: {
			KOPIA_TOKEN_FILE: "/run/secrets/kopia-repository-token"
		}
		script: """
			#!/bin/bash
			set -euo pipefail
			
			echo "Verifying media service backups..."
			
			# Connect to repository
			kopia repository connect from-config --token-file $KOPIA_TOKEN_FILE
			
			# Verify recent backups exist
			services=("media-library" "nixarr-jellyfin" "nixarr-prowlarr" "nixarr-radarr" "nixarr-sonarr" "nixarr-transmission")
			
			for service in "${services[@]}"; do
				echo "Verifying backups for $service..."
				
				# Check if backup exists from last 48 hours
				recent_backup=$(kopia snapshot list --tags "service:$service" \
					--max-results 1 --json | jq -r '.[0].startTime // empty')
				
				if [ -n "$recent_backup" ]; then
					backup_age=$(( $(date +%s) - $(date -d "$recent_backup" +%s) ))
					hours_old=$(( backup_age / 3600 ))
					
					if [ $hours_old -lt 48 ]; then
						echo "✓ $service: Recent backup found ($hours_old hours old)"
					else
						echo "✗ $service: Backup is too old ($hours_old hours)"
					fi
				else
					echo "✗ $service: No recent backups found"
				fi
			done
			
			# Verify backup integrity
			echo "Running backup integrity verification..."
			kopia maintenance run --full
			
			kopia repository disconnect
			echo "Backup verification completed"
		"""
	}
}