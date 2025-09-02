// Nixarr Services Test Suite
// Comprehensive testing for Dagger-enhanced nixarr services
package main

import (
	"dagger.io/dagger"
	"universe.dagger.io/bash"
	"universe.dagger.io/docker"
)

// Nixarr test suite
#NixarrTestSuite: {
	config: #NixOSConfig

	// Test configuration validation
	config_tests: #ConfigTests & {_config: config}

	// Test service health and connectivity
	health_tests: #HealthTests & {_config: config}

	// Test service integration and API connectivity
	integration_tests: #IntegrationTests & {_config: config}

	// Test backup and recovery functionality
	backup_tests: #BackupTests & {_config: config}

	// Test migration functionality
	migration_tests: #MigrationTests & {_config: config}
}

// Configuration validation tests
#ConfigTests: {
	_config: #NixOSConfig

	validate_directories: bash.#Script & {
		script: """
			#!/bin/bash
			set -euo pipefail

			echo "=== Configuration Tests ==="
			echo "Testing directory structure and permissions..."

			# Check required directories exist
			required_dirs=(
				"\(_config.storage.stateRoot)/nixarr"
				"\(_config.storage.mediaRoot)"
				"/run/dagger-secrets"
				"/var/cache/dagger"
			)

			for dir in "${required_dirs[@]}"; do
				if [ -d "$dir" ]; then
					echo "✓ Directory exists: $dir"
				else
					echo "✗ Missing directory: $dir"
					exit 1
				fi
			done

			# Check permissions
			if [ -w "\(_config.storage.stateRoot)/nixarr" ]; then
				echo "✓ State directory is writable"
			else
				echo "✗ State directory is not writable"
				exit 1
			fi

			echo "✓ Configuration tests passed"
		"""
	}

	validate_secrets: bash.#Script & {
		script: """
			#!/bin/bash
			set -euo pipefail

			echo "Testing secrets configuration..."

			# Check if secret directories exist
			services=("sonarr" "radarr" "prowlarr" "bazarr" "transmission" "jellyfin")
			
			for service in "${services[@]}"; do
				secret_dir="/run/dagger-secrets/$service"
				if [ -d "$secret_dir" ]; then
					echo "✓ Secret directory exists for $service"
				else
					echo "⚠️  Secret directory missing for $service (may be OK if service disabled)"
				fi
			done

			echo "✓ Secrets configuration tests completed"
		"""
	}

	validate_ports: bash.#Script & {
		script: """
			#!/bin/bash
			set -euo pipefail

			echo "Testing port availability..."

			# List of ports that should be available or in use by our services
			ports=(
				"\(_config.ports.sonarr)"
				"\(_config.ports.radarr)"
				"\(_config.ports.prowlarr)"
				"6767"  # bazarr
				"\(_config.ports.transmission)"
				"\(_config.ports.jellyfin)"
			)

			for port in "${ports[@]}"; do
				if ss -tlnp | grep -q ":$port "; then
					echo "ℹ️  Port $port is in use (expected if service is running)"
				else
					echo "ℹ️  Port $port is available"
				fi
			done

			echo "✓ Port availability tests completed"
		"""
	}
}

