#!/bin/bash
# Nixarr Migration Tools
# Comprehensive migration utilities for Dagger-enhanced services
# Provides status checking, migration, rollback, and system management

set -euo pipefail

# Configuration
MIGRATION_STATE_FILE="/var/lib/dagger/nixarr-migration-state.json"
SERVICE_REGISTRY="/var/lib/dagger-shared/service-registry.json"
BACKUP_DIR="/var/lib/dagger/backups"
LOG_FILE="/var/log/dagger-tests/migration.log"

# Logging function
log() {
    echo "$(date -Iseconds) $*" | tee -a "$LOG_FILE"
}

# Service definitions
declare -A services=(
    ["sonarr"]="8989"
    ["radarr"]="7878"
    ["prowlarr"]="9696"
    ["bazarr"]="6767"
    ["transmission"]="9091"
    ["jellyfin"]="8096"
    ["pihole"]="8080"
    ["portainer"]="9000"
    ["unpackerr"]="5656"
    ["homebridge"]="8581"
)

# Function to check if service is running
check_service() {
    local service="$1"
    local port="${services[$service]}"
    
    # Check systemd service
    legacy_active=$(systemctl is-active "${service}.service" 2>/dev/null || echo "inactive")
    dagger_active=$(systemctl is-active "dagger-*${service}*.service" 2>/dev/null || echo "inactive")
    
    # Check network endpoint
    network_healthy=false
    if curl -f -s --connect-timeout 5 "http://127.0.0.1:${port}" >/dev/null 2>&1; then
        network_healthy=true
    fi
    
    echo "legacy:$legacy_active,dagger:$dagger_active,network:$network_healthy,port:$port"
}

