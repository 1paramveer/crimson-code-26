#!/bin/bash

# Navigate to project directory
cd "$(dirname "$0")" || exit 1

# Activate virtual environment
source venv/bin/activate

# Start Flask app
python dashboard.py
