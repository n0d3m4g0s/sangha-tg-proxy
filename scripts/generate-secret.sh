#!/usr/bin/env bash
set -euo pipefail

# Generate a random 32-hex-char secret for mtprotoproxy
openssl rand -hex 16
