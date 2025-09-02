// Secrets Management for Dagger Pipelines
// Integrates with NixOS SOPS-nix for secure secret injection
package main

import (
	"dagger.io/dagger"
	"universe.dagger.io/bash"
)

// Secret management system that integrates with SOPS-nix
#SecretsManager: {
	config: #NixOSConfig
	
	// Runtime secrets directory (injected by NixOS)
	secretsDir: string | *"/run/dagger-secrets"
	
	// Secret definitions that map to SOPS secrets
	secrets: {
		cloudflare: {
			email: #Secret & {
				name: "cloudflare-email"
				path: "\(secretsDir)/cloudflare-email"
			}
			apiKey: #Secret & {
				name: "cloudflare-api-key"
				path: "\(secretsDir)/cloudflare-api-key"
			}
		}
		
		kopia: {
			repositoryToken: #Secret & {
				name: "kopia-repository-token"
				path: "\(secretsDir)/kopia-repository-token"
			}
		}
		
		transmission: {
			rpcPassword: #Secret & {
				name: "transmission-rpc-password"
				path: "\(secretsDir)/transmission-rpc-password"
			}
		}
	}
	
	// Secret validation pipeline
	validate: #SecretValidation & {
		_secrets: secrets
		_config: config
	}
	
	// Secret injection for containers
	inject: #SecretInjection & {
		_secrets: secrets
		_config: config
	}
}

// Individual secret definition
#Secret: {
	name: string
	path: string
	required?: bool | *true
	
	// Validation that secret exists and is accessible
	exists: bash.#Script & {
		script: """
			if [ -f "\(path)" ]; then
				echo "✓ Secret \(name) is available"
			else
				echo "✗ Secret \(name) not found at \(path)"
				exit 1
			fi
		"""
	}
	
	// Read secret value (for use in pipelines)
	read: bash.#Script & {
		script: """
			if [ -f "\(path)" ]; then
				cat "\(path)"
			else
				echo "Secret \(name) not available" >&2
				exit 1
			fi
		"""
	}
}

// Secret validation pipeline
#SecretValidation: {
	_secrets: {...}
	_config: #NixOSConfig
	
	validate: bash.#Script & {
		script: """
			#!/bin/bash
			set -euo pipefail
			
			echo "Validating Dagger secrets..."
			
			secrets_ok=0
			total_secrets=0
			
			# Check Cloudflare secrets (required for ACME)
			total_secrets=$((total_secrets + 1))
			if [ -f "\(_secrets.cloudflare.email.path)" ] && [ -s "\(_secrets.cloudflare.email.path)" ]; then
				echo "✓ Cloudflare email available"
				secrets_ok=$((secrets_ok + 1))
			else
				echo "✗ Cloudflare email missing or empty"
			fi
			
			total_secrets=$((total_secrets + 1))
			if [ -f "\(_secrets.cloudflare.apiKey.path)" ] && [ -s "\(_secrets.cloudflare.apiKey.path)" ]; then
				echo "✓ Cloudflare API key available"
				secrets_ok=$((secrets_ok + 1))
			else
				echo "✗ Cloudflare API key missing or empty"
			fi
			
			# Check Kopia backup token (required for backups)
			total_secrets=$((total_secrets + 1))
			if [ -f "\(_secrets.kopia.repositoryToken.path)" ] && [ -s "\(_secrets.kopia.repositoryToken.path)" ]; then
				echo "✓ Kopia repository token available"
				secrets_ok=$((secrets_ok + 1))
			else
				echo "✗ Kopia repository token missing or empty"
			fi
			
			# Check transmission password
			total_secrets=$((total_secrets + 1))
			if [ -f "\(_secrets.transmission.rpcPassword.path)" ] && [ -s "\(_secrets.transmission.rpcPassword.path)" ]; then
				echo "✓ Transmission RPC password available"
				secrets_ok=$((secrets_ok + 1))
			else
				echo "✗ Transmission RPC password missing or empty"
			fi
			
			echo "Secret validation summary: $secrets_ok/$total_secrets secrets available"
			
			if [ $secrets_ok -lt $total_secrets ]; then
				echo "WARNING: Some secrets are missing - functionality may be limited"
				exit 1
			fi
			
			echo "All required secrets are available"
		"""
	}
}

