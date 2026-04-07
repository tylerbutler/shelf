# Split PR #12 into Stacked PRs

> **For agentic workers:** REQUIRED: Use superpowers:subagent-driven-development (if subagents available) or superpowers:executing-plans to implement this plan. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Split the monolithic PR #12 (16 commits, 48 files) into 6 focused, stacked PRs that can be reviewed independently.

**Architecture:** Cherry-pick commits from the existing `tylerbu/type-safe-decoders` branch onto new branches. Each branch targets its dependency branch. Changelog fragments are distributed to the PR that introduces the described change. When cherry-picks conflict, resolve by checking out the file state from the full branch at the appropriate commit.

**Tech Stack:** git (cherry-pick, worktrees), gh CLI

---

## Commit Inventory

| # | SHA | Message | Group |
|---|-----|---------|-------|
| 1 | `8f84a37` | feat: require decoders on open for runtime type safety (#10) | Core |
| 2 | `29f00eb` | docs: clarify bulk transfer tradeoff from decoder validation | Docs |
| 3 | `cd3fd1e` | docs: update website content for decoder-gated API | Docs |
| 4 | `b4bfa21` | refactor: extract shared logic to internal module | Core |
| 5 | `b80aef6` | fix: resolve resource leak, entry order reversal | Bugfix |
| 6 | `1c5dfcb` | fix: FFI bug fixes | Bugfix |
| 7 | `db47a69` | fix: Gleam core fixes — resource leaks, panic safety | Bugfix |
| 8 | `225a086` | docs: fix crashing examples, scaling/concurrency docs | Docs |
| 9 | `88271f4` | perf: WriteThrough O(1) | Perf |
| 10 | `4c8b75e` | chore: opaque Config, delete_object doc fix | Core |
| 11 | `aba3b0a` | test: bag/duplicate_bag coverage, error paths, helpers | Test |
| 12 | `6254e88` | fix: address fleet review critical issues | Security |
| 13 | `653ee49` | chore: add changelog fragments | (distribute) |
| 14 | `6a3c713` | chore: Breaking kind in changie, recategorize | (distribute) |
| 15 | `19d244b` | fix: resolve warnings and update examples for base_directory | Security |
| 16 | `3148b87` | fix: path traversal bypass and remove review artifacts | Security |

## PR Chain

```
main
 └─ PR1: feat/type-safe-decoders (Core) ─── commits 1, 4, 10
     ├─ PR2: fix/shelf-bug-fixes (Bugfix) ─── commits 5, 6, 7 + Fixed-213157 fragment
     │   └─ PR3: perf/write-through-o1 (Perf) ─── commit 9 + Performance fragment
     │       └─ PR4: fix/security-hardening (Security) ─── commits 12, 15, 16 + Security/Breaking/Added/Fixed-213149/Fixed-213206 fragments + .changie.yaml
     │           └─ PR5: test/shelf-coverage (Test) ─── commit 11
     └─ PR6: docs/shelf-decoder-api (Docs) ─── commits 2, 3, 8
```

## Changelog Fragment Distribution

| Fragment | Description | Goes with |
|----------|-------------|-----------|
| Fixed-20260322-213157.yaml | delete_object docs | PR1 (Core) — introduced in commit 10 |
| Fixed-20260322-213149.yaml | atom exhaustion | PR4 (Security) |
| Fixed-20260322-213206.yaml | data loss on save | PR4 (Security) |
| Performance-20260322-213225.yaml | streaming loader | PR4 (Security) — streaming loader is in commit 12 |
| Security-20260322-213215.yaml | path traversal | PR4 (Security) |
| Added-20260322-213246.yaml | InvalidPath variant | PR4 (Security) |
| Breaking-20260322-213733.yaml | named_table removal | PR4 (Security) |
| Breaking-20260322-213808.yaml | base_directory required | PR4 (Security) |
| .changie.yaml (Breaking kind) | Config change | PR4 (Security) |

---

## Task 1: Create core feature branch (PR1)

**Branch:** `feat/type-safe-decoders` from `main`
**Targets:** `main`

- [ ] **Step 1: Create branch from main**

```bash
git branch feat/type-safe-decoders main
git checkout feat/type-safe-decoders
```

- [ ] **Step 2: Cherry-pick commit 1 (base feature)**

```bash
git cherry-pick 8f84a3734024be3f087d358a3c89057f13df98b1
```

- [ ] **Step 3: Cherry-pick commit 4 (refactor to internal module)**

```bash
git cherry-pick b4bfa21dd92e6bd9d48384dbcc777f3196fc5f03
```

Commits 2-3 (docs) only touch README.md and website/, so this should apply cleanly.

- [ ] **Step 4: Cherry-pick commit 10 (opaque Config, delete_object doc fix)**

```bash
git cherry-pick 4c8b75e2727dee3e0be632d3867dd2f8575e284d
```

This may conflict since commits 5-9 modified some of the same files (src/shelf.gleam, test/type_safety_test.gleam). If it conflicts, resolve by examining what commit 10 changed relative to commit 4 and applying those specific changes manually.

- [ ] **Step 5: Add changelog fragment for delete_object doc fix**

Copy `Fixed-20260322-213157.yaml` from the full branch:
```bash
mkdir -p .changes/unreleased
git show tylerbu/type-safe-decoders:.changes/unreleased/Fixed-20260322-213157.yaml > .changes/unreleased/Fixed-20260322-213157.yaml
git add .changes/unreleased/Fixed-20260322-213157.yaml
git commit -m "chore: add changelog fragment for delete_object doc fix"
```

- [ ] **Step 6: Verify tests pass**

```bash
gleam test
```

- [ ] **Step 7: Push and create PR**

```bash
git push -u origin feat/type-safe-decoders
gh pr create --base main --title "feat!: require decoders on open for runtime type safety" --body "..."
```

---

## Task 2: Create bug fixes branch (PR2)

**Branch:** `fix/shelf-bug-fixes` from `feat/type-safe-decoders`
**Targets:** `feat/type-safe-decoders`

- [ ] **Step 1: Create branch**

```bash
git checkout -b fix/shelf-bug-fixes feat/type-safe-decoders
```

- [ ] **Step 2: Cherry-pick commits 5, 6, 7**

```bash
git cherry-pick b80aef69820031ece4cc5d8668f027bfc680e6ac
git cherry-pick 1c5dfcbc16183cbdc371038c97f1a6820c446f07
git cherry-pick db47a6950dc6092f48fc48de3e785cab4d141894
```

These should apply cleanly since they directly follow the refactor (commit 4) in the original history, and commit 10's changes don't overlap heavily.

- [ ] **Step 3: Verify tests pass**

```bash
gleam test
```

- [ ] **Step 4: Push and create PR**

```bash
git push -u origin fix/shelf-bug-fixes
gh pr create --base feat/type-safe-decoders --title "fix: resolve resource leaks, FFI bugs, and panic safety" --body "..."
```

---

## Task 3: Create performance branch (PR3)

**Branch:** `perf/write-through-o1` from `fix/shelf-bug-fixes`
**Targets:** `fix/shelf-bug-fixes`

- [ ] **Step 1: Create branch and cherry-pick**

```bash
git checkout -b perf/write-through-o1 fix/shelf-bug-fixes
git cherry-pick 88271f47c67cd1fb14d10a770b81cade9d86c504
```

- [ ] **Step 2: Add performance changelog fragment**

```bash
mkdir -p .changes/unreleased
git show tylerbu/type-safe-decoders:.changes/unreleased/Performance-20260322-213225.yaml > .changes/unreleased/Performance-20260322-213225.yaml
git add .changes/unreleased/Performance-20260322-213225.yaml
git commit -m "chore: add changelog fragment for streaming loader performance"
```

Wait — the Performance fragment describes "streaming DETS loader" which is actually in the security commit (12), not the perf commit (9). The perf commit (9) is about WriteThrough O(1). This fragment should go with PR4 (Security). Skip adding it here.

- [ ] **Step 3: Verify tests pass**

```bash
gleam test
```

- [ ] **Step 4: Push and create PR**

```bash
git push -u origin perf/write-through-o1
gh pr create --base fix/shelf-bug-fixes --title "perf: WriteThrough O(1) per write via targeted DETS operations" --body "..."
```

---

## Task 4: Create security branch (PR4)

**Branch:** `fix/security-hardening` from `perf/write-through-o1`
**Targets:** `perf/write-through-o1`

- [ ] **Step 1: Create branch and cherry-pick**

```bash
git checkout -b fix/security-hardening perf/write-through-o1
git cherry-pick 6254e8864f33cd4ceb3e3810246e3fc9a08889a9
git cherry-pick 19d244b5a59b179963fffc7796e1746e25b559cb
git cherry-pick 3148b872d0b27f59ce7af4e68c828d62e8f06bf5
```

Commit 12 (6254e88) is the largest commit. It should cherry-pick, but may conflict with commit 10's changes. Resolve conflicts by favoring the security commit's version.

- [ ] **Step 2: Add all security-related changelog fragments**

```bash
mkdir -p .changes/unreleased
for f in Added-20260322-213246.yaml Breaking-20260322-213733.yaml Breaking-20260322-213808.yaml Fixed-20260322-213149.yaml Fixed-20260322-213206.yaml Performance-20260322-213225.yaml Security-20260322-213215.yaml; do
  git show tylerbu/type-safe-decoders:.changes/unreleased/$f > .changes/unreleased/$f
done
# Also get .changie.yaml changes
git show tylerbu/type-safe-decoders:.changie.yaml > .changie.yaml
git add .changes/ .changie.yaml
git commit -m "chore: add changelog fragments for security hardening"
```

- [ ] **Step 3: Verify tests pass**

```bash
gleam test
```

- [ ] **Step 4: Push and create PR**

```bash
git push -u origin fix/security-hardening
gh pr create --base perf/write-through-o1 --title "fix!: security hardening — atom pool, path validation, atomic save" --body "..."
```

---

## Task 5: Create tests branch (PR5)

**Branch:** `test/shelf-coverage` from `fix/security-hardening`
**Targets:** `fix/security-hardening`

- [ ] **Step 1: Create branch and cherry-pick**

```bash
git checkout -b test/shelf-coverage fix/security-hardening
git cherry-pick aba3b0a2ecdbf30202da5d62bbb1c2ced657df75
```

- [ ] **Step 2: Verify tests pass**

```bash
gleam test
```

- [ ] **Step 3: Push and create PR**

```bash
git push -u origin test/shelf-coverage
gh pr create --base fix/security-hardening --title "test: expand bag/duplicate_bag coverage and add error path tests" --body "..."
```

---

## Task 6: Create docs branch (PR6)

**Branch:** `docs/shelf-decoder-api` from `feat/type-safe-decoders`
**Targets:** `feat/type-safe-decoders`

- [ ] **Step 1: Create branch and cherry-pick**

```bash
git checkout -b docs/shelf-decoder-api feat/type-safe-decoders
git cherry-pick 29f00eb1b644f060febe4861be06de43cae2c05b
git cherry-pick cd3fd1e49880381254ea1abb85a60235309b21d1
git cherry-pick 225a0868f11f983b92662aa07144254d44241b85
```

Commit 8 (225a086) may conflict since it was originally written on top of commits 5-7. If it conflicts, resolve by applying only the docs changes (CLAUDE.md, README.md, examples/tag_index.gleam).

- [ ] **Step 2: Verify build succeeds**

```bash
gleam build
```

- [ ] **Step 3: Push and create PR**

```bash
git push -u origin docs/shelf-decoder-api
gh pr create --base feat/type-safe-decoders --title "docs: update website, README, and examples for decoder-gated API" --body "..."
```

---

## Task 7: Close original PR and clean up

- [ ] **Step 1: Close PR #12 with note**

```bash
gh pr close 12 --comment "Split into stacked PRs: #XX, #XX, #XX, #XX, #XX, #XX"
```

- [ ] **Step 2: Optionally delete the old branch**

```bash
# Only after confirming all new PRs are created
git push origin --delete tylerbu/type-safe-decoders
```
