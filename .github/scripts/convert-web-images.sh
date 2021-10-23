#!/usr/bin/env bash
set -euo pipefail

IMG_DIR="$1"
IMG_FILETYPE="$2"
REPO_DIR="$( dirname "${BASH_SOURCE[0]}" )/../.."

for img in $REPO_DIR/$IMG_DIR/*.$IMG_FILETYPE; do cwebp -metadata all -q 60 "${img}" -o "$REPO_DIR/$IMG_DIR/$(basename "${img}" .$IMG_FILETYPE).webp"; done
