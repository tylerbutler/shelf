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
    gleam build

# Build with warnings as errors
build-strict:
    gleam build --warnings-as-errors

# === TESTING ===

# Run all tests
test:
    gleam test

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
ci: format-check check test build-strict check-examples

# Alias for PR checks
alias pr := ci

# Run extended checks for main branch
main: ci docs
