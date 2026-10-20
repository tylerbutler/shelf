#!/usr/bin/env bash
set -euo pipefail

script_directory="$(cd "$(dirname "$0")" && pwd)"
hook="${1:-$script_directory/netlify-ignore.sh}"
fixture="$(mktemp -d)"
trap 'rm -rf -- "$fixture"' EXIT

git init --quiet --bare "$fixture/origin.git"
git init --quiet --initial-branch=main "$fixture/repo"
cd "$fixture/repo"
git config user.name "Netlify hook test"
git config user.email "test@example.invalid"
git config commit.gpgsign false
git config core.hooksPath /dev/null
git remote add origin "$fixture/origin.git"
mkdir website
cp "$hook" website/netlify-ignore.sh
printf 'version = "1.0.0"\n' > gleam.toml
printf 'site\n' > website/index.md
git add .
git commit --quiet -m "test: seed website inputs"
git push --quiet origin main
base="$(git rev-parse HEAD)"

printf 'library only\n' > README.md
git add README.md
git commit --quiet -m "test: change unrelated file"
unrelated="$(git rev-parse HEAD)"

printf 'version = "1.1.0"\n' > gleam.toml
git add gleam.toml
git commit --quiet -m "test: change release version"
release="$(git rev-parse HEAD)"

printf 'updated site\n' > website/index.md
git add website/index.md
git commit --quiet -m "test: change website"
site="$(git rev-parse HEAD)"

git switch --quiet --detach "$base"
printf 'website-only change\n' > website/index.md
git add website/index.md
git commit --quiet -m "test: change only website inputs"
site_only="$(git rev-parse HEAD)"

assert_decision() {
  local label="$1" expected="$2" context="$3" cached="$4" head="$5"
  local output actual
  if output="$(
    cd website
    CONTEXT="$context" CACHED_COMMIT_REF="$cached" COMMIT_REF="$head" \
      NETLIFY_IGNORE_BASE_BRANCH=main bash netlify-ignore.sh 2>&1
  )"; then
    actual=0
  else
    actual=$?
  fi
  if [ "$actual" -ne "$expected" ]; then
    printf 'FAIL: %s (expected %s, got %s)\n%s\n' \
      "$label" "$expected" "$actual" "$output" >&2
    exit 1
  fi
  printf 'PASS: %s\n' "$label"
}

assert_decision "production ignores unrelated changes" 0 production "$base" "$unrelated"
assert_decision "preview ignores unrelated changes" 0 deploy-preview "$base" "$unrelated"
assert_decision "production builds a release-only change" 1 production "$unrelated" "$release"
assert_decision "preview builds a release-only change" 1 deploy-preview "$unrelated" "$release"
assert_decision "production builds website changes" 1 production "$release" "$site"
assert_decision "preview builds website-only changes" 1 deploy-preview "$base" "$site_only"
assert_decision "production skips unchanged inputs" 0 production "$site" "$site"
assert_decision "first production build runs" 1 production "" "$site"
assert_decision "missing cached revision builds" 1 production missing-revision "$site"
assert_decision "unknown preview history builds" 1 deploy-preview "$base" missing-revision
