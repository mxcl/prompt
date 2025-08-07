# Cask Parser Scripts

This directory contains scripts for downloading and parsing Homebrew cask data.

## Scripts

### `parse-casks.ts`

A comprehensive script for downloading and parsing cask data with multiple output formats.

**Usage:**

```bash
# Output as JSON (default)
./Scripts/parse-casks.ts

# Output as CSV
./Scripts/parse-casks.ts --csv

# Output as table (good for quick preview)
./Scripts/parse-casks.ts --table

# Limit output to first N casks
./Scripts/parse-casks.ts --limit=10 --table
```

**Features:**

- Downloads fresh cask data from Homebrew API
- Uses ETag-based caching to avoid unnecessary downloads
- Extracts: token, name, description, homepage, and brew install command
- Multiple output formats: JSON, CSV, table
- Limit output for testing/preview

### `build-cask-db.ts`

A simpler script that generates a parsed cask database file for use in Swift applications.

**Usage:**

```bash
# Generate parsed-casks.json in Data/ directory
./Scripts/build-cask-db.ts

# Specify custom output file
./Scripts/build-cask-db.ts --output=./my-casks.json
```

**Output:**

Creates a JSON file with an array of objects containing:

- `token`: The cask identifier (e.g., "firefox")
- `name`: Human-readable name (e.g., "Firefox")
- `description`: Brief description of the application
- `homepage`: Official website URL
- `brewInstallCommand`: Complete brew install command

## Data Structure

Each parsed cask contains:

```json
{
  "token": "firefox",
  "name": "Firefox",
  "description": "Web browser",
  "homepage": "https://www.mozilla.org/firefox/",
  "brewInstallCommand": "brew install --cask firefox"
}
```

## Requirements

- [pkgx](https://pkgx.sh/) for running Deno scripts
- Internet connection for downloading cask data

## Caching

The scripts automatically cache downloaded data in `./Data/cask.json` with ETag-based cache invalidation to minimize API calls and improve performance.