# Function to show comprehensive status
show_status() {
    log "Generating comprehensive system status..."
    
    echo "=== Dagger Migration Status ==="
    echo "Generated: $(date)"
    echo ""
    
    # Migration state
    if [[ -f "$MIGRATION_STATE_FILE" ]]; then
        echo "=== Migration State ==="
        jq -r '
            "Last Updated: " + (.timestamp // "unknown"),
            "",
            "Service States:",
            (.services // {} | to_entries[] | "  " + .key + ": " + .value.status + " (" + .value.timestamp + ")")
        ' "$MIGRATION_STATE_FILE" 2>/dev/null || echo "Migration state file corrupted"
        echo ""
    fi
    
    # Service status
    echo "=== Service Status ==="
    printf "%-12s %-10s %-10s %-10s %-6s %s\n" "Service" "Legacy" "Dagger" "Network" "Port" "Status"
    printf "%-12s %-10s %-10s %-10s %-6s %s\n" "-------" "------" "------" "-------" "----" "------"
    
    for service in "${!services[@]}"; do
        status_info=$(check_service "$service")
        IFS=',' read -r legacy dagger network port <<< "${status_info//legacy:/} ${status_info//dagger:/} ${status_info//network:/} ${status_info//port:/}"
        
        legacy=${legacy%%,*}
        dagger=${dagger%%,*}
        network=${network%%,*}
        port=${port%%,*}
        
        # Determine overall status
        if [[ "$legacy" == "active" && "$dagger" == "active" ]]; then
            overall="CONFLICT"
        elif [[ "$dagger" == "active" ]]; then
            if [[ "$network" == "true" ]]; then
                overall="DAGGER-OK"
            else
                overall="DAGGER-FAIL"
            fi
        elif [[ "$legacy" == "active" ]]; then
            if [[ "$network" == "true" ]]; then
                overall="LEGACY-OK"
            else
                overall="LEGACY-FAIL"
            fi
        else
            overall="DOWN"
        fi
        
        printf "%-12s %-10s %-10s %-10s %-6s %s\n" "$service" "$legacy" "$dagger" "$network" "$port" "$overall"
    done
    echo ""
    
    # Service discovery
    if [[ -f "$SERVICE_REGISTRY" ]]; then
        echo "=== Service Discovery ==="
        jq -r '
            "Last Check: " + .timestamp,
            "",
            "Discovered Services:",
            (.services // {} | to_entries[] | "  " + .key + ": " + .value.status + " (" + .value.endpoint + ")")
        ' "$SERVICE_REGISTRY" 2>/dev/null || echo "Service registry unavailable"
        echo ""
    fi
    
    # Resource usage
    echo "=== System Resources ==="
    echo "CPU Usage: $(top -bn1 | grep "Cpu(s)" | sed "s/.*, *\([0-9.]*\)%* id.*/\1/" | awk '{print 100 - $1}')%"
    echo "Memory Usage: $(free | grep Mem | awk '{printf("%.1f", $3/$2 * 100.0)}')%"
    
    if [[ -d "/var/lib/nixarr" ]]; then
        echo "Storage (nixarr): $(df -h /var/lib/nixarr | tail -1 | awk '{print $5}') used"
    fi
    
    if [[ -d "/var/lib/dagger" ]]; then
        echo "Storage (dagger): $(df -h /var/lib/dagger | tail -1 | awk '{print $5}') used"
    fi
    
    echo ""
    
    # Port usage
    echo "=== Port Usage ==="
    ss -tlnp | grep -E ':(8989|7878|9696|6767|9091|8096|8080|9000|5656|8581)\s' | while read line; do
        port=$(echo "$line" | awk '{print $4}' | cut -d':' -f2)
        process=$(echo "$line" | awk -F'users:' '{print $2}' | sed 's/[()"]*//g' | awk '{print $1}' | head -1)
        echo "  Port $port: ${process:-unknown}"
    done
    echo ""
    
    # Recent activity
    echo "=== Recent Activity ==="
    echo "Recent Dagger Service Events:"
    journalctl -u 'dagger-*' --since '1 hour ago' --no-pager -n 10 --output=short | tail -5 || echo "No recent activity"
    echo ""
    
    echo "=== Quick Commands ==="
    echo "  migration-tools migrate <service>    - Migrate service to Dagger"
    echo "  migration-tools rollback <service>   - Rollback service to legacy"
    echo "  migration-tools health               - Run health checks"
    echo "  migration-tools backup               - Create system backup"
    echo "  migration-tools validate             - Run full validation"
    echo ""
}

# Function to migrate a service
migrate_service() {
    local service="$1"
    
    if [[ ! "${services[$service]+exists}" ]]; then
        echo "Error: Unknown service '$service'"
        echo "Available services: ${!services[*]}"
        exit 1
    fi
    
    log "Starting migration for service: $service"
    
    # Check current state
    status_info=$(check_service "$service")
    IFS=',' read -r legacy dagger network port <<< "${status_info//legacy:/} ${status_info//dagger:/} ${status_info//network:/} ${status_info//port:/}"
    
    legacy=${legacy%%,*}
    dagger=${dagger%%,*}
    
    if [[ "$dagger" == "active" ]]; then
        log "Service $service already migrated to Dagger"
        return 0
    fi
    
    # Create backup if legacy service is active
    if [[ "$legacy" == "active" ]]; then
        log "Creating pre-migration backup for $service"
        
        backup_path="${BACKUP_DIR}/${service}-pre-migration-$(date +%Y%m%d-%H%M%S)"
        mkdir -p "$backup_path"
        
        # Stop legacy service
        log "Stopping legacy $service service"
        systemctl stop "${service}.service" || true
        
        # Backup data
        if [[ -d "/var/lib/$service" ]]; then
            cp -r "/var/lib/$service" "$backup_path/"
            log "Backed up service data to $backup_path"
        fi
        
        # Backup configuration
        if [[ -d "/etc/$service" ]]; then
            cp -r "/etc/$service" "$backup_path/"
            log "Backed up service config to $backup_path"
        fi
        
        # Disable legacy service
        systemctl disable "${service}.service" || true
    fi
    
    # Start Dagger service
    log "Starting Dagger-managed $service service"
    
    # Determine the correct systemd service name
    case "$service" in
        pihole|portainer)
            dagger_service="dagger-infrastructure-${service}"
            ;;
        unpackerr)
            dagger_service="dagger-automation-${service}"
            ;;
        sonarr|radarr|prowlarr|bazarr|transmission|jellyfin)
            dagger_service="dagger-${service}"
            ;;
        homebridge)
            dagger_service="dagger-automation-homebridge"
            ;;
        *)
            dagger_service="dagger-${service}"
            ;;
    esac
    
    systemctl enable "${dagger_service}.service"
    systemctl start "${dagger_service}.service"
    
    # Wait for service to be ready
    log "Waiting for $service to be ready..."
    port="${services[$service]}"
    
    for i in {1..30}; do
        if curl -f -s --connect-timeout 5 "http://127.0.0.1:${port}" >/dev/null 2>&1; then
            log "✅ Service $service migration completed successfully"
            
            # Update migration state
            update_migration_state "$service" "completed"
            return 0
        fi
        echo "  Waiting for $service to respond... ($i/30)"
        sleep 10
    done
    
    log "❌ Service $service migration failed - service not responding"
    update_migration_state "$service" "failed"
    exit 1
}

