// Storage Infrastructure for Dagger Services
// Provides persistent storage that integrates with NixOS impermanence and existing storage patterns
// Maintains compatibility with current backup and persistence strategies
package main

import (
	"dagger.io/dagger"
	"universe.dagger.io/bash"
)

// Storage management system for Dagger services
#StorageManager: {
	config: #NixOSConfig
	
	// NFS validation and health monitoring
	nfs: #NFSManager & {
		_config: config
	}
	
	// Storage volumes aligned with NixOS persistence patterns
	volumes: {
		// Persistent application data
		persistent: #Volume & {
			name: "dagger-persistent"
			path: "\(config.storage.persistRoot)/var/lib/dagger"
			mode: "0755"
			owner: "root:root"
			backup: true
			_config: config
		}
		
		// Media storage (large files, selective backup)
		media: #Volume & {
			name: "dagger-media"  
			path: config.storage.mediaRoot
			mode: "0755"
			owner: "root:root"
			backup: false // Handled by specialized media backup
			_config: config
		}
		
		// Temporary/cache storage
		cache: #Volume & {
			name: "dagger-cache"
			path: "/var/cache/dagger"
			mode: "0755"
			owner: "root:root"
			backup: false
			_config: config
		}
		
		// Runtime data (secrets, sockets)
		runtime: #Volume & {
			name: "dagger-runtime"
			path: "/run/dagger"
			mode: "0700"
			owner: "root:root" 
			backup: false
			_config: config
		}
	}
	
	// Volume management operations
	management: #VolumeManagement & {
		_volumes: volumes
		_config: config
		_nfs: nfs
	}
	
	// Backup coordination
	backup: #BackupManagement & {
		_volumes: volumes
		_config: config
	}
	
	// Storage monitoring
	monitoring: #StorageMonitoring & {
		_volumes: volumes
		_config: config
	}
}

// Individual volume definition  
#Volume: {
	name: string
	path: string
	mode: string
	owner: string
	backup: bool
	_config: #NixOSConfig
	
	// Mount options
	mount_options?: [...string]
	
	// Size limits (optional)
	size_limit?: string
	
	// Create the volume directory
	create: bash.#Script & {
		script: """
			#!/bin/bash
			set -euo pipefail
			
			echo "Creating volume: \(name) at \(path)"
			
			# Create directory if it doesn't exist
			mkdir -p "\(path)"
			
			# Set ownership and permissions
			chown \(owner) "\(path)"
			chmod \(mode) "\(path)"
			
			# Apply SELinux context if available
			if command -v restorecon &> /dev/null; then
				restorecon -R "\(path)"
			fi
			
			echo "Volume \(name) created successfully"
		"""
	}
	
	// Verify volume integrity
	verify: bash.#Script & {
		script: """
			#!/bin/bash
			set -euo pipefail
			
			echo "Verifying volume: \(name)"
			
			# Check if directory exists
			if [ ! -d "\(path)" ]; then
				echo "✗ Volume directory \(path) does not exist"
				exit 1
			fi
			
			# Check ownership
			actual_owner=$(stat -c "%U:%G" "\(path)")
			expected_owner="\(owner)"
			if [ "$actual_owner" != "$expected_owner" ]; then
				echo "⚠ Volume ownership mismatch: expected $expected_owner, got $actual_owner"
			fi
			
			# Check permissions
			actual_mode=$(stat -c "%a" "\(path)")
			expected_mode="\(mode)"
			if [ "$actual_mode" != "$expected_mode" ]; then
				echo "⚠ Volume permissions mismatch: expected $expected_mode, got $actual_mode"
			fi
			
			# Check disk space
			df -h "\(path)"
			
			echo "✓ Volume \(name) verification completed"
		"""
	}
	
	// Clean up volume (with safety checks)
	cleanup: bash.#Script & {
		script: """
			#!/bin/bash
			set -euo pipefail
			
			echo "Cleaning up volume: \(name)"
			
			# Safety checks
			if [ "\(path)" = "/" ] || [ "\(path)" = "/nix" ] || [ "\(path)" = "/nix/store" ]; then
				echo "Error: Cannot clean critical system path \(path)"
				exit 1
			fi
			
			# Clean temporary files in cache volumes
			if [[ "\(name)" == *"cache"* ]]; then
				echo "Cleaning cache files in \(path)..."
				find "\(path)" -type f -mtime +7 -delete 2>/dev/null || true
				find "\(path)" -type d -empty -delete 2>/dev/null || true
			fi
			
			# Clean old log files
			find "\(path)" -name "*.log" -mtime +30 -delete 2>/dev/null || true
			find "\(path)" -name "*.log.*" -mtime +7 -delete 2>/dev/null || true
			
			echo "Volume cleanup completed for \(name)"
		"""
	}
}

