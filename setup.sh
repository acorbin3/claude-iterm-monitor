#!/bin/bash
set -e

echo "=== Claude Monitor Setup ==="
echo ""

# Check for python3
PYTHON=""
for p in /Library/Frameworks/Python.framework/Versions/3.*/bin/python3 /opt/homebrew/bin/python3 /usr/local/bin/python3 /usr/bin/python3; do
    if [ -x "$p" ]; then
        PYTHON="$p"
        break
    fi
done

if [ -z "$PYTHON" ]; then
    echo "ERROR: python3 not found. Please install Python 3 first."
    exit 1
fi

echo "Using Python: $PYTHON"

# Install iterm2 Python package
echo ""
echo "Installing iterm2 Python package..."
"$PYTHON" -m pip install iterm2 --quiet 2>/dev/null || "$PYTHON" -m pip install iterm2 --quiet --break-system-packages
echo "Done."

# Enable iTerm2 Python API
echo ""
echo "Enabling iTerm2 Python API..."
defaults write com.googlecode.iterm2 EnableAPIServer -bool true
echo "Done."

echo ""
echo "=== Setup complete ==="
echo ""
echo "If iTerm2 is currently running, restart it for the Python API to take effect."
echo ""
echo "Build and run with:"
echo "  swift build && swift run"
