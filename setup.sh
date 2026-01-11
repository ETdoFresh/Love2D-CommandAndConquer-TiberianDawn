#!/bin/bash
# Setup script for LoveCommandAndConquer2D
# Clones the CnC Remastered Collection source code if not already present

REPO_URL="https://github.com/electronicarts/CnC_Remastered_Collection"
TARGET_DIR="temp/CnC_Remastered_Collection"

if [ -d "$TARGET_DIR" ]; then
    echo "Source code already exists at $TARGET_DIR"
else
    echo "Cloning CnC Remastered Collection..."

    # Create temp directory if it doesn't exist
    mkdir -p temp

    if git clone "$REPO_URL" "$TARGET_DIR"; then
        echo "Successfully cloned to $TARGET_DIR"
    else
        echo "Failed to clone repository"
        exit 1
    fi
fi
