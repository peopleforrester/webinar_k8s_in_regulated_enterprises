# ============================================================================
# COMPLIANT APPLICATION DOCKERFILE - SECURITY HARDENED
# ============================================================================
#
# PURPOSE:
# This Dockerfile demonstrates SECURE container build practices that meet
# regulatory requirements. Use this as a reference for building production
# container images in regulated environments.
#
# ============================================================================
# SECURITY CONTROLS IMPLEMENTED
# ============================================================================
#
# 1. Pinned Image Version    - nginx:1.25.4-alpine (immutable, auditable)
# 2. Alpine Base Image       - Minimal attack surface (~5MB base)
# 3. Non-Root User           - Runs as UID 101 (nginx user)
# 4. Unprivileged Port       - Listens on port 8080 (no root needed)
# 5. HEALTHCHECK             - Container health monitoring
# 6. Minimal Layers          - Reduced image size and complexity
#
# ============================================================================
# COMPARISON WITH VULNERABLE DOCKERFILE
# ============================================================================
#
# | Aspect              | Vulnerable          | Compliant                    |
# |---------------------|---------------------|------------------------------|
# | Base Image Tag      | :latest (mutable)   | :1.25.4-alpine (pinned)      |
# | Base Image Size     | ~140MB (Debian)     | ~40MB (Alpine)               |
# | User                | root (UID 0)        | nginx (UID 101)              |
# | Port                | 80 (privileged)     | 8080 (unprivileged)          |
# | HEALTHCHECK         | None                | Yes (wget to /healthz)       |
# | Reproducibility     | No                  | Yes                          |
# | CVE Count           | Higher              | Lower                        |
#
# ============================================================================
# REGULATORY ALIGNMENT
# ============================================================================
#
# PCI-DSS:
#   - 2.2: Configuration standards (documented secure configuration)
#   - 6.4.3: Change control (pinned versions, reproducible builds)
#   - 7.2.2: Least privilege (non-root user)
#
# HIPAA:
#   - 164.312(a)(1): Access control (non-root)
#   - 164.312(c)(1): Integrity controls (pinned versions)
#
# SOC 2:
#   - CC6.1: Logical access controls (non-root)
#   - CC7.1: Change management (reproducible builds)
#
# NIST 800-53:
#   - AC-6: Least privilege (non-root, minimal base image)
#   - CM-2: Baseline configuration (documented Dockerfile)
#   - CM-6: Configuration settings (security settings explicit)
#
# ============================================================================
# CONTAINER IMAGE SCANNING
# ============================================================================
#
# This image should be scanned with tools like:
#   - Trivy: trivy image compliant-app:latest
#   - Grype: grype compliant-app:latest
#   - Snyk: snyk container test compliant-app:latest
#
# Alpine-based images typically have:
#   - Fewer packages installed
#   - Fewer known vulnerabilities
#   - Faster security patch updates
#
# ============================================================================

# =============================================================================
# STAGE: Base Image Selection
# =============================================================================
# SECURITY CONTROL: Pinned Version + Alpine
#
# Using nginx:1.25.4-alpine instead of nginx:latest because:
#
# 1. VERSION PINNING (1.25.4):
#    - Immutable reference to specific nginx version
#    - Reproducible builds - same image every time
#    - Audit trail - know exactly what's deployed
#    - Controlled updates - change version deliberately
#
# 2. ALPINE BASE IMAGE:
#    - Minimal OS (~5MB vs ~140MB for Debian)
#    - Fewer packages = fewer vulnerabilities
#    - musl libc instead of glibc (smaller attack surface)
#    - No package managers in default path (harder to exploit)
#
# EVEN BETTER: Use digest for complete immutability:
#   FROM nginx:1.25.4-alpine@sha256:6a2f8b28e45c4adea04ec207a251fd4a2df03ddc930f782af51e315ebc76e9a9
#
# The digest ensures even if 1.25.4-alpine tag is overwritten, you get
# the exact same image.
# =============================================================================
FROM nginx:1.25.4-alpine AS base

# =============================================================================
# FILE OWNERSHIP AND PERMISSIONS
# =============================================================================
# SECURITY CONTROL: Prepare for Non-Root Execution
#
# nginx needs to write to certain directories:
#   - /var/cache/nginx: Proxy cache, fastcgi cache
#   - /var/run: PID files, Unix sockets
#   - /var/log/nginx: Access and error logs
#
# We change ownership to nginx:nginx (UID/GID 101) so the non-root user
# can write to these directories.
#
# NOTE: In the Kubernetes deployment, we mount emptyDir volumes at these
# paths, which provides fresh, writable directories owned by fsGroup.
# =============================================================================
RUN chown -R nginx:nginx /var/cache/nginx /var/run /var/log/nginx && \
# =============================================================================
# SECURITY CONTROL: Unprivileged Port
# =============================================================================
# Change nginx to listen on port 8080 instead of 80.
#
# WHY THIS MATTERS:
#   - Ports < 1024 are "privileged" and require root or CAP_NET_BIND_SERVICE
#   - Port 8080 can be bound by any user
#   - Eliminates need for root or special capabilities
#
# The Kubernetes Service maps external port 80 to container port 8080,
# so clients still connect to standard HTTP port.
# =============================================================================
    sed -i 's/listen       80;/listen       8080;/' /etc/nginx/conf.d/default.conf && \
# =============================================================================
# NGINX CONFIGURATION FOR NON-ROOT
# =============================================================================
# Remove the 'user nginx;' directive from nginx.conf.
#
# WHY THIS MATTERS:
#   - The 'user' directive tells nginx to switch to a different user
#   - This only works when nginx starts as root
#   - Since we're starting as non-root (UID 101), this directive would fail
#   - Removing it allows nginx to run as whatever user started it
# =============================================================================
    sed -i 's/^user  nginx;//' /etc/nginx/nginx.conf