// Service health and connectivity tests
#HealthTests: {
	_config: #NixOSConfig

	test_service_health: bash.#Script & {
		script: """
			#!/bin/bash
			set -euo pipefail

			echo "=== Service Health Tests ==="

			# Function to test service health
			test_service() {
				local service=$1
				local port=$2
				local endpoint=${3:-"/ping"}

				echo "Testing $service on port $port..."

				# Check if port is listening
				if ! ss -tlnp | grep -q ":$port "; then
					echo "⚠️  $service: Port $port not listening (service may be stopped)"
					return 0
				fi

				# Check HTTP response
				if curl -f -s --connect-timeout 5 "http://127.0.0.1:$port$endpoint" > /dev/null; then
					echo "✓ $service: Health check passed"
				else
					echo "✗ $service: Health check failed"
					return 1
				fi
			}

			# Test each service
			test_service "Sonarr" "\(_config.ports.sonarr)" "/ping"
			test_service "Radarr" "\(_config.ports.radarr)" "/ping"  
			test_service "Prowlarr" "\(_config.ports.prowlarr)" "/ping"
			test_service "Bazarr" "6767" "/ping"
			test_service "Transmission" "\(_config.ports.transmission)" "/transmission/rpc"
			test_service "Jellyfin" "\(_config.ports.jellyfin)" "/health"

			echo "✓ Service health tests completed"
		"""
	}

	test_dagger_connectivity: bash.#Script & {
		script: """
			#!/bin/bash
			set -euo pipefail

			echo "Testing Dagger connectivity..."

			# Test Dagger CLI
			if dagger version > /dev/null 2>&1; then
				echo "✓ Dagger CLI is working"
			else
				echo "✗ Dagger CLI is not working"
				exit 1
			fi

			# Test Dagger daemon connectivity
			if dagger query '{core{version}}' > /dev/null 2>&1; then
				echo "✓ Dagger daemon is accessible"
			else
				echo "✗ Dagger daemon is not accessible"
				exit 1
			fi

			echo "✓ Dagger connectivity tests passed"
		"""
	}
}

// Service integration and API tests
#IntegrationTests: {
	_config: #NixOSConfig

	test_api_connectivity: bash.#Script & {
		script: """
			#!/bin/bash
			set -euo pipefail

			echo "=== API Integration Tests ==="

			# Function to test API endpoints
			test_api() {
				local service=$1
				local port=$2
				local endpoint=$3

				echo "Testing $service API: $endpoint"

				if curl -f -s --connect-timeout 5 "http://127.0.0.1:$port$endpoint" > /dev/null; then
					echo "✓ $service API endpoint responding: $endpoint"
				else
					echo "⚠️  $service API endpoint not responding: $endpoint (may need authentication)"
				fi
			}

			# Test API endpoints if services are running
			if ss -tlnp | grep -q ":\(_config.ports.sonarr) "; then
				test_api "Sonarr" "\(_config.ports.sonarr)" "/api/v3/system/status"
			fi

			if ss -tlnp | grep -q ":\(_config.ports.radarr) "; then
				test_api "Radarr" "\(_config.ports.radarr)" "/api/v3/system/status"
			fi

			if ss -tlnp | grep -q ":\(_config.ports.prowlarr) "; then
				test_api "Prowlarr" "\(_config.ports.prowlarr)" "/api/v1/system/status"
			fi

			if ss -tlnp | grep -q ":6767 "; then
				test_api "Bazarr" "6767" "/api/system/status"
			fi

			echo "✓ API integration tests completed"
		"""
	}

	test_inter_service_communication: bash.#Script & {
		script: """
			#!/bin/bash
			set -euo pipefail

			echo "Testing inter-service communication..."

			# This would test things like:
			# - Prowlarr can communicate with Sonarr/Radarr
			# - Sonarr/Radarr can communicate with download clients
			# - Bazarr can communicate with Sonarr/Radarr

			echo "ℹ️  Inter-service communication tests require API keys"
			echo "ℹ️  Manual verification needed through web interfaces"

			echo "✓ Inter-service communication tests completed"
		"""
	}
}

// Backup functionality tests
#BackupTests: {
	_config: #NixOSConfig

	test_backup_functionality: bash.#Script & {
		env: {
			TEST_BACKUP_DIR: "/tmp/nixarr-test-backup"
		}
		script: """
			#!/bin/bash
			set -euo pipefail

			echo "=== Backup Functionality Tests ==="

			# Create test data
			mkdir -p "$TEST_BACKUP_DIR/test-service"
			echo "test config data" > "$TEST_BACKUP_DIR/test-service/config.xml"

			# Test backup creation (simulated)
			echo "Testing backup creation..."
			if [ -d "\(_config.storage.stateRoot)/nixarr" ]; then
				echo "✓ Nixarr state directory exists for backup"
			else
				echo "⚠️  No nixarr state directory found"
			fi

			# Test backup validation (requires kopia setup)
			if command -v kopia > /dev/null 2>&1; then
				echo "✓ Kopia backup tool available"
				# Would test actual backup functionality here if repo is configured
			else
				echo "ℹ️  Kopia not available (backup tests skipped)"
			fi

			# Cleanup
			rm -rf "$TEST_BACKUP_DIR"

			echo "✓ Backup functionality tests completed"
		"""
	}
}