// Volume management operations
#VolumeManagement: {
	_volumes: {...}
	_config: #NixOSConfig
	_nfs: #NFSManager
	
	// Initialize all volumes
	initialize: bash.#Script & {
		script: """
			#!/bin/bash
			set -euo pipefail
			
			echo "Initializing Dagger storage volumes..."
			
			# First validate NFS if configured
			echo "Validating NFS storage..."
			\(_nfs.validate_paths.script)
			
			# Create base directories
			mkdir -p "\(_config.storage.persistRoot)/var/lib/dagger"
			mkdir -p "/var/cache/dagger"  
			mkdir -p "/run/dagger"
			
			# Set proper ownership and permissions for persistent storage
			chown root:root "\(_config.storage.persistRoot)/var/lib/dagger"
			chmod 755 "\(_config.storage.persistRoot)/var/lib/dagger"
			
			# Set proper ownership and permissions for cache
			chown root:root "/var/cache/dagger"
			chmod 755 "/var/cache/dagger"
			
			# Set proper ownership and permissions for runtime
			chown root:root "/run/dagger"
			chmod 700 "/run/dagger"
			
			# Ensure media directory is accessible (should already exist from nixarr)
			if [ -d "\(_config.storage.mediaRoot)" ]; then
				echo "✓ Media directory \(_config.storage.mediaRoot) is available"
			else
				echo "⚠ Media directory \(_config.storage.mediaRoot) not found - creating"
				mkdir -p "\(_config.storage.mediaRoot)"
				chown root:root "\(_config.storage.mediaRoot)"
				chmod 755 "\(_config.storage.mediaRoot)"
			fi
			
			echo "Storage volume initialization completed"
		"""
	}
	
	// Migrate data between volumes
	migrate: {
		source: string
		destination: string
		
		script: bash.#Script & {
			script: """
				#!/bin/bash
				set -euo pipefail
				
				echo "Migrating data from \(source) to \(destination)..."
				
				# Verify source exists
				if [ ! -d "\(source)" ]; then
					echo "Source directory \(source) does not exist"
					exit 1
				fi
				
				# Create destination if needed
				mkdir -p "\(destination)"
				
				# Copy data with preservation of attributes
				rsync -av --progress "\(source)/" "\(destination)/"
				
				# Verify migration
				source_size=$(du -sb "\(source)" | cut -f1)
				dest_size=$(du -sb "\(destination)" | cut -f1)
				
				if [ "$source_size" -eq "$dest_size" ]; then
					echo "✓ Migration completed successfully"
					echo "  Source size: $source_size bytes"
					echo "  Destination size: $dest_size bytes"
				else
					echo "✗ Migration size mismatch"
					echo "  Source size: $source_size bytes"  
					echo "  Destination size: $dest_size bytes"
					exit 1
				fi
			"""
		}
	}
	
	// Synchronize volumes across hosts
	sync: {
		remote_host: string
		volumes: [...string]
		
		script: bash.#Script & {
			script: """
				#!/bin/bash
				set -euo pipefail
				
				echo "Synchronizing volumes to \(remote_host)..."
				
				volumes=(\(strings.Join([for v in volumes {"\"\(v)\""}], " ")))
				
				for volume in "''${volumes[@]}"; do
					echo "Syncing volume: $volume"
					
					case "$volume" in
						"persistent")
							rsync -av --progress "\(_config.storage.persistRoot)/var/lib/dagger/" \
								"\(remote_host):\(_config.storage.persistRoot)/var/lib/dagger/"
							;;
						"cache")
							echo "Skipping cache volume sync (not necessary)"
							;;
						"media")
							echo "Media volume sync requires special handling (large files)"
							# Media sync would typically be handled by specialized tools
							;;
						*)
							echo "Unknown volume: $volume"
							;;
					esac
				done
				
				echo "Volume synchronization completed"
			"""
		}
	}
}

