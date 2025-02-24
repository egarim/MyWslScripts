#!/bin/bash

# Exit on error
set -e

echo "Starting Redis installation..."

# Kill any existing Redis processes
echo "Cleaning up existing Redis processes..."
sudo pkill redis-server || true
sleep 2

# Clean installation
echo "Removing existing Redis installation..."
sudo apt-get remove --purge -y redis-server
sudo apt-get autoremove -y
sudo rm -rf /var/lib/redis /etc/redis

# Fresh install
echo "Installing Redis..."
sudo apt-get update
sudo apt-get install -y redis-server

# Ensure proper permissions
echo "Setting up permissions..."
sudo chown -R redis:redis /var/lib/redis
sudo chmod -R 770 /var/lib/redis
sudo chown -R redis:redis /etc/redis
sudo chmod -R 660 /etc/redis/redis.conf
sudo chmod 770 /etc/redis

# Configure Redis
echo "Configuring Redis..."
sudo cp /etc/redis/redis.conf /etc/redis/redis.conf.backup
sudo sed -i 's/bind 127.0.0.1 ::1/bind 127.0.0.1/' /etc/redis/redis.conf
sudo sed -i 's/supervised systemd/supervised no/' /etc/redis/redis.conf
sudo sed -i 's/daemonize yes/daemonize no/' /etc/redis/redis.conf

# Start Redis with proper permissions
echo "Starting Redis..."
sudo -u redis redis-server /etc/redis/redis.conf &
sleep 2

# Test connection
echo "Testing Redis connection..."
if redis-cli ping | grep -q 'PONG'; then
    echo "✓ Redis installed and running successfully!"
    echo "✓ Port: 6379"
    echo "✓ Test with: redis-cli ping"
else
    echo "✗ Redis failed to start"
    echo "Checking logs..."
    sudo cat /var/log/redis/redis-server.log
    exit 1
fi