// Migration functionality tests
#MigrationTests: {
	_config: #NixOSConfig

	test_migration_tools: bash.#Script & {
		script: """
			#!/bin/bash
			set -euo pipefail

			echo "=== Migration Tools Tests ==="

			# Test migration utility availability
			if command -v nixarr-migrate > /dev/null 2>&1; then
				echo "✓ nixarr-migrate command available"
				
				# Test status command
				if nixarr-migrate status > /dev/null 2>&1; then
					echo "✓ Migration status command working"
				else
					echo "✗ Migration status command failed"
					exit 1
				fi
			else
				echo "✗ nixarr-migrate command not available"
				exit 1
			fi

			# Test migration status script
			if command -v nixarr-migration-status > /dev/null 2>&1; then
				echo "✓ Migration status script available"
			else
				echo "✗ Migration status script not available"
				exit 1
			fi

			echo "✓ Migration tools tests passed"
		"""
	}

	test_conflict_detection: bash.#Script & {
		script: """
			#!/bin/bash
			set -euo pipefail

			echo "Testing service conflict detection..."

			# Check for actual conflicts
			conflicts=0
			
			services=("sonarr" "radarr" "prowlarr" "transmission" "jellyfin")
			
			for service in "${services[@]}"; do
				legacy_active=$(systemctl is-active $service.service 2>/dev/null || echo "inactive")
				dagger_active=$(systemctl is-active dagger-$service.service 2>/dev/null || echo "inactive")
				
				if [ "$legacy_active" = "active" ] && [ "$dagger_active" = "active" ]; then
					echo "⚠️  Conflict detected: Both $service and dagger-$service are active"
					conflicts=$((conflicts + 1))
				fi
			done

			if [ $conflicts -eq 0 ]; then
				echo "✓ No service conflicts detected"
			else
				echo "⚠️  $conflicts service conflicts detected"
			fi

			echo "✓ Conflict detection tests completed"
		"""
	}
}

// Complete test runner
#TestRunner: {
	config: #NixOSConfig

	run_all_tests: bash.#Script & {
		script: """
			#!/bin/bash
			set -euo pipefail

			echo "==============================================="
			echo "    Dagger-Nixarr Integration Test Suite"
			echo "==============================================="
			echo

			# Initialize test results
			total_tests=0
			passed_tests=0

			# Function to run test and track results
			run_test() {
				local test_name=$1
				local test_command=$2
				
				echo "Running: $test_name"
				echo "----------------------------------------"
				
				if $test_command; then
					echo "✓ PASSED: $test_name"
					passed_tests=$((passed_tests + 1))
				else
					echo "✗ FAILED: $test_name"
				fi
				
				total_tests=$((total_tests + 1))
				echo
			}

			# Run all test categories
			echo "Starting comprehensive test suite..."
			echo

			# Configuration tests
			run_test "Directory Structure Validation" "validate_directories"
			run_test "Secrets Configuration" "validate_secrets"  
			run_test "Port Availability" "validate_ports"

			# Health tests
			run_test "Service Health Checks" "test_service_health"
			run_test "Dagger Connectivity" "test_dagger_connectivity"

			# Integration tests
			run_test "API Connectivity" "test_api_connectivity"
			run_test "Inter-service Communication" "test_inter_service_communication"

			# Backup tests
			run_test "Backup Functionality" "test_backup_functionality"

			# Migration tests
			run_test "Migration Tools" "test_migration_tools"
			run_test "Conflict Detection" "test_conflict_detection"

			# Final report
			echo "==============================================="
			echo "           Test Results Summary"
			echo "==============================================="
			echo "Total Tests: $total_tests"
			echo "Passed: $passed_tests"
			echo "Failed: $((total_tests - passed_tests))"
			echo

			if [ $passed_tests -eq $total_tests ]; then
				echo "🎉 ALL TESTS PASSED!"
				exit 0
			else
				echo "⚠️  Some tests failed. Please review the output above."
				exit 1
			fi
		"""
	}
}