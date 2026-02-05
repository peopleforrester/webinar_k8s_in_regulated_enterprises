# Hardened Dockerfile for compliant application
# Follows container security best practices
FROM nginx:1.25.4-alpine AS base

# Run as non-root nginx user
RUN chown -R nginx:nginx /var/cache/nginx /var/run /var/log/nginx && \
    sed -i 's/listen       80;/listen       8080;/' /etc/nginx/conf.d/default.conf && \
    sed -i 's/^user  nginx;//' /etc/nginx/nginx.conf

# Add health check endpoint
RUN echo "OK" > /usr/share/nginx/html/healthz

COPY index.html /usr/share/nginx/html/index.html

USER 101

EXPOSE 8080

HEALTHCHECK --interval=30s --timeout=3s --start-period=5s --retries=3 \
  CMD wget -qO- http://localhost:8080/healthz || exit 1
