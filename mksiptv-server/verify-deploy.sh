#!/bin/bash
# verify-deploy.sh - Verify deployment prerequisites and configuration

echo "🔍 Checking deployment prerequisites..."

# Check Swift version
echo ""
echo "📦 Swift version:"
if command -v swift &> /dev/null; then
    swift --version
else
    echo "❌ Swift not found. Install from https://www.swift.org/download/"
    exit 1
fi

# Check if build directory exists
echo ""
echo "🏗️  Build directory:"
if [ -d ".build/release" ]; then
    echo "✅ .build/release exists"
    if [ -f ".build/release/mksiptv-server" ]; then
        echo "✅ Binary exists: .build/release/mksiptv-server"
        ls -lh .build/release/mksiptv-server
    else
        echo "⚠️  Binary not found. Run 'swift build --configuration release' first."
    fi
else
    echo "⚠️  Build directory not found. Run 'swift build --configuration release' first."
fi

# Check deploy.sh
echo ""
echo "🚀 Deploy script:"
if [ -f "deploy.sh" ]; then
    if [ -x "deploy.sh" ]; then
        echo "✅ deploy.sh exists and is executable"
    else
        echo "⚠️  deploy.sh exists but is not executable. Run: chmod +x deploy.sh"
    fi
else
    echo "❌ deploy.sh not found"
fi

# Check systemd service file
echo ""
echo "🔧 Systemd service file:"
if [ -f "mksiptv-server.service" ]; then
    echo "✅ mksiptv-server.service exists"
    echo "📋 Service config:"
    grep -E "^(User|ExecStart|Environment)" mksiptv-server.service | head -10
else
    echo "❌ mksiptv-server.service not found"
fi

# Check SSH connectivity (optional)
echo ""
echo "🌐 SSH connectivity to VPS:"
if command -v ssh &> /dev/null; then
    if ssh -o ConnectTimeout=5 root@hs.mks2508.systems "echo '✅ SSH connection successful'" 2> /dev/null; then
        echo "✅ SSH connection to VPS Helsinki successful"
    else
        echo "⚠️  Cannot connect to VPS. Ensure SSH keys are configured."
    fi
else
    echo "⚠️  SSH not found. Install OpenSSH client."
fi

# Check Docker (optional)
echo ""
echo "🐳 Docker (optional):"
if command -v docker &> /dev/null; then
    echo "✅ Docker is available"
    docker --version | head -1
else
    echo "⚠️  Docker not found. Optional for containerized deployment."
fi

# Environment variables check
echo ""
echo "🔑 Environment variables:"
env_vars=(
    "PORT"
    "CONFIG_PATH"
    "DOWNLOAD_PATH"
    "OIDC_ISSUER"
    "OIDC_CLIENT_ID"
)

for var in "${env_vars[@]}"; do
    if [ -n "${!var:-}" ]; then
        echo "✅ $var is set: ${!var}"
    else
        echo "⚠️  $var is not set (will use default in systemd service)"
    fi
done

echo ""
echo "✅ Verification complete!"
echo ""
echo "Next steps:"
echo "  1. Run './deploy.sh --dry-run' to preview deployment"
echo "  2. Run './deploy.sh' to deploy to VPS"
echo "  3. Check status: 'ssh root@hs.mks2508.systems systemctl status mksiptv-server'"
