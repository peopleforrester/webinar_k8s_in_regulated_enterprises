# Intentionally insecure Dockerfile for demo purposes
# Violates container security best practices
FROM nginx:latest

# Running as root (no USER directive)
# No health check
# No read-only filesystem configuration

COPY index.html /usr/share/nginx/html/index.html

EXPOSE 80
