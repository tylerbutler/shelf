---
target: splash page (index.mdx)
total_score: 29
p0_count: 1
p1_count: 1
timestamp: 2026-07-20T06-29-33Z
slug: website-src-content-docs-index-mdx
---
Method: dual-agent (A: critique-design-review · B: critique-detector)

# Critique: shelf splash page (website/src/content/docs/index.mdx)

## Design Health Score — 29/40 (Good)

| # | Heuristic | Score | Key Issue |
|---|-----------|-------|-----------|
| 1 | Visibility of System Status | 2 | Limited surface; theme toggle, search, "Last updated" present |
| 2 | Match System / Real World | 4 | Exact BEAM idiom (ETS/DETS/WriteBack); card-catalog logo |
| 3 | User Control and Freedom | 3 | Theme toggle, search, low-commitment secondary CTA |
| 4 | Consistency and Standards | 2 | Amber Starlight-default aside broke the berry system (since removed) |
| 5 | Error Prevention | 3 | Code sample correct and labelled |
| 6 | Recognition Rather Than Recall | 3 | Mobile code scrolls with no affordance cue |
| 7 | Flexibility and Efficiency | 3 | Ctrl+K search, Auto theme, dual entry points |
| 8 | Aesthetic and Minimalist Design | 3 | Docked for hero dead space + loud aside |
| 9 | Error Recovery | 2 | Tinylytics analytics 404s silently |
| 10 | Help and Documentation | 4 | Whole site is docs; clear CTAs, search, sidebar |
| **Total** | | **29/40** | **Good** |

## Anti-Patterns Verdict

Not AI slop. No gradient text (the old rule was dead code, now deleted), no card grids, no eyebrows, no hero metrics, no numbered scaffolding, no overflow at 375px. The berry/ink monochrome is not guessable from "BEAM library docs."

Deterministic scan: CLI scan of index.mdx clean (0 findings). In-page detector found 2: `side-tab` (border-left: 4px on the Starlight caution aside — the same element the design review flagged as P0; resolved by removing the stale Pre-1.0 notice) and `layout-transition` (transition: width,height on the framework body element — framework-origin, accepted).

## Priority Issues

- [P0 — RESOLVED] Stale amber Pre-1.0 warning: broke the berry system, front-loaded alarm at the adoption moment, and carried a banned 4px side-stripe. shelf shipped 1.0.1; component and all four usages deleted this session.
- [P1] Desktop hero has ~130px dead space and a top-weighted text column against a centered illustration; mobile composes better. Fix: vertically center text against image or tighten hero height.
- [P2] "Built in" is a 7-item flat group with an orphaned 7th cell (chunking failure, >4 per group). Fix: trim/merge to 6 or split into two labelled clusters.
- [P2] Tinylytics embed 404s on every page — dead analytics plus console error. Fix: verify embed ID.
- [P3] Mobile code block scrolls horizontally with no visible cue or copy button. Fix: edge fade or ensure copy button at mobile width.

## Persona Red Flags

- Jordan (first-timer): previously hit "not production-ready" before learning what shelf is — resolved by removal.
- Casey (mobile): CTA thumb-reachable; code sample clips right with no cue; 404 wastes a request.
- Riley (stress tester): overflow/contrast/zoom robust; orphan 7th cell and hero dead space look unfinished.
- Priya (BEAM evaluator): gets the pattern immediately from real code — trust win. But the page never makes the "why shelf over bravo / raw DETS / SQLite" case she came for.

## Strengths

1. Palette commitment with real contrast discipline (feature text 9.93:1 dark theme); the No-Gray rule is executed, not just written.
2. "Show the pattern, not the pitch" — real, correct Gleam right after the hero is the most persuasive element on the page.
3. Restrained feature list (bare dl, no chrome) dodges the SaaS card-grid trap.

## Minor Observations

- Astro dev toolbar overlaps content in dev screenshots only; won't ship.
- Dark-theme primary button matches DESIGN.md spec exactly (Accent Blush on Blackberry).
- Mobile's centered hero composes better than desktop's left-aligned one.

## Questions to Consider

1. Now that the warning is gone, what earns its place as the first thing below the hero?
2. Where's the comparison Priya came for? One honest trade-off line vs. raw DETS/bravo may do more for adoption than a 7th feature.
3. Should desktop borrow mobile's centered hero — or put the code sample inside the hero so the first thing is working code?