# Function to rollback a service
rollback_service() {
    local service="$1"
    
    if [[ ! "${services[$service]+exists}" ]]; then
        echo "Error: Unknown service '$service'"
        exit 1
    fi
    
    log "Starting rollback for service: $service"
    
    # Stop Dagger service
    case "$service" in
        pihole|portainer)
            dagger_service="dagger-infrastructure-${service}"
            ;;
        unpackerr)
            dagger_service="dagger-automation-${service}"
            ;;
        sonarr|radarr|prowlarr|bazarr|transmission|jellyfin)
            dagger_service="dagger-${service}"
            ;;
        homebridge)
            dagger_service="dagger-automation-homebridge"
            ;;
        *)
            dagger_service="dagger-${service}"
            ;;
    esac
    
    if systemctl is-active --quiet "${dagger_service}.service"; then
        log "Stopping Dagger $service service"
        systemctl stop "${dagger_service}.service"
        systemctl disable "${dagger_service}.service"
    fi
    
    # Find most recent backup
    latest_backup=$(find "$BACKUP_DIR" -name "${service}-pre-migration-*" -type d | sort -r | head -n1 || echo "")
    
    if [[ -n "$latest_backup" && -d "$latest_backup" ]]; then
        log "Restoring $service data from $latest_backup"
        
        # Remove current data if it exists
        if [[ -d "/var/lib/$service" ]]; then
            rm -rf "/var/lib/$service"
        fi
        
        # Restore from backup
        if [[ -d "$latest_backup/$service" ]]; then
            cp -r "$latest_backup/$service" "/var/lib/$service"
        else
            cp -r "$latest_backup"/* "/var/lib/" 2>/dev/null || true
        fi
        
        # Fix permissions
        chown -R "${service}:${service}" "/var/lib/$service" 2>/dev/null || true
    else
        log "Warning: No backup found for $service"
    fi
    
    # Re-enable legacy service
    log "Re-enabling legacy $service service"
    systemctl enable "${service}.service"
    systemctl start "${service}.service"
    
    # Wait for service to be ready
    port="${services[$service]}"
    for i in {1..30}; do
        if curl -f -s --connect-timeout 5 "http://127.0.0.1:${port}" >/dev/null 2>&1; then
            log "✅ Service $service rollback completed successfully"
            update_migration_state "$service" "rolled_back"
            return 0
        fi
        echo "  Waiting for legacy $service to respond... ($i/30)"
        sleep 10
    done
    
    log "❌ Service $service rollback failed - service not responding"
    update_migration_state "$service" "rollback_failed"
    exit 1
}

# Function to update migration state
update_migration_state() {
    local service="$1"
    local status="$2"
    local timestamp=$(date -Iseconds)
    
    mkdir -p "$(dirname "$MIGRATION_STATE_FILE")"
    
    if [[ -f "$MIGRATION_STATE_FILE" ]]; then
        jq --arg service "$service" --arg status "$status" --arg timestamp "$timestamp" \
            '.services[$service] = {status: $status, timestamp: $timestamp}' \
            "$MIGRATION_STATE_FILE" > "${MIGRATION_STATE_FILE}.tmp"
    else
        echo '{}' | jq --arg service "$service" --arg status "$status" --arg timestamp "$timestamp" \
            '{timestamp: $timestamp, services: {($service): {status: $status, timestamp: $timestamp}}}' > "${MIGRATION_STATE_FILE}.tmp"
    fi
    
    mv "${MIGRATION_STATE_FILE}.tmp" "$MIGRATION_STATE_FILE"
    chmod 644 "$MIGRATION_STATE_FILE"
}

# Function to run health checks
run_health_checks() {
    log "Running comprehensive health checks..."
    
    echo "=== Health Check Results ==="
    
    # Check Dagger daemon
    if dagger version >/dev/null 2>&1; then
        echo "✅ Dagger daemon is accessible"
    else
        echo "❌ Dagger daemon is not accessible"
    fi
    
    # Check container runtime
    if podman version >/dev/null 2>&1; then
        echo "✅ Podman container runtime is available"
    elif docker version >/dev/null 2>&1; then
        echo "✅ Docker container runtime is available"
    else
        echo "❌ No container runtime available"
    fi
    
    # Check individual services
    for service in "${!services[@]}"; do
        status_info=$(check_service "$service")
        IFS=',' read -r legacy dagger network port <<< "${status_info//legacy:/} ${status_info//dagger:/} ${status_info//network:/} ${status_info//port:/}"
        
        network=${network%%,*}
        dagger=${dagger%%,*}
        
        if [[ "$dagger" == "active" && "$network" == "true" ]]; then
            echo "✅ $service (Dagger) is healthy"
        elif [[ "$dagger" == "active" ]]; then
            echo "⚠️  $service (Dagger) is running but not responding"
        else
            echo "ℹ️  $service is not managed by Dagger"
        fi
    done
    
    # Run validation if available
    if systemctl list-unit-files | grep -q dagger-validation; then
        echo ""
        echo "Running full validation suite..."
        if systemctl start dagger-validation.service; then
            echo "✅ Validation suite completed"
        else
            echo "❌ Validation suite failed"
        fi
    fi
}

# Function to create system backup
create_backup() {
    log "Creating comprehensive system backup..."
    
    backup_root="${BACKUP_DIR}/system-backup-$(date +%Y%m%d-%H%M%S)"
    mkdir -p "$backup_root"
    
    echo "=== System Backup ==="
    echo "Backup location: $backup_root"
    
    # Backup service data
    for service in "${!services[@]}"; do
        if [[ -d "/var/lib/$service" ]]; then
            echo "Backing up $service data..."
            cp -r "/var/lib/$service" "$backup_root/"
        fi
    done
    
    # Backup Dagger configuration
    if [[ -d "/var/lib/dagger" ]]; then
        echo "Backing up Dagger data..."
        cp -r "/var/lib/dagger" "$backup_root/"
    fi
    
    # Backup configuration files
    if [[ -d "/etc/dagger-shared" ]]; then
        echo "Backing up Dagger configuration..."
        cp -r "/etc/dagger-shared" "$backup_root/"
    fi
    
    # Create backup manifest
    cat > "$backup_root/BACKUP_MANIFEST" << EOF
System Backup
Created: $(date)
Hostname: $(hostname)
NixOS Generation: $(nixos-version)

Services Backed Up:
$(for service in "${!services[@]}"; do
    if [[ -d "/var/lib/$service" ]]; then
        echo "  $service: $(du -sh "/var/lib/$service" | cut -f1)"
    fi
done)

Total Backup Size: $(du -sh "$backup_root" | cut -f1)
EOF
    
    echo "✅ System backup completed: $backup_root"
    echo "Backup size: $(du -sh "$backup_root" | cut -f1)"
}

# Main command dispatcher
main() {
    # Ensure log directory exists
    mkdir -p "$(dirname "$LOG_FILE")"
    
    case "${1:-status}" in
        "status"|"st")
            show_status
            ;;
        "migrate"|"mig")
            if [[ $# -lt 2 ]]; then
                echo "Usage: $0 migrate <service|all>"
                echo "Services: ${!services[*]}"
                exit 1
            fi
            
            if [[ "$2" == "all" ]]; then
                for service in "${!services[@]}"; do
                    echo "Migrating $service..."
                    migrate_service "$service" || echo "❌ $service migration failed"
                done
            else
                migrate_service "$2"
            fi
            ;;
        "rollback"|"roll")
            if [[ $# -lt 2 ]]; then
                echo "Usage: $0 rollback <service|all>"
                exit 1
            fi
            
            if [[ "$2" == "all" ]]; then
                for service in "${!services[@]}"; do
                    echo "Rolling back $service..."
                    rollback_service "$service" || echo "❌ $service rollback failed"
                done
            else
                rollback_service "$2"
            fi
            ;;
        "health"|"check")
            run_health_checks
            ;;
        "backup"|"bak")
            create_backup
            ;;
        "validate"|"val")
            if systemctl list-unit-files | grep -q dagger-validation; then
                systemctl start dagger-validation.service
                echo "Validation started. Check results with: dagger-test-results"
            else
                echo "Validation service not available"
                run_health_checks
            fi
            ;;
        "logs")
            echo "=== Recent Dagger Service Logs ==="
            journalctl -u 'dagger-*' --since '1 hour ago' --no-pager -n 50
            ;;
        "help"|"-h"|"--help")
            cat << EOF
Nixarr Migration Tools

Usage: $0 <command> [options]

Commands:
  status (st)              Show comprehensive system status
  migrate (mig) <service>  Migrate service to Dagger management
  rollback (roll) <service> Rollback service to legacy management  
  health (check)           Run health checks on all services
  backup (bak)             Create comprehensive system backup
  validate (val)           Run full validation suite
  logs                     Show recent Dagger service logs
  help                     Show this help message

Services: ${!services[*]}

Examples:
  $0 status                # Show system status
  $0 migrate sonarr        # Migrate Sonarr to Dagger
  $0 migrate all           # Migrate all services
  $0 rollback radarr       # Rollback Radarr to legacy
  $0 health                # Run health checks
  $0 backup                # Create system backup
EOF
            ;;
        *)
            echo "Unknown command: $1"
            echo "Use '$0 help' for usage information"
            exit 1
            ;;
    esac
}

# Run main function with all arguments
main "$@"