#!/bin/bash
# Test script for Series endpoints

echo "Starting mksiptv-server..."
swift run mksiptv-server &
SERVER_PID=$!

# Wait for server to start
sleep 3

echo ""
echo "=== Testing Series Endpoints ==="
echo ""

# Test 1: Root endpoint
echo "1. GET /"
curl -s http://localhost:4848/ | jq '.'
echo ""

# Test 2: List series (should return error - no active profile)
echo "2. GET /series (expecting error - no active profile)"
curl -s http://localhost:4848/series | jq '.'
echo ""

# Test 3: List categories (should return error - no active profile)
echo "3. GET /series/categories (expecting error - no active profile)"
curl -s http://localhost:4848/series/categories | jq '.'
echo ""

# Test 4: Series detail (should return error - no active profile)
echo "4. GET /series/123 (expecting error - no active profile)"
curl -s http://localhost:4848/series/123 | jq '.'
echo ""

# Cleanup
echo "Killing server (PID: $SERVER_PID)..."
kill $SERVER_PID 2>/dev/null || true

echo ""
echo "=== Tests Complete ==="
