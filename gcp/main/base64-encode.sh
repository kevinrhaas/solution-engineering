#!/bin/bash

# Check if file path parameter is provided
if [ -z "$1" ]; then
    echo "Error: Please provide a file path as parameter"
    echo "Usage: $0 <file-path>"
    exit 1
fi

# Strip any surrounding quotes from the parameter
FILE_PATH="${1%\'}"
FILE_PATH="${FILE_PATH#\'}"
FILE_PATH="${FILE_PATH%\"}"
FILE_PATH="${FILE_PATH#\"}"

# Check if file exists
if [ ! -f "$FILE_PATH" ]; then
    echo "Error: File '$FILE_PATH' not found"
    exit 1
fi

# Encode the file to base64 and remove newlines
base64 -i "$FILE_PATH" | tr -d '\n'