// Backup management for Dagger storage
#BackupManagement: {
	_volumes: {...}
	_config: #NixOSConfig
	
	// Coordinate backups with existing Kopia system
	coordinate: bash.#Script & {
		script: """
			#!/bin/bash
			set -euo pipefail
			
			echo "Coordinating Dagger storage backups with Kopia..."
			
			# Connect to Kopia repository
			if [ -f "/run/secrets/kopia-repository-token" ]; then
				kopia repository connect from-config --token-file /run/secrets/kopia-repository-token
			else
				echo "Kopia repository token not available - backup coordination limited"
				exit 1
			fi
			
			# Backup persistent Dagger data
			persistent_path="\(_config.storage.persistRoot)/var/lib/dagger"
			if [ -d "$persistent_path" ]; then
				echo "Backing up Dagger persistent data..."
				kopia snapshot create "$persistent_path" \
					--tags "service:dagger,type:persistent,automated:true"
			fi
			
			# Backup service-specific data directories
			service_dirs=(
				"\(_config.storage.stateRoot)/homebridge"
				"\(_config.storage.stateRoot)/scrypted" 
				"\(_config.storage.stateRoot)/nixarr"
			)
			
			for dir in "''${service_dirs[@]}"; do
				if [ -d "$dir" ]; then
					service_name=$(basename "$dir")
					echo "Backing up $service_name data..."
					kopia snapshot create "$dir" \
						--tags "service:$service_name,type:application,automated:true,managed:dagger"
				fi
			done
			
			# Generate backup report
			echo "Recent Dagger-managed backups:"
			kopia snapshot list --tags "managed:dagger" --max-results 10
			
			# Disconnect from repository
			kopia repository disconnect
			
			echo "Backup coordination completed"
		"""
	}
	
	// Restore data from backup
	restore: {
		service: string
		snapshot_id: string
		
		script: bash.#Script & {
			script: """
				#!/bin/bash
				set -euo pipefail
				
				echo "Restoring \(service) from snapshot \(snapshot_id)..."
				
				# Connect to Kopia repository
				kopia repository connect from-config --token-file /run/secrets/kopia-repository-token
				
				# Determine restore path
				restore_path=""
				case "\(service)" in
					"dagger")
						restore_path="\(_config.storage.persistRoot)/var/lib/dagger"
						;;
					"homebridge"|"scrypted")
						restore_path="\(_config.storage.stateRoot)/\(service)"
						;;
					"nixarr")
						restore_path="\(_config.storage.stateRoot)/nixarr"
						;;
					*)
						echo "Unknown service: \(service)"
						exit 1
						;;
				esac
				
				# Stop related services before restore
				echo "Stopping related services..."
				systemctl stop "dagger-*\(service)*" 2>/dev/null || true
				
				# Create backup of current data
				if [ -d "$restore_path" ]; then
					backup_current="$restore_path.backup.$(date +%s)"
					echo "Backing up current data to $backup_current..."
					mv "$restore_path" "$backup_current"
				fi
				
				# Restore from snapshot
				echo "Restoring from snapshot..."
				mkdir -p "$restore_path"
				kopia snapshot restore \(snapshot_id) "$restore_path"
				
				# Set proper ownership
				chown -R root:root "$restore_path"
				
				# Start services
				echo "Starting services..."
				systemctl start "dagger-*\(service)*" 2>/dev/null || true
				
				kopia repository disconnect
				
				echo "Restore completed for \(service)"
			"""
		}
	}
}