// Secret injection system for containers
#SecretInjection: {
	_secrets: {...}
	_config: #NixOSConfig
	
	// Inject secrets as environment variables
	injectEnv: {
		// Cloudflare secrets for SSL certificate management
		CLOUDFLARE_EMAIL_FILE: _secrets.cloudflare.email.path
		CLOUDFLARE_DNS_API_TOKEN_FILE: _secrets.cloudflare.apiKey.path
		
		// Kopia backup token
		KOPIA_TOKEN_FILE: _secrets.kopia.repositoryToken.path
		
		// Transmission RPC password
		TRANSMISSION_RPC_PASSWORD_FILE: _secrets.transmission.rpcPassword.path
	}
	
	// Mount secrets as files in containers
	injectMounts: [
		// Cloudflare secrets
		{
			source: _secrets.cloudflare.email.path
			target: "/run/secrets/cloudflare-email"
			readonly: true
		},
		{
			source: _secrets.cloudflare.apiKey.path
			target: "/run/secrets/cloudflare-api-key"
			readonly: true
		},
		
		// Kopia backup token
		{
			source: _secrets.kopia.repositoryToken.path
			target: "/run/secrets/kopia-repository-token"
			readonly: true
		},
		
		// Transmission password
		{
			source: _secrets.transmission.rpcPassword.path
			target: "/run/secrets/transmission-rpc-password"
			readonly: true
		},
	]
	
	// Secret rotation detection
	checkRotation: bash.#Script & {
		script: """
			#!/bin/bash
			set -euo pipefail
			
			echo "Checking for secret rotation..."
			
			rotation_marker="/tmp/dagger-secrets-rotation"
			current_time=$(date +%s)
			
			# Check if any secrets have been modified recently (last 5 minutes)
			find "\(_config.storage.persistRoot)/dagger-secrets" -type f -newermt "5 minutes ago" 2>/dev/null | while read -r file; do
				echo "Secret rotation detected: $file"
				echo "$current_time" > "$rotation_marker"
			done
			
			if [ -f "$rotation_marker" ]; then
				echo "Secret rotation detected - containers should be restarted"
				exit 1
			else
				echo "No secret rotation detected"
			fi
		"""
	}
}

// Enhanced secret operations for specific service types
#ServiceSecrets: {
	service: string
	_secrets: {...}
	_config: #NixOSConfig
	
	// Get secrets relevant to specific services
	getSecrets: bash.#Script & {
		script: """
			#!/bin/bash
			set -euo pipefail
			
			case "\(service)" in
				"homebridge"|"scrypted")
					# These services don't typically need secrets
					echo "No additional secrets required for \(service)"
					;;
				"backup")
					# Backup services need Kopia token
					if [ -f "\(_secrets.kopia.repositoryToken.path)" ]; then
						export KOPIA_TOKEN_FILE="\(_secrets.kopia.repositoryToken.path)"
						echo "Kopia backup token configured"
					else
						echo "Error: Kopia token required for backup service"
						exit 1
					fi
					;;
				"ssl-manager")
					# SSL management needs Cloudflare API access
					if [ -f "\(_secrets.cloudflare.apiKey.path)" ]; then
						export CLOUDFLARE_DNS_API_TOKEN_FILE="\(_secrets.cloudflare.apiKey.path)"
						export CLOUDFLARE_EMAIL_FILE="\(_secrets.cloudflare.email.path)"
						echo "Cloudflare API credentials configured"
					else
						echo "Error: Cloudflare credentials required for SSL management"
						exit 1
					fi
					;;
				"transmission")
					# Transmission needs RPC password
					if [ -f "\(_secrets.transmission.rpcPassword.path)" ]; then
						export TRANSMISSION_RPC_PASSWORD_FILE="\(_secrets.transmission.rpcPassword.path)"
						echo "Transmission RPC password configured"
					else
						echo "Error: Transmission RPC password required"
						exit 1
					fi
					;;
				*)
					echo "Unknown service: \(service)"
					exit 1
					;;
			esac
		"""
	}
}