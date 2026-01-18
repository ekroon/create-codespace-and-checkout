#!/bin/bash
set -e

echo "Running post-create setup..."

# Install build dependencies for Ruby and other languages
echo "Installing build dependencies..."
sudo apt-get update
sudo apt-get install -y --no-install-recommends \
    libffi-dev \
    libyaml-dev \
    libssl-dev \
    libreadline-dev \
    zlib1g-dev \
    autoconf \
    bison \
    build-essential \
    libtool
sudo rm -rf /var/lib/apt/lists/*

# Setup mise
echo "Setting up mise..."
mise trust
mise install

echo "Post-create setup completed!"