// Storage monitoring and alerting
#StorageMonitoring: {
	_volumes: {...}
	_config: #NixOSConfig
	
	// Monitor storage usage and health
	monitor: bash.#Script & {
		script: """
			#!/bin/bash
			set -euo pipefail
			
			echo "Monitoring Dagger storage health..."
			
			# Check disk usage for all volumes
			volumes=(
				"\(_config.storage.persistRoot):persistent"
				"\(_config.storage.mediaRoot):media" 
				"/var/cache/dagger:cache"
				"/run/dagger:runtime"
			)
			
			critical_alerts=()
			warnings=()
			
			for volume_info in "''${volumes[@]}"; do
				IFS=":" read -r path name <<< "$volume_info"
				
				if [ -d "$path" ]; then
					usage=$(df "$path" | awk 'NR==2 {print $5}' | sed 's/%//')
					available=$(df -h "$path" | awk 'NR==2 {print $4}')
					
					echo "Volume $name ($path): $usage% used, $available available"
					
					# Alert thresholds
					if [ "$usage" -gt 95 ]; then
						critical_alerts+=("$name: $usage% used (CRITICAL)")
					elif [ "$usage" -gt 85 ]; then
						warnings+=("$name: $usage% used (WARNING)")
					fi
				else
					echo "Volume $name ($path): NOT FOUND"
					critical_alerts+=("$name: Volume not found")
				fi
			done
			
			# Check for I/O errors
			dmesg | grep -i "i/o error" | tail -5 | while read -r line; do
				echo "I/O Error detected: $line"
			done
			
			# Report alerts
			if [ ''${#critical_alerts[@]} -gt 0 ]; then
				echo ""
				echo "CRITICAL ALERTS:"
				printf '%s\n' "''${critical_alerts[@]}"
				exit 2
			fi
			
			if [ ''${#warnings[@]} -gt 0 ]; then
				echo ""
				echo "WARNINGS:"
				printf '%s\n' "''${warnings[@]}"
				exit 1
			fi
			
			echo "All storage volumes are healthy"
		"""
	}
	
	// Clean up old files and optimize storage
	cleanup: bash.#Script & {
		script: """
			#!/bin/bash
			set -euo pipefail
			
			echo "Performing storage cleanup..."
			
			# Clean cache directories
			echo "Cleaning cache directories..."
			find "/var/cache/dagger" -type f -mtime +7 -delete 2>/dev/null || true
			find "/var/cache/dagger" -type d -empty -delete 2>/dev/null || true
			
			# Clean runtime directories
			echo "Cleaning runtime directories..."
			find "/run/dagger" -type f -mtime +1 -delete 2>/dev/null || true
			
			# Clean old log files
			echo "Cleaning old log files..."
			find "\(_config.storage.persistRoot)/var/lib/dagger" -name "*.log" -mtime +30 -delete 2>/dev/null || true
			find "\(_config.storage.persistRoot)/var/lib/dagger" -name "*.log.*" -mtime +7 -delete 2>/dev/null || true
			
			# Clean container build cache
			echo "Cleaning container build cache..."
			podman system prune -af --volumes 2>/dev/null || true
			
			# Report space freed
			echo "Storage cleanup completed"
			df -h "\(_config.storage.persistRoot)" "/var/cache/dagger" 2>/dev/null || true
		"""
	}
}

// Service-specific storage configurations
#ServiceStorage: {
	service: string
	_config: #NixOSConfig
	
	// Get storage configuration for specific services
	getConfig: {
		// Homebridge storage
		if service == "homebridge" {
			volumes: [
				{
					source: "\(_config.storage.stateRoot)/homebridge"
					target: "/homebridge"
					mode: "rw"
				}
			]
			backup_paths: ["\(_config.storage.stateRoot)/homebridge"]
		}
		
		// Scrypted storage
		if service == "scrypted" {
			volumes: [
				{
					source: "\(_config.storage.stateRoot)/scrypted"
					target: "/server/volume"
					mode: "rw"
				}
			]
			backup_paths: ["\(_config.storage.stateRoot)/scrypted"]
		}
		
		// Media transcoding storage  
		if service == "transcoding" {
			volumes: [
				{
					source: _config.storage.mediaRoot
					target: "/media"
					mode: "rw"
				},
				{
					source: "/var/cache/dagger/transcoding"
					target: "/tmp/transcode"
					mode: "rw"
				}
			]
			backup_paths: [] // Media files backed up separately
		}
	}
}

