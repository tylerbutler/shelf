# Gleam Project Tasks

# === ALIASES ===
alias b := build
alias t := test
alias f := format
alias c := check
alias d := docs
alias cl := change

default:
    @just --list

# === DEPENDENCIES ===

# Download project dependencies
deps:
    gleam deps download

# === BUILD ===

# Build project (Erlang target)
build:
    rm -f priv/shelf.cdx.json
    gleam build
    just sbom

# Build with warnings as errors
build-strict:
    rm -f priv/shelf.cdx.json
    gleam build --warnings-as-errors
    just sbom

# Generate a reproducible CycloneDX SBOM for the locked Shelf dependencies
sbom:
    rm -f priv/shelf.cdx.json
    gleam deps download
    mkdir -p priv
    SOURCE_DATE_EPOCH=0 licence_audit sbom --reproducible --output=priv/shelf.cdx.json

# === TESTING ===

# Run all tests
test:
    gleam test

# Test the website deploy filter without network access
test-site-ignore:
    bash website/netlify-ignore.test.sh

# Check SBOM reproducibility, locked dependency coverage, and Hex package bytes
test-sbom: sbom
    SOURCE_DATE_EPOCH=0 licence_audit sbom --reproducible --output=build/shelf-check.cdx.json
    cmp priv/shelf.cdx.json build/shelf-check.cdx.json
    rm build/shelf-check.cdx.json
    gleam export hex-tarball
    python3 test/sbom_test.py

# === CODE QUALITY ===

# Format source code
format:
    gleam format src test examples/src

# Check formatting without changes
format-check:
    gleam format --check src test examples/src

# Type check without building
check:
    gleam check

# === DOCUMENTATION ===

# Build documentation
docs:
    gleam docs build

# === CHANGELOG ===

# Create a changelog entry: just change Fixed "Describe the user-facing change"
[positional-arguments]
change kind body:
    trellis changelog new --package shelf --kind "$1" --body "$2"

# Preview unreleased changelog
changelog-preview:
    trellis version plan

# Apply the version bump and generate CHANGELOG.md
changelog:
    trellis version apply

# === MAINTENANCE ===

# Remove build artifacts
clean:
    rm -f priv/shelf.cdx.json
    rm -rf build

# === EXAMPLES ===

# Type-check example applications
check-examples:
    cd examples && gleam check

# Build example applications
build-examples:
    cd examples && gleam build

# === CI ===

# Run all CI checks (format, check, test, build)
ci: format-check check test test-site-ignore build-strict test-sbom check-examples

# Alias for PR checks
alias pr := ci

# Run extended checks for main branch
main: ci docs
