#!/usr/bin/env bash
# Netlify build-ignore hook. Runs from the site's base directory (website/).
#
#   exit 0  -> skip the build
#   exit 1+ -> run the build
#
# The pathspec is `.` on purpose: Netlify runs this from the base directory, so
# `-- website/` would resolve to website/website/ and match nothing, which reads
# as "no changes" and cancels every build. That was the previous bug.
#
# Deploy previews ask "does this PR touch the website at all?" — comparing
# against the merge base, not against the last build, so a PR that never touches
# website/ never builds a preview, no matter how many times it is pushed.
#
# Production and branch deploys stay incremental: build only if something under
# this directory changed since the commit Netlify last built.
#
# Whenever the answer cannot be determined, build. A spurious build is cheap; a
# silently skipped one looks like a broken deploy.
set -u

BASE_BRANCH="${NETLIFY_IGNORE_BASE_BRANCH:-main}"
DIR_LABEL="$(basename "$PWD")/"

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

  git diff --quiet "$base" "$COMMIT_REF" -- . 2>/dev/null
  case $? in
    0) say "PR touches no files under $DIR_LABEL (base $base) -> skipping"; exit 0 ;;
    1) say "PR touches $DIR_LABEL (base $base) -> building"; exit 1 ;;
    *) say "could not diff $base..$COMMIT_REF -> building"; exit 1 ;;
  esac
fi

if [ -z "${CACHED_COMMIT_REF:-}" ]; then
  say "no cached commit for $CONTEXT -> building"
  exit 1
fi

git diff --quiet "$CACHED_COMMIT_REF" "$COMMIT_REF" -- . 2>/dev/null
case $? in
  0) say "no changes under $DIR_LABEL since $CACHED_COMMIT_REF -> skipping"; exit 0 ;;
  1) say "changes under $DIR_LABEL since $CACHED_COMMIT_REF -> building"; exit 1 ;;
  *) say "cached commit $CACHED_COMMIT_REF not in this clone -> building"; exit 1 ;;
esac
