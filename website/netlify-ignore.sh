#!/usr/bin/env bash
# Netlify build-ignore hook. Runs from the site's base directory (website/).
#
#   exit 0  -> skip the build
#   exit 1+ -> run the build
#
# Paths are relative to website/: `.` covers the site, while ../gleam.toml
# supplies the release version used by src/version.mjs.
#
# Deploy previews ask "does this PR touch any website input?" — comparing
# against the merge base, not against the last build, so a PR that never touches
# these inputs never builds a preview, no matter how many times it is pushed.
#
# Production and branch deploys build only if a website input changed since
# the commit Netlify last built.
#
# Whenever the answer cannot be determined, build. A spurious build is cheap; a
# silently skipped one looks like a broken deploy.
set -u

BASE_BRANCH="${NETLIFY_IGNORE_BASE_BRANCH:-main}"

say() { echo "netlify-ignore: $*"; }

if [ "${CONTEXT:-}" = "deploy-preview" ]; then
  # Netlify shallow-clones, so the base branch usually is not present yet.
  git fetch --no-tags --quiet --depth=100 origin "$BASE_BRANCH" 2>/dev/null || true

  base="$(git merge-base FETCH_HEAD "$COMMIT_REF" 2>/dev/null \
    || git merge-base "origin/$BASE_BRANCH" "$COMMIT_REF" 2>/dev/null \
    || true)"

  if [ -z "$base" ]; then
    say "could not resolve merge base with $BASE_BRANCH -> building"
    exit 1
  fi

  git diff --quiet "$base" "$COMMIT_REF" -- . ../gleam.toml 2>/dev/null
  case $? in
    0) say "PR touches no website inputs (base $base) -> skipping"; exit 0 ;;
    1) say "PR touches website inputs (base $base) -> building"; exit 1 ;;
    *) say "could not diff $base..$COMMIT_REF -> building"; exit 1 ;;
  esac
fi

if [ -z "${CACHED_COMMIT_REF:-}" ]; then
  say "no cached commit for $CONTEXT -> building"
  exit 1
fi

git diff --quiet "$CACHED_COMMIT_REF" "$COMMIT_REF" -- . ../gleam.toml 2>/dev/null
case $? in
  0) say "no website input changes since $CACHED_COMMIT_REF -> skipping"; exit 0 ;;
  1) say "website inputs changed since $CACHED_COMMIT_REF -> building"; exit 1 ;;
  *) say "cached commit $CACHED_COMMIT_REF not in this clone -> building"; exit 1 ;;
esac
