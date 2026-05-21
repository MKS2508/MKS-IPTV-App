# Dockerfile - Multiplatform build for mksiptv-server
# This is optional, intended for testing only. Primary deployment is static binary + systemd.
#
# Build:
#   docker buildx build --platform linux/amd64,linux/arm64 -t mksiptv-server .
#
# Run:
#   docker run -p 4848:4848 -v $(pwd)/config:/opt/mksiptv-server/config mksiptv-server

FROM swift:6.0-jammy AS builder

# Install build dependencies
RUN apt-get update && apt-get install -y \
    libssl-dev \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /build

# Copy source files
COPY . .

# Build release binary
RUN swift build --configuration release --enable-test-discovery

# Runtime stage
FROM ubuntu:22.04

# Install runtime dependencies
RUN apt-get update && apt-get install -y \
    ca-certificates \
    libssl3 \
    && rm -rf /var/lib/apt/lists/*

# Create non-root user
RUN useradd -m -u 1000 -s /bin/bash mksiptv

# Create directories
RUN mkdir -p /opt/mksiptv-server/{config,logs,downloads} && \
    chown -R mksiptv:mksiptv /opt/mksiptv-server

# Copy binary from builder
COPY --from=builder /build/.build/release/mksiptv-server /opt/mksiptv-server/
RUN chmod +x /opt/mksiptv-server/mksiptv-server

# Switch to non-root user
USER mksiptv
WORKDIR /opt/mksiptv-server

# Expose port
EXPOSE 4848

# Health check
HEALTHCHECK --interval=30s --timeout=10s --start-period=5s --retries=3 \
    CMD curl -f http://localhost:4848/health || exit 1

# Set environment variables (can be overridden at runtime)
ENV PORT=4848
ENV HOST=0.0.0.0
ENV LOG_LEVEL=info
ENV CONFIG_PATH=/opt/mksiptv-server/config
ENV DOWNLOAD_PATH=/opt/mksiptv-server/downloads

# Run the server
CMD ["./mksiptv-server"]
