# Dagger Services Validation and Testing Infrastructure
# Comprehensive validation, testing, and health check system for all Dagger services
# Provides automated testing, dependency validation, and system health monitoring

{
  config,
  lib,
  pkgs,
  ...
}:

with lib;

let
  cfg = config.services.dagger.validation;
  
  # Test configuration for each service
  serviceTests = {
    pihole = {
      name = "Pi-hole DNS Service";
      enabled = config.services.dagger.pihole.enable;
      port = config.services.dagger.pihole.webPort;
      dnsPort = config.services.dagger.pihole.dnsPort;
      healthEndpoint = "/admin/api.php";
      dependencies = [ "network" "dns" ];
      critical = true;
    };
    
    portainer = {
      name = "Portainer Container Management";
      enabled = config.services.dagger.portainer.enable;
      port = config.services.dagger.portainer.port;
      healthEndpoint = "/api/status";
      dependencies = [ "network" "container-runtime" ];
      critical = false;
    };
    
    unpackerr = {
      name = "Unpackerr Archive Extraction";
      enabled = config.services.dagger.unpackerr.enable;
      port = if config.services.dagger.unpackerr.webui.enable then config.services.dagger.unpackerr.webui.port else null;
      healthEndpoint = if config.services.dagger.unpackerr.webui.enable then "/api/health" else null;
      dependencies = [ "network" "filesystem" "nixarr-services" ];
      critical = false;
    };
    
    nixarr = {
      name = "Enhanced Nixarr Services";
      enabled = config.services.dagger.nixarr.enable or false;
      dependencies = [ "network" "filesystem" "container-runtime" ];
      critical = true;
    };
    
    homebridge = {
      name = "Dagger Homebridge Service";
      enabled = config.services.dagger.homebridge.enable or false;
      port = config.services.dagger.homebridge.port or null;
      healthEndpoint = "/";
      dependencies = [ "network" "homekit" ];
      critical = false;
    };
  };
  
  # Dependency test definitions
  dependencyTests = {
    network = {
      name = "Network Connectivity";
      test = "ping -c 1 1.1.1.1 > /dev/null 2>&1";
      description = "Test external network connectivity";
    };
    
    dns = {
      name = "DNS Resolution";
      test = "nslookup google.com > /dev/null 2>&1";
      description = "Test DNS resolution capability";
    };
    
    container-runtime = {
      name = "Container Runtime";
      test = if config.services.dagger.portainer.containerRuntime == "podman" 
             then "podman version > /dev/null 2>&1"
             else "docker version > /dev/null 2>&1";
      description = "Test container runtime availability";
    };
    
    filesystem = {
      name = "Filesystem Access";
      test = "[ -d '${config.services.dagger.workingDirectory}' ] && [ -w '${config.services.dagger.workingDirectory}' ]";
      description = "Test filesystem access for Dagger services";
    };
    
    nfs-storage = {
      name = "NFS Storage";
      test = "[ ! -d '/mnt/docker-data' ] || (mountpoint -q '/mnt/docker-data' && timeout 10 touch '/mnt/docker-data/.dagger-validation-test' && rm -f '/mnt/docker-data/.dagger-validation-test')";
      description = "Test NFS storage availability and write access";
    };
    
    nixarr-services = {
      name = "Nixarr Service Integration";
      test = "curl -f -s --connect-timeout 5 http://127.0.0.1:8989/api/v3/system/status > /dev/null 2>&1 || curl -f -s --connect-timeout 5 http://127.0.0.1:7878/api/v3/system/status > /dev/null 2>&1";
      description = "Test Nixarr service availability for integration";
    };
    
    homekit = {
      name = "HomeKit Network Access";
      test = "nc -z -w 5 127.0.0.1 ${toString (config.services.dagger.homebridge.port or 8581)} > /dev/null 2>&1";
      description = "Test HomeKit service network access";
    };
  };
  
in {
  options.services.dagger.validation = {
    enable = mkEnableOption "Dagger services validation and testing infrastructure";
    
    continuousTesting = mkOption {
      type = types.bool;
      default = true;
      description = "Enable continuous health testing of Dagger services";
    };
    
    testInterval = mkOption {
      type = types.str;
      default = "5m";
      description = "Interval for continuous testing (systemd timer format)";
    };
    
    integrationTests = mkOption {
      type = types.bool;
      default = true;
      description = "Enable integration testing between services";
    };
    
    performanceTests = mkOption {
      type = types.bool;
      default = false;
      description = "Enable performance testing and benchmarking";
    };
    
    alertOnFailure = mkOption {
      type = types.bool;
      default = true;
      description = "Send alerts when critical services fail validation";
    };
    
    testReportsDir = mkOption {
      type = types.path;
      default = "/var/lib/dagger/test-reports";
      description = "Directory for storing test reports and logs";
    };
    
    maxTestDuration = mkOption {
      type = types.str;
      default = "300s";
      description = "Maximum duration for individual tests";
    };
    
    retryFailedTests = mkOption {
      type = types.int;
      default = 3;
      description = "Number of retries for failed tests";
    };
    
    enableMetrics = mkOption {
      type = types.bool;
      default = true;
      description = "Enable metrics collection for test results";
    };
    
    testSuites = mkOption {
      type = types.listOf (types.enum [ "basic" "integration" "performance" "security" ]);
      default = [ "basic" "integration" ];
      description = "Test suites to run";
    };
  };
  
  config = mkIf cfg.enable {
    
    # Create test directories and files
    systemd.tmpfiles.rules = [
      "d ${cfg.testReportsDir} 0755 root root -"
      "d ${cfg.testReportsDir}/current 0755 root root -"
      "d ${cfg.testReportsDir}/history 0755 root root -"
      "d /var/lib/dagger/test-configs 0755 root root -"
      "d /var/log/dagger-tests 0755 root root -"
    ];
    
    # Main validation service
    systemd.services.dagger-validation = {
      description = "Dagger Services Validation and Testing";
      after = [ "dagger-coordinator.service" ];
      
      serviceConfig = {
        Type = "oneshot";
        User = "root";
        Group = "root";
        TimeoutStartSec = cfg.maxTestDuration;
        
        # Allow network access for tests
        PrivateNetwork = false;
      };
      
      script = ''
        #!/bin/bash
        set -euo pipefail
        
        # Test execution
        exec 2>&1
        test_start_time=$(date +%s)
        test_id="validation-$(date +%Y%m%d-%H%M%S)"
        test_report="${cfg.testReportsDir}/current/$test_id.json"
        
        echo "=== Dagger Services Validation Started ==="
        echo "Test ID: $test_id"
        echo "Timestamp: $(date -Iseconds)"
        echo ""
        
        # Initialize test report
        mkdir -p "$(dirname "$test_report")"
        cat > "$test_report" << EOF
        {
          "test_id": "$test_id",
          "start_time": "$(date -Iseconds)",
          "test_suites": ${builtins.toJSON cfg.testSuites},
          "results": {
            "dependencies": {},
            "services": {},
            "integration": {},
            "performance": {},
            "security": {}
          },
          "summary": {
            "total_tests": 0,
            "passed": 0,
            "failed": 0,
            "skipped": 0
          }
        }
        EOF
        
        total_tests=0
        passed_tests=0
        failed_tests=0
        skipped_tests=0
        
        # Function to update test report
        update_report() {
          local category="$1"
          local test_name="$2"
          local status="$3"
          local message="$4"
          local duration="$5"
          
          ${pkgs.jq}/bin/jq --arg cat "$category" --arg name "$test_name" --arg status "$status" --arg msg "$message" --arg dur "$duration" \
            '.results[$cat][$name] = {status: $status, message: $msg, duration: $dur, timestamp: now | todate}' \
            "$test_report" > "$test_report.tmp" && mv "$test_report.tmp" "$test_report"
        }
        
        # Run dependency tests
        ${optionalString (elem "basic" cfg.testSuites) ''
        echo "=== Dependency Tests ==="
        ${concatStringsSep "\n        " (mapAttrsToList (depName: depTest: ''
        echo -n "Testing ${depTest.name}... "
        test_start=$(date +%s.%3N)
        if timeout 30 bash -c '${depTest.test}'; then
          test_end=$(date +%s.%3N)
          duration=$(echo "$test_end - $test_start" | bc)
          echo "✓ PASS ($duration s)"
          update_report "dependencies" "${depName}" "PASS" "${depTest.description}" "$duration"
          ((passed_tests++))
        else
          test_end=$(date +%s.%3N)
          duration=$(echo "$test_end - $test_start" | bc)
          echo "✗ FAIL ($duration s)"
          update_report "dependencies" "${depName}" "FAIL" "${depTest.description}" "$duration"
          ((failed_tests++))
        fi
        ((total_tests++))
        '') dependencyTests)}
        echo ""
        ''}
        
        # Run service tests
        ${optionalString (elem "basic" cfg.testSuites) ''
        echo "=== Service Health Tests ==="
        ${concatStringsSep "\n        " (mapAttrsToList (serviceName: serviceTest: 
          optionalString serviceTest.enabled ''
          echo -n "Testing ${serviceTest.name}... "
          test_start=$(date +%s.%3N)
          
          service_healthy=true
          error_msg=""
          
          # Test service process
          if ! systemctl is-active --quiet "dagger-*${serviceName}*"; then
            service_healthy=false
            error_msg="Service not running"
          fi
          
          # Test network endpoint if available
          ${optionalString (serviceTest.port != null && serviceTest.healthEndpoint != null) ''
          if [ "$service_healthy" = true ] && ! curl -f -s --connect-timeout 10 --max-time 30 "http://127.0.0.1:${toString serviceTest.port}${serviceTest.healthEndpoint}" > /dev/null; then
            service_healthy=false
            error_msg="Health endpoint unreachable"
          fi
          ''}
          
          test_end=$(date +%s.%3N)
          duration=$(echo "$test_end - $test_start" | bc)
          
          if [ "$service_healthy" = true ]; then
            echo "✓ PASS ($duration s)"
            update_report "services" "${serviceName}" "PASS" "Service healthy" "$duration"
            ((passed_tests++))
          else
            echo "✗ FAIL ($duration s) - $error_msg"
            update_report "services" "${serviceName}" "FAIL" "$error_msg" "$duration"
            ((failed_tests++))
          fi
          ((total_tests++))
          ''
        ) serviceTests)}
        echo ""
        ''}
        
        # Run integration tests
        ${optionalString (elem "integration" cfg.testSuites && cfg.integrationTests) ''
        echo "=== Integration Tests ==="
        
        # Test Pi-hole + DNS integration
        ${optionalString (config.services.dagger.pihole.enable) ''
        echo -n "Testing Pi-hole DNS integration... "
        test_start=$(date +%s.%3N)
        if dig @127.0.0.1 -p ${toString config.services.dagger.pihole.dnsPort} google.com +short | grep -q .; then
          test_end=$(date +%s.%3N)
          duration=$(echo "$test_end - $test_start" | bc)
          echo "✓ PASS ($duration s)"
          update_report "integration" "pihole_dns" "PASS" "DNS resolution working" "$duration"
          ((passed_tests++))
        else
          test_end=$(date +%s.%3N)
          duration=$(echo "$test_end - $test_start" | bc)
          echo "✗ FAIL ($duration s)"
          update_report "integration" "pihole_dns" "FAIL" "DNS resolution failed" "$duration"
          ((failed_tests++))
        fi
        ((total_tests++))
        ''}
        
        # Test Portainer + Container Runtime integration
        ${optionalString (config.services.dagger.portainer.enable) ''
        echo -n "Testing Portainer container integration... "
        test_start=$(date +%s.%3N)
        if curl -f -s --connect-timeout 10 "http://127.0.0.1:${toString config.services.dagger.portainer.port}/api/endpoints" | grep -q "Name"; then
          test_end=$(date +%s.%3N)
          duration=$(echo "$test_end - $test_start" | bc)
          echo "✓ PASS ($duration s)"
          update_report "integration" "portainer_containers" "PASS" "Container management working" "$duration"
          ((passed_tests++))
        else
          test_end=$(date +%s.%3N)
          duration=$(echo "$test_end - $test_start" | bc)
          echo "✗ FAIL ($duration s)"
          update_report "integration" "portainer_containers" "FAIL" "Container management failed" "$duration"
          ((failed_tests++))
        fi
        ((total_tests++))
        ''}
        
        # Test Unpackerr + Nixarr integration
        ${optionalString (config.services.dagger.unpackerr.enable && (config.services.dagger.unpackerr.sonarr.enable || config.services.dagger.unpackerr.radarr.enable)) ''
        echo -n "Testing Unpackerr nixarr integration... "
        test_start=$(date +%s.%3N)
        integration_working=false
        
        ${optionalString config.services.dagger.unpackerr.sonarr.enable ''
        if curl -f -s --connect-timeout 5 "http://127.0.0.1:${toString config.services.dagger.unpackerr.sonarr.port}/api/v3/system/status" > /dev/null; then
          integration_working=true
        fi
        ''}
        
        ${optionalString config.services.dagger.unpackerr.radarr.enable ''
        if curl -f -s --connect-timeout 5 "http://127.0.0.1:${toString config.services.dagger.unpackerr.radarr.port}/api/v3/system/status" > /dev/null; then
          integration_working=true
        fi
        ''}
        
        test_end=$(date +%s.%3N)
        duration=$(echo "$test_end - $test_start" | bc)
        
        if [ "$integration_working" = true ]; then
          echo "✓ PASS ($duration s)"
          update_report "integration" "unpackerr_nixarr" "PASS" "Nixarr integration working" "$duration"
          ((passed_tests++))
        else
          echo "✗ FAIL ($duration s)"
          update_report "integration" "unpackerr_nixarr" "FAIL" "Nixarr integration failed" "$duration"
          ((failed_tests++))
        fi
        ((total_tests++))
        ''}
        
        echo ""
        ''}
        
        # Run performance tests
        ${optionalString (elem "performance" cfg.testSuites && cfg.performanceTests) ''
        echo "=== Performance Tests ==="
        
        # Test response times
        ${concatStringsSep "\n        " (mapAttrsToList (serviceName: serviceTest: 
          optionalString (serviceTest.enabled && serviceTest.port != null) ''
          echo -n "Testing ${serviceTest.name} response time... "
          test_start=$(date +%s.%3N)
          
          # Measure response time
          response_time=$(curl -w "%{time_total}" -s -o /dev/null --connect-timeout 5 --max-time 10 "http://127.0.0.1:${toString serviceTest.port}${serviceTest.healthEndpoint or "/"}" || echo "timeout")
          
          test_end=$(date +%s.%3N)
          duration=$(echo "$test_end - $test_start" | bc)
          
          if [ "$response_time" != "timeout" ] && (( $(echo "$response_time < 2.0" | bc -l) )); then
            echo "✓ PASS ($duration s) - Response: $response_time s"
            update_report "performance" "${serviceName}_response" "PASS" "Response time: $response_time s" "$duration"
            ((passed_tests++))
          else
            echo "✗ FAIL ($duration s) - Response: $response_time s"
            update_report "performance" "${serviceName}_response" "FAIL" "Slow response: $response_time s" "$duration"
            ((failed_tests++))
          fi
          ((total_tests++))
          ''
        ) serviceTests)}
        
        echo ""
        ''}
        
        # Update final summary
        test_end_time=$(date +%s)
        total_duration=$((test_end_time - test_start_time))
        
        ${pkgs.jq}/bin/jq --arg end "$(date -Iseconds)" --arg dur "$total_duration" \
          --argjson total "$total_tests" --argjson passed "$passed_tests" --argjson failed "$failed_tests" --argjson skipped "$skipped_tests" \
          '.end_time = $end | .duration = ($dur + "s") | .summary.total_tests = $total | .summary.passed = $passed | .summary.failed = $failed | .summary.skipped = $skipped' \
          "$test_report" > "$test_report.tmp" && mv "$test_report.tmp" "$test_report"
        
        # Print summary
        echo "=== Test Summary ==="
        echo "Total Tests: $total_tests"
        echo "Passed: $passed_tests"
        echo "Failed: $failed_tests"
        echo "Skipped: $skipped_tests"
        echo "Duration: $total_duration seconds"
        echo ""
        
        # Copy to history
        cp "$test_report" "${cfg.testReportsDir}/history/"
        
        # Clean up old reports (keep last 10)
        cd "${cfg.testReportsDir}/history"
        ls -t *.json | tail -n +11 | xargs -r rm
        
        # Create symlink to latest
        ln -sf "$test_report" "${cfg.testReportsDir}/latest.json"
        
        ${optionalString cfg.alertOnFailure ''
        # Alert on critical failures
        critical_failures=0
        ${concatStringsSep "\n        " (mapAttrsToList (serviceName: serviceTest: 
          optionalString (serviceTest.enabled && serviceTest.critical) ''
          if ${pkgs.jq}/bin/jq -e '.results.services.${serviceName}.status == "FAIL"' "$test_report" > /dev/null 2>&1; then
            echo "CRITICAL: ${serviceTest.name} failed validation!"
            ((critical_failures++))
          fi
          ''
        ) serviceTests)}
        
        if [ $critical_failures -gt 0 ]; then
          echo "=== CRITICAL ALERT ==="
          echo "$critical_failures critical service(s) failed validation!"
          echo "Report: $test_report"
          # Here you could integrate with alerting systems
          exit 1
        fi
        ''}
        
        if [ $failed_tests -eq 0 ]; then
          echo "✅ All tests passed!"
          exit 0
        else
          echo "⚠️  $failed_tests test(s) failed"
          ${optionalString cfg.alertOnFailure "exit 1"}
        fi
      '';
    };
    
    # Continuous testing timer
    systemd.timers.dagger-validation = mkIf cfg.continuousTesting {
      description = "Dagger Services Continuous Validation";
      wantedBy = [ "timers.target" ];
      
      timerConfig = {
        OnCalendar = "*:0/${cfg.testInterval}";
        RandomizedDelaySec = "30s";
        Persistent = true;
      };
    };
    
    # Test report web server (optional)
    systemd.services.dagger-test-server = {
      description = "Dagger Test Reports Web Server";
      after = [ "network.target" ];
      
      serviceConfig = {
        Type = "simple";
        User = "nobody";
        Group = "nobody";
        Restart = "on-failure";
        RestartSec = "5s";
        
        # Security hardening
        NoNewPrivileges = true;
        ProtectSystem = "strict";
        ProtectHome = true;
        ReadOnlyPaths = [ cfg.testReportsDir ];
        PrivateTmp = true;
        PrivateDevices = true;
        ProtectKernelTunables = true;
        ProtectKernelModules = true;
        ProtectControlGroups = true;
      };
      
      script = ''
        #!/bin/bash
        cd "${cfg.testReportsDir}"
        
        # Simple HTTP server for test reports
        ${pkgs.python3}/bin/python3 -m http.server 8899 --bind 127.0.0.1
      '';
    };
    
    # Metrics collection service
    systemd.services.dagger-test-metrics = mkIf cfg.enableMetrics {
      description = "Dagger Test Metrics Collector";
      after = [ "dagger-validation.service" ];
      
      serviceConfig = {
        Type = "oneshot";
        User = "root";
        Group = "root";
      };
      
      script = ''
        #!/bin/bash
        
        # Collect metrics from latest test report
        latest_report="${cfg.testReportsDir}/latest.json"
        
        if [ ! -f "$latest_report" ]; then
          exit 0
        fi
        
        # Extract metrics
        total_tests=$(${pkgs.jq}/bin/jq -r '.summary.total_tests // 0' "$latest_report")
        passed_tests=$(${pkgs.jq}/bin/jq -r '.summary.passed // 0' "$latest_report")
        failed_tests=$(${pkgs.jq}/bin/jq -r '.summary.failed // 0' "$latest_report")
        
        # Write metrics in Prometheus format
        metrics_file="/var/lib/dagger/metrics/validation.prom"
        mkdir -p "$(dirname "$metrics_file")"
        
        cat > "$metrics_file" << EOF
        # HELP dagger_validation_tests_total Total number of validation tests
        # TYPE dagger_validation_tests_total counter
        dagger_validation_tests_total $total_tests
        
        # HELP dagger_validation_tests_passed Number of passed validation tests  
        # TYPE dagger_validation_tests_passed counter
        dagger_validation_tests_passed $passed_tests
        
        # HELP dagger_validation_tests_failed Number of failed validation tests
        # TYPE dagger_validation_tests_failed counter
        dagger_validation_tests_failed $failed_tests
        
        # HELP dagger_validation_success_rate Success rate of validation tests
        # TYPE dagger_validation_success_rate gauge
        dagger_validation_success_rate $(echo "scale=2; $passed_tests / $total_tests" | bc)
        EOF
        
        echo "Test metrics updated: $metrics_file"
      '';
    };
    
    # Utility commands for test management
    environment.systemPackages = [
      # Run tests manually
      (pkgs.writeShellScriptBin "dagger-test" ''
        #!/bin/bash
        echo "Running Dagger services validation..."
        systemctl start dagger-validation.service
        echo "Test completed. View results:"
        echo "  dagger-test-results"
      '')
      
      # View test results
      (pkgs.writeShellScriptBin "dagger-test-results" ''
        #!/bin/bash
        latest_report="${cfg.testReportsDir}/latest.json"
        
        if [ ! -f "$latest_report" ]; then
          echo "No test results available. Run: dagger-test"
          exit 1
        fi
        
        echo "=== Latest Test Results ==="
        ${pkgs.jq}/bin/jq -r '
          "Test ID: " + .test_id,
          "Start Time: " + .start_time,
          "End Time: " + (.end_time // "running"),
          "Duration: " + (.duration // "unknown"),
          "",
          "=== Summary ===",
          "Total Tests: " + (.summary.total_tests | tostring),
          "Passed: " + (.summary.passed | tostring),  
          "Failed: " + (.summary.failed | tostring),
          "Skipped: " + (.summary.skipped | tostring),
          ""
        ' "$latest_report"
        
        # Show failures
        failures=$(${pkgs.jq}/bin/jq -r '
          [.results[][] | select(.status == "FAIL")] |
          if length > 0 then
            "=== Failures ===",
            (.[] | "❌ " + .timestamp + ": " + .message)
          else
            "✅ No failures detected"
          end
        ' "$latest_report")
        
        echo "$failures"
        
        echo ""
        echo "Full report: $latest_report"
        echo "Web interface: http://localhost:8899/latest.json"
      '')
      
      # Test specific service
      (pkgs.writeShellScriptBin "dagger-test-service" ''
        #!/bin/bash
        if [ $# -eq 0 ]; then
          echo "Usage: dagger-test-service <service>"
          echo "Services: ${concatStringsSep " " (attrNames (filterAttrs (n: v: v.enabled) serviceTests))}"
          exit 1
        fi
        
        service="$1"
        
        case "$service" in
          ${concatStringsSep "\n          " (mapAttrsToList (serviceName: serviceTest: 
            optionalString serviceTest.enabled ''
            ${serviceName})
              echo "Testing ${serviceTest.name}..."
              ${optionalString (serviceTest.port != null && serviceTest.healthEndpoint != null) ''
              curl -f -s --connect-timeout 10 "http://127.0.0.1:${toString serviceTest.port}${serviceTest.healthEndpoint}" || {
                echo "❌ ${serviceTest.name} health check failed"
                exit 1
              }
              ''}
              systemctl is-active --quiet "dagger-*${serviceName}*" || {
                echo "❌ ${serviceTest.name} service not running"
                exit 1  
              }
              echo "✅ ${serviceTest.name} is healthy"
              ;;
            ''
          ) serviceTests)}
          *)
            echo "Unknown service: $service"
            exit 1
            ;;
        esac
      '')
      
      # Continuous test monitoring
      (pkgs.writeShellScriptBin "dagger-test-monitor" ''
        #!/bin/bash
        echo "Monitoring Dagger test results (Ctrl+C to stop)..."
        
        while true; do
          if [ -f "${cfg.testReportsDir}/latest.json" ]; then
            timestamp=$(${pkgs.jq}/bin/jq -r '.end_time // .start_time' "${cfg.testReportsDir}/latest.json")
            passed=$(${pkgs.jq}/bin/jq -r '.summary.passed' "${cfg.testReportsDir}/latest.json")
            failed=$(${pkgs.jq}/bin/jq -r '.summary.failed' "${cfg.testReportsDir}/latest.json")
            
            echo "$(date): Tests - ✅ $passed ❌ $failed (Last: $timestamp)"
          else
            echo "$(date): No test results available"
          fi
          
          sleep 30
        done
      '')
    ];
    
    # Web interface for test reports
    services.nginx.virtualHosts."tests.orther.dev" = mkIf config.services.nginx.enable {
      forceSSL = true;
      useACMEHost = "orther.dev";
      
      locations."/" = {
        proxyPass = "http://127.0.0.1:8899";
        extraConfig = ''
          # Enable directory browsing
          autoindex on;
          autoindex_exact_size off;
          autoindex_localtime on;
        '';
      };
      
      locations."/api/latest" = {
        alias = "${cfg.testReportsDir}/latest.json";
        extraConfig = ''
          add_header Content-Type application/json;
          add_header Access-Control-Allow-Origin *;
        '';
      };
    };
    
    # Persistence for test data
    environment.persistence."/nix/persist" = mkIf config.environment.persistence."/nix/persist".enable {
      directories = [
        cfg.testReportsDir
        "/var/lib/dagger/test-configs"
        "/var/lib/dagger/metrics"
        "/var/log/dagger-tests"
      ];
    };
    
    # Log rotation for test logs
    services.logrotate.settings.dagger-tests = {
      files = "/var/log/dagger-tests/*.log";
      frequency = "weekly";
      rotate = 4;
      compress = true;
      delaycompress = true;
      missingok = true;
      notifempty = true;
      create = "644 root root";
    };
  };
}