// NFS mount management and health checking
#NFSManager: {
	_config: #NixOSConfig
	
	// NFS mount validation
	validate: bash.#Script & {
		script: """
			#!/bin/bash
			set -euo pipefail
			
			echo "Validating NFS storage availability..."
			
			NFS_MOUNT="/mnt/docker-data"
			NFS_HOST="10.4.0.50"
			
			# Check if NFS mount directory exists
			if [ ! -d "$NFS_MOUNT" ]; then
				echo "NFS mount directory $NFS_MOUNT does not exist, skipping NFS validation"
				exit 0
			fi
			
			# Check if already mounted
			if mountpoint -q "$NFS_MOUNT"; then
				echo "✓ NFS mount $NFS_MOUNT is active"
				
				# Test connectivity and write access
				if timeout 10 touch "$NFS_MOUNT/.dagger-nfs-test" 2>/dev/null; then
					rm -f "$NFS_MOUNT/.dagger-nfs-test"
					echo "✓ NFS mount is accessible and writable"
				else
					echo "✗ NFS mount is not accessible or writable"
					exit 1
				fi
			else
				echo "✗ NFS mount $NFS_MOUNT is not mounted"
				
				# Attempt to ping NFS server
				if timeout 5 ping -c 1 "$NFS_HOST" >/dev/null 2>&1; then
					echo "✓ NFS server $NFS_HOST is reachable"
				else
					echo "✗ NFS server $NFS_HOST is not reachable"
					exit 1
				fi
				
				# Attempt to mount
				echo "Attempting to mount NFS..."
				if mount "$NFS_MOUNT"; then
					echo "✓ NFS mount successful"
				else
					echo "✗ Failed to mount NFS"
					exit 1
				fi
			fi
			
			echo "NFS validation completed successfully"
		"""
	}
	
	// NFS health monitoring
	monitor: bash.#Script & {
		script: """
			#!/bin/bash
			set -euo pipefail
			
			echo "Monitoring NFS health..."
			
			NFS_MOUNT="/mnt/docker-data"
			NFS_HOST="10.4.0.50"
			
			# Skip if NFS not configured
			if [ ! -d "$NFS_MOUNT" ]; then
				echo "NFS not configured, skipping monitoring"
				exit 0
			fi
			
			alerts=()
			
			# Check mount status
			if ! mountpoint -q "$NFS_MOUNT"; then
				alerts+=("NFS mount $NFS_MOUNT is not mounted")
			fi
			
			# Check server connectivity
			if ! timeout 5 ping -c 1 "$NFS_HOST" >/dev/null 2>&1; then
				alerts+=("NFS server $NFS_HOST is not reachable")
			fi
			
			# Check I/O performance
			if mountpoint -q "$NFS_MOUNT"; then
				start_time=$(date +%s.%N)
				if timeout 10 touch "$NFS_MOUNT/.dagger-perf-test" 2>/dev/null; then
					end_time=$(date +%s.%N)
					duration=$(echo "$end_time - $start_time" | bc)
					rm -f "$NFS_MOUNT/.dagger-perf-test"
					
					# Alert if I/O takes longer than 5 seconds
					if (( $(echo "$duration > 5.0" | bc -l) )); then
						alerts+=("NFS I/O performance degraded: ${duration}s write time")
					else
						echo "NFS I/O performance: ${duration}s"
					fi
				else
					alerts+=("NFS write test failed")
				fi
			fi
			
			# Check disk usage
			if mountpoint -q "$NFS_MOUNT"; then
				usage=$(df "$NFS_MOUNT" | awk 'NR==2 {print $5}' | sed 's/%//')
				echo "NFS usage: $usage%"
				
				if [ "$usage" -gt 90 ]; then
					alerts+=("NFS usage critical: $usage%")
				elif [ "$usage" -gt 80 ]; then
					alerts+=("NFS usage warning: $usage%")
				fi
			fi
			
			# Report alerts
			if [ ${#alerts[@]} -gt 0 ]; then
				echo ""
				echo "NFS ALERTS:"
				printf '%s\n' "${alerts[@]}"
				exit 1
			fi
			
			echo "✓ NFS health check passed"
		"""
	}
	
	// NFS recovery operations
	recover: bash.#Script & {
		script: """
			#!/bin/bash
			set -euo pipefail
			
			echo "Attempting NFS recovery..."
			
			NFS_MOUNT="/mnt/docker-data"
			NFS_HOST="10.4.0.50"
			
			if [ ! -d "$NFS_MOUNT" ]; then
				echo "NFS not configured, skipping recovery"
				exit 0
			fi
			
			# Unmount if stale
			if mountpoint -q "$NFS_MOUNT"; then
				echo "Unmounting potentially stale NFS mount..."
				umount -f "$NFS_MOUNT" || umount -l "$NFS_MOUNT" || true
			fi
			
			# Wait for network
			echo "Waiting for network connectivity..."
			for i in {1..10}; do
				if timeout 5 ping -c 1 "$NFS_HOST" >/dev/null 2>&1; then
					echo "✓ Network connectivity restored"
					break
				fi
				echo "Network connectivity attempt $i/10..."
				sleep 5
			done
			
			# Attempt remount
			echo "Attempting to remount NFS..."
			if mount "$NFS_MOUNT"; then
				echo "✓ NFS remount successful"
				
				# Validate access
				if timeout 10 touch "$NFS_MOUNT/.dagger-recovery-test" 2>/dev/null; then
					rm -f "$NFS_MOUNT/.dagger-recovery-test"
					echo "✓ NFS recovery completed successfully"
				else
					echo "✗ NFS mounted but not accessible"
					exit 1
				fi
			else
				echo "✗ NFS remount failed"
				exit 1
			fi
		"""
	}
	
	// Storage path validation with NFS awareness
	validate_paths: bash.#Script & {
		script: """
			#!/bin/bash
			set -euo pipefail
			
			echo "Validating storage paths with NFS awareness..."
			
			# Check if services need NFS storage
			NFS_MOUNT="/mnt/docker-data"
			MEDIA_ROOT="\(_config.storage.mediaRoot)"
			STATE_ROOT="\(_config.storage.stateRoot)"
			PERSIST_ROOT="\(_config.storage.persistRoot)"
			
			# Validate media storage (usually /fun)
			if [ ! -d "$MEDIA_ROOT" ]; then
				echo "✗ Media root directory $MEDIA_ROOT not found"
				exit 1
			else
				echo "✓ Media root directory $MEDIA_ROOT exists"
			fi
			
			# Validate state storage
			if [ ! -d "$STATE_ROOT" ]; then
				echo "Creating state root directory $STATE_ROOT"
				mkdir -p "$STATE_ROOT"
			fi
			echo "✓ State root directory $STATE_ROOT exists"
			
			# Validate persistence storage
			if [ ! -d "$PERSIST_ROOT" ]; then
				echo "Creating persistence root directory $PERSIST_ROOT"
				mkdir -p "$PERSIST_ROOT"
			fi
			echo "✓ Persistence root directory $PERSIST_ROOT exists"
			
			# Check NFS if configured
			if [ -d "$NFS_MOUNT" ]; then
				echo "Checking NFS storage at $NFS_MOUNT"
				if mountpoint -q "$NFS_MOUNT"; then
					echo "✓ NFS mount is available"
				else
					echo "⚠ NFS mount is not active, some services may have limited functionality"
				fi
			else
				echo "NFS storage not configured"
			fi
			
			echo "Storage path validation completed"
		"""
	}
}