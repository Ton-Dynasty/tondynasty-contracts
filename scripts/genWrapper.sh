#!/bin/bash

# List all directories under 'build' and ask the user to choose one
echo "Available directories under 'build':"
select DIR_NAME in $(find build -maxdepth 1 -mindepth 1 -type d -exec basename {} \;); do
    if [[ -n "$DIR_NAME" ]]; then
        echo "You selected: $DIR_NAME"
        break
    else
        echo "Invalid selection"
    fi
done

# Define the path to the source and destination directories
SRC_DIR="build/$DIR_NAME"
DEST_DIR="wrappers"

# Ensure that the destination directory exists
mkdir -p "$DEST_DIR"

# Loop through each `tact_xxx.ts` file in the source directory
find "$SRC_DIR" -type f -name 'tact_*.ts' | while read -r FILEPATH; do
    # Extract the filename without the path and extension
    FILENAME=$(basename -- "$FILEPATH")
    BASENAME="${FILENAME%.*}"
    
    # Define the new file path
    NEW_FILE="$DEST_DIR/${DIR_NAME}_${BASENAME#tact_}.ts"
    
    # Write the export statement to the new file
    echo "export * from '../$SRC_DIR/${BASENAME}';" > "$NEW_FILE"
done
