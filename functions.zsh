# Dynamically loading all functions in the "functions" folder
for file in "$ZSH_ENV_DIR/functions"/*; do
    if [ -f "$file" ]; then
        source "$file"
    fi
done
