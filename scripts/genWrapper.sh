#!/bin/bash

# Check if the source directory is provided
if [ "$#" -ne 1 ]; then
    echo "Usage: $0 <SourceDirectoryName>"
    exit 1
fi

# Define the path to the source and destination directories
SRC_DIR="build/$1"
DEST_DIR="wrappers"

# Ensure that the destination directory exists
mkdir -p "$DEST_DIR"

# Loop through each `tact_xxx.ts` file in the source directory
find "$SRC_DIR" -type f -name 'tact_*.ts' | while read -r FILEPATH; do
    # Extract the filename without the path and extension
    FILENAME=$(basename -- "$FILEPATH")
    BASENAME="${FILENAME%.*}"
    
    # Define the new file path
    NEW_FILE="$DEST_DIR/${BASENAME#tact_}.ts"
    
    # Write the export statement to the new file
    echo "export * from '../$SRC_DIR/${BASENAME}';" > "$NEW_FILE"
done
