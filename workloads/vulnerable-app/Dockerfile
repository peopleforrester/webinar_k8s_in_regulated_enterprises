# ============================================================================
# VULNERABLE APPLICATION DOCKERFILE - INTENTIONALLY INSECURE
# ============================================================================
#
# PURPOSE:
# This Dockerfile demonstrates INSECURE container build practices that
# should be avoided in production environments. Use this as a teaching tool
# to understand container security anti-patterns.
#
# WARNING: DO NOT use this pattern in production. See compliant-app/Dockerfile
# for secure container build practices.
#
# ============================================================================
# SECURITY VIOLATIONS SUMMARY
# ============================================================================
#
# This Dockerfile violates the following security best practices:
#
# 1. Uses :latest tag (mutable, unpredictable)
# 2. Runs as root (no USER directive)
# 3. No HEALTHCHECK defined
# 4. No multi-stage build (larger attack surface)
# 5. Full base image (not -alpine or -slim)
# 6. No explicit package version pinning
#
# ============================================================================
# DETAILED VIOLATION ANALYSIS
# ============================================================================
#
# VIOLATION 1: Using :latest Tag
# ------------------------------
# Problem: image: nginx:latest
#
# Why this is dangerous:
#   - :latest is mutable - it changes when new versions are pushed
#   - Builds are not reproducible
#   - You can't audit what exact version is running
#   - Supply chain attacks: attacker pushes malicious :latest
#   - Breaks rollback capability
#
# Regulatory impact:
#   - PCI-DSS 6.4.3: Requires tracking changes to system components
#   - NIST 800-53 CM-2: Configuration baseline management
#
# Secure alternative:
#   FROM nginx:1.25.4-alpine
#   Or even better, use image digest:
#   FROM nginx@sha256:6af79ae5de407283dcea8b00d5c37ace95441fd58a8b1d2aa1ed93f5511bb18c
#
#
# VIOLATION 2: Running as Root
# ----------------------------
# Problem: No USER directive
#
# By default, containers run as root (UID 0). This means:
#   - If an attacker exploits a vulnerability, they have root access
#   - Root in container can exploit kernel vulnerabilities for escape
#   - Many CVEs are only exploitable as root
#
# Regulatory impact:
#   - PCI-DSS 7.2.2: Limit access based on job function
#   - NIST 800-53 AC-6: Principle of least privilege
#   - CIS Docker Benchmark 4.1: Create a user for the container
#
# Secure alternative:
#   # Create non-root user
#   RUN useradd --uid 10001 --no-create-home --shell /bin/false appuser
#   USER 10001
#
#
# VIOLATION 3: No HEALTHCHECK
# ---------------------------
# Problem: No HEALTHCHECK instruction
#
# Without HEALTHCHECK:
#   - Container may appear running but be unresponsive
#   - No automatic recovery from hung processes
#   - Orchestrator can't accurately track container health
#
# Impact:
#   - Reduced availability
#   - Slower failure detection
#   - Poor user experience during outages
#
# Secure alternative:
#   HEALTHCHECK --interval=30s --timeout=3s --start-period=5s --retries=3 \
#     CMD wget -qO- http://localhost:80/healthz || exit 1
#
#
# VIOLATION 4: No Multi-Stage Build
# ---------------------------------
# Problem: Single FROM stage
#
# Without multi-stage builds:
#   - Larger image size
#   - Build tools included in production image
#   - Larger attack surface
#   - More potential vulnerabilities
#
# Secure alternative:
#   # Build stage
#   FROM nginx:1.25.4-alpine AS builder
#   # ... build steps ...
#
#   # Production stage
#   FROM nginx:1.25.4-alpine AS production
#   COPY --from=builder /app/build /usr/share/nginx/html
#   USER 101
#
#
# VIOLATION 5: Full Base Image (not Alpine)
# -----------------------------------------
# Problem: nginx:latest (Debian-based, ~140MB)
#
# Full images include:
#   - Package managers (apt, dpkg)
#   - Shell utilities (bash, grep, curl)
#   - Development libraries
#   - More attack surface
#
# Alpine-based images:
#   - ~5MB base size
#   - Minimal utilities (ash shell, busybox)
#   - Fewer packages = fewer vulnerabilities
#
# Secure alternative:
#   FROM nginx:1.25.4-alpine
#
#
# VIOLATION 6: Port 80 (Privileged Port)
# --------------------------------------
# Problem: EXPOSE 80
#
# Ports below 1024 require either:
#   - Root user
#   - CAP_NET_BIND_SERVICE capability
#
# This encourages running as root or adding unnecessary capabilities.
#
# Secure alternative:
#   EXPOSE 8080
#   # And configure nginx to listen on 8080
#
# ============================================================================
# COMPARISON: Vulnerable vs Compliant Dockerfile
# ============================================================================
#
# | Aspect              | Vulnerable          | Compliant                    |
# |---------------------|---------------------|------------------------------|
# | Base Image          | nginx:latest        | nginx:1.25.4-alpine          |
# | Image Size          | ~140MB              | ~40MB                        |
# | User                | root (UID 0)        | nginx (UID 101)              |
# | Port                | 80 (privileged)     | 8080 (unprivileged)          |
# | HEALTHCHECK         | None                | wget to /healthz             |
# | Reproducible        | No                  | Yes                          |
# | Attack Surface      | Large               | Minimal                      |
#
# ============================================================================
# KYVERNO/OPA POLICIES THAT WOULD FLAG THIS
# ============================================================================
#
# In a CI/CD pipeline, image scanning tools would flag:
#
# 1. Trivy/Grype: Vulnerability scan would find more CVEs in full image
# 2. Conftest/OPA: Policy check would fail on:
#    - :latest tag usage
#    - No USER instruction
#    - Privileged port
# 3. Dockerfile linting (hadolint) would warn about all these issues
#
# Example hadolint output:
#   DL3007 warning: Using latest is prone to errors
#   DL3002 warning: Last USER should not be root
#   DL3048 info: Invalid label key
#
# ============================================================================

# VIOLATION: Using :latest tag - unpredictable, non-reproducible builds
FROM nginx:latest

# VIOLATION: No USER directive - container runs as root (UID 0)
# Any commands run without USER will execute as root
# If nginx process is compromised, attacker has root access

# VIOLATION: No HEALTHCHECK - container health cannot be monitored
# Kubernetes probes can partially compensate, but Docker-level health
# checks are still a best practice for container hygiene

# VIOLATION: Not optimizing for security
# Missing:
#   - chown to non-root user
#   - chmod to restrict permissions
#   - removal of unnecessary capabilities in the image

# Copy application content
# At least this is minimal, but still owned by root
COPY index.html /usr/share/nginx/html/index.html

# VIOLATION: Privileged port - requires root or CAP_NET_BIND_SERVICE
EXPOSE 80

# MISSING: HEALTHCHECK instruction
# Container orchestrators rely on this for health monitoring
