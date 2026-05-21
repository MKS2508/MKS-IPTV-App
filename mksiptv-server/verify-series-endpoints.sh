#!/bin/bash

echo "=== Series Endpoints Verification ==="
echo ""

# Kill any existing server
pkill -9 -f mksiptv-server 2>/dev/null || true
sleep 1

# Start server
echo "Starting server..."
swift run mksiptv-server > /tmp/mksiptv-test.log 2>&1 &
SERVER_PID=$!
echo "Server PID: $SERVER_PID"

# Wait for startup
sleep 4

# Check if server is running
if ! ps -p $SERVER_PID > /dev/null; then
    echo "ERROR: Server failed to start!"
    cat /tmp/mksiptv-test.log
    exit 1
fi

echo "Server started successfully"
echo ""

# Test endpoints
echo "=== Test 1: GET / ==="
curl -s http://localhost:4848/ | jq '.endpoints'
echo ""

echo "=== Test 2: GET /series (expecting error - no active profile) ==="
curl -s http://localhost:4848/series
echo -e "\n"

echo "=== Test 3: GET /series/categories (expecting error - no active profile) ==="
curl -s http://localhost:4848/series/categories
echo -e "\n"

echo "=== Test 4: GET /series/123 (expecting error - no active profile) ==="
curl -s http://localhost:4848/series/123
echo -e "\n"

echo "=== Test 5: GET /series/123/seasons/1 (expecting error - no active profile) ==="
curl -s http://localhost:4848/series/123/seasons/1
echo -e "\n"

echo "=== Test 6: GET /series/123/stream-url?season=1&episode=1 (expecting error - no active profile) ==="
curl -s "http://localhost:4848/series/123/stream-url?season=1&episode=1"
echo -e "\n"

# Cleanup
echo "Killing server..."
kill $SERVER_PID 2>/dev/null || pkill -9 -f mksiptv-server

echo ""
echo "=== Verification Complete ==="
echo ""
echo "Server log excerpt:"
tail -10 /tmp/mksiptv-test.log