# =============================================================================
# HEALTH CHECK ENDPOINT
# =============================================================================
# SECURITY CONTROL: Container Health Monitoring
#
# Creates a simple /healthz endpoint that returns "OK".
# This endpoint is used by:
#   - Docker HEALTHCHECK (defined below)
#   - Kubernetes livenessProbe and readinessProbe
#
# WHY THIS MATTERS:
#   - Enables automatic detection of unhealthy containers
#   - Kubernetes can restart failed containers
#   - Load balancers can route traffic away from unhealthy pods
#   - Faster incident detection and recovery
#
# In production, consider more sophisticated health checks:
#   - Check database connectivity
#   - Verify critical dependencies
#   - Return detailed status information
# =============================================================================
RUN echo "OK" > /usr/share/nginx/html/healthz

# =============================================================================
# APPLICATION CONTENT
# =============================================================================
# Copy the application's static content.
# This is the actual web content served by nginx.
#
# SECURITY CONSIDERATIONS:
#   - Content is copied during build (immutable in running container)
#   - Combined with readOnlyRootFilesystem, content can't be modified
#   - Any changes require a new image build (tracked, audited)
# =============================================================================
COPY index.html /usr/share/nginx/html/index.html

# =============================================================================
# SECURITY CONTROL: Non-Root User
# =============================================================================
# Switch to the nginx user (UID 101) for all subsequent commands
# and the default runtime user.
#
# WHY THIS MATTERS:
#   - Container processes run as non-root
#   - If container is compromised, attacker has limited privileges
#   - Many CVEs are only exploitable as root
#   - Required for Kubernetes securityContext.runAsNonRoot: true
#
# BEST PRACTICE: Use numeric UID instead of username:
#   USER 101
#
# This avoids potential issues with /etc/passwd manipulation and
# ensures consistent behavior across different base images.
#
# UID 101 is the nginx user in Alpine nginx images.
# =============================================================================
USER 101

# =============================================================================
# EXPOSED PORT
# =============================================================================
# Documents that the container listens on port 8080.
#
# NOTE: EXPOSE doesn't actually publish the port. It's documentation.
# The actual port mapping is done in Kubernetes Service or docker run -p.
#
# Using unprivileged port 8080:
#   - Doesn't require root
#   - Doesn't require CAP_NET_BIND_SERVICE
#   - Standard pattern for containerized applications
# =============================================================================
EXPOSE 8080

# =============================================================================
# SECURITY CONTROL: Container Health Check
# =============================================================================
# Defines how Docker (and some container runtimes) check container health.
#
# PARAMETERS:
#   --interval=30s: Check every 30 seconds
#   --timeout=3s: Fail if check takes longer than 3 seconds
#   --start-period=5s: Wait 5 seconds before first check (startup time)
#   --retries=3: Mark unhealthy after 3 consecutive failures
#
# COMMAND:
#   wget -qO- http://localhost:8080/healthz || exit 1
#   - wget: HTTP client available in Alpine
#   - -q: Quiet mode (no progress output)
#   - O-: Output to stdout
#   - || exit 1: Return failure if wget fails
#
# WHY THIS MATTERS:
#   - Container runtime can detect and restart unhealthy containers
#   - Docker Swarm and ECS use this for health-based scheduling
#   - Kubernetes uses separate livenessProbe/readinessProbe (more flexible)
#
# NOTE: In Kubernetes, the HEALTHCHECK instruction is typically not used.
# Kubernetes probes defined in the Deployment take precedence.
# However, it's still good practice to include for Docker-only environments.
# =============================================================================
HEALTHCHECK --interval=30s --timeout=3s --start-period=5s --retries=3 \
  CMD wget -qO- http://localhost:8080/healthz || exit 1

# =============================================================================
# ADDITIONAL SECURITY HARDENING (Consider for Production)
# =============================================================================
#
# 1. REMOVE SHELL ACCESS (if not needed for debugging):
#    RUN rm /bin/sh /bin/ash
#    # Prevents shell-based exploits
#
# 2. USE SCRATCH OR DISTROLESS BASE (for compiled languages):
#    FROM gcr.io/distroless/static-debian11
#    # Minimal attack surface, no package manager, no shell
#
# 3. LABEL IMAGES FOR TRACEABILITY:
#    LABEL org.opencontainers.image.source="https://github.com/org/repo"
#    LABEL org.opencontainers.image.version="1.0.0"
#    LABEL org.opencontainers.image.vendor="Company Name"
#
# 4. USE MULTI-STAGE BUILDS (for compiled applications):
#    FROM golang:1.21-alpine AS builder
#    WORKDIR /app
#    COPY . .
#    RUN go build -o app .
#
#    FROM gcr.io/distroless/static-debian11
#    COPY --from=builder /app/app /app
#    USER 65534  # nobody user
#    ENTRYPOINT ["/app"]
#
# 5. COPY WITH EXPLICIT OWNERSHIP:
#    COPY --chown=101:101 app /app
#    # Ensures files are owned by non-root user
#
# =============================================================================
# BUILD AND SCAN COMMANDS
# =============================================================================
#
# Build the image:
#   docker build -t compliant-app:1.0.0 .
#
# Scan for vulnerabilities:
#   trivy image compliant-app:1.0.0
#   grype compliant-app:1.0.0
#
# Lint the Dockerfile:
#   hadolint Dockerfile
#
# Test the image:
#   docker run --rm -d -p 8080:8080 --user 101 --read-only \
#     --tmpfs /tmp --tmpfs /var/cache/nginx --tmpfs /var/run \
#     compliant-app:1.0.0
#   curl http://localhost:8080/healthz
#
# =============================================================================
