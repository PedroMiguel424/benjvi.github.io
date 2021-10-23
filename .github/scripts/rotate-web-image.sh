#!/usr/bin/env bash
set -euo pipefail

IMG_FILE="$1"
ROTATION_DEG="$2"
REPO_DIR="$( dirname "${BASH_SOURCE[0]}" )/../.."

convert $REPO_DIR/$IMG_FILE -rotate "$ROTATION_DEG" $REPO_DIR/$IMG_FILE 
