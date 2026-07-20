---
name: shelf
description: Persistent ETS tables backed by DETS for Gleam.
colors:
  boysenberry: "#ab3772"
  mulberry-ink: "#8f195a"
  blackberry-night: "#340014"
  deep-currant: "#6b0031"
  berry-stain: "#a2004e"
  raspberry-glow: "#ff729e"
  petal-pink: "#f8aabe"
  accent-blush: "#e6bbcb"
  rose-paper: "#ffe7ec"
  blush-white: "#fff3f5"
  pure-white: "#ffffff"
typography:
  display:
    fontFamily: "Spline Sans Variable, Spline Sans, sans-serif"
    fontSize: "2.5rem"
    fontWeight: 650
    lineHeight: 1.2
  heading:
    fontFamily: "Spline Sans Variable, Spline Sans, sans-serif"
    fontSize: "1.5rem"
    fontWeight: 650
    lineHeight: 1.25
  body:
    fontFamily: "Spline Sans Variable, Spline Sans, sans-serif"
    fontSize: "1rem"
    fontWeight: 400
    lineHeight: 1.65
  code:
    fontFamily: "Spline Sans Mono Variable, Spline Sans Mono, ui-monospace, monospace"
    fontSize: "0.8125rem"
    fontWeight: 400
    lineHeight: 1.65
components:
  button-primary:
    backgroundColor: "{colors.mulberry-ink}"
    textColor: "{colors.pure-white}"
    rounded: "999rem"
    padding: "0.75rem 1.25rem"
  button-secondary:
    textColor: "{colors.mulberry-ink}"
    rounded: "999rem"
    padding: "0.75rem 1.25rem"
---

# Design System: shelf

## 1. Overview

**Creative North Star: "The Card Catalog"**

shelf's documentation site is a great library's index: warm wood-and-ink materiality on the surface, instant and exact retrieval underneath. That is the product itself — ETS-speed lookups with disk permanence — expressed visually. The berry-and-ink palette carries the warmth; the type system and Starlight's information architecture carry the precision. Nothing on the page is decorative that doesn't help a reader find, read, or trust.

The system explicitly rejects the generic SaaS landing (gradient heroes, hero metrics, interchangeable feature grids), the sterile unthemed Starlight default, and anything that reads as a toy project. It is a themed, maintained, personality-carrying documentation site for working BEAM developers.

**Key Characteristics:**
- Monochromatic berry palette — there are no true grays anywhere; every neutral carries the brand hue
- One type superfamily (Spline Sans + Spline Sans Mono) across UI, prose, and code
- Flat, tonally-layered surfaces; depth from the berry ramp, not shadows
- Restrained components that disappear into the reading

## 2. Colors: The Berry & Ink Palette

A single hue family, stretched from near-black blackberry to blush white — commitment to one color, differentiated entirely by lightness.

### Primary
- **Boysenberry** (#ab3772): The accent in dark theme — links, current sidebar item, interactive highlights against Blackberry Night.
- **Mulberry Ink** (#8f195a): The accent in light theme — the same voice, darkened to hold 4.5:1 against white paper. Primary buttons and links in light mode.

### Neutral
The "grays" are a berry-tinted lightness ramp; the two themes read it from opposite ends.
- **Blackberry Night** (#340014): The deepest value — page ground in dark theme, primary ink in light theme.
- **Deep Currant** (#6b0031) and **Berry Stain** (#a2004e): Mid-ramp values for borders, secondary text, and surface layering.
- **Raspberry Glow** (#ff729e) and **Petal Pink** (#f8aabe): Upper mid-ramp — secondary text in dark theme, decorative tints in light.
- **Accent Blush** (#e6bbcb): High-contrast accent text/fills on dark surfaces.
- **Rose Paper** (#ffe7ec) and **Blush White** (#fff3f5): The palest tints — light-theme surfaces and dark-theme primary text.
- **Pure White** (#ffffff): Light-theme page ground and maximal text on dark.

### Named Rules
**The No-Gray Rule.** There are no neutral grays in this system. Every "gray" is a berry-tinted value from the ramp above. Introducing a true gray (or a blue-tinted slate) is a violation; it instantly reads as unthemed.

**The Two-Ends Rule.** Dark and light themes are the same ramp read from opposite ends, not two palettes. A new color must be placed on the ramp and verified at ≥4.5:1 for body text in both themes before use.

## 3. Typography

**Display Font:** Spline Sans Variable (with sans-serif fallback)
**Body Font:** Spline Sans Variable (same family)
**Code Font:** Spline Sans Mono Variable (with ui-monospace fallback)

**Character:** A true superfamily — the warm, slightly compact grotesque and its matching mono share one skeleton, so headings, prose, and code read as one voice. Precise letterforms with friendly curves: "precise, warm, confident" without geometric coldness.

### Hierarchy
- **Display** (650, ~2.5rem, 1.2): Page titles and the hero wordmark line. Weight 650 — deliberately between semibold and bold — is the signature of confident headings here.
- **Heading** (650, Starlight scale h2–h3, 1.25): Section headings in guides.
- **Body** (400, 1rem, 1.65): All prose. Line-height is raised to 1.65 to give the compact grotesque air in long-form reading.
- **Code** (400, 0.8125rem, 1.65): All code blocks and inline code, always Spline Sans Mono.

### Named Rules
**The One Family Rule.** Spline Sans and Spline Sans Mono are the only typefaces. No third family, no display font for flavor. Hierarchy comes from the variable weight axis (400 body / 650 headings), never from a new face.

**The Designed Code Rule.** Code is first-class content on this site. It never renders in a browser-default mono stack; `--sl-font-mono` must resolve to Spline Sans Mono Variable.

## 4. Elevation

Flat with tonal layering. Depth is conveyed by stepping along the berry ramp — a panel sits "above" the page by being one ramp step lighter (dark theme) or by a hairline border on Rose Paper (light theme). Shadows appear only where Starlight itself uses them (the search modal); nothing else casts one.

### Named Rules
**The Tonal-Depth Rule.** To elevate a surface, move one step along the berry ramp. Never add a box-shadow to create hierarchy on cards, asides, or navigation.

## 5. Components

The component vocabulary is Starlight's, themed — refined and restrained: quiet controls that disappear into the reading, with the berry accent marking actions and current location only.

### Buttons
- **Shape:** Pill (999rem radius, Starlight default).
- **Primary:** Accent-filled — Mulberry Ink on white text in light theme; Accent Blush fill with Blackberry Night text in dark theme.
- **Secondary:** Text-only with accent color; no fill, no border.
- **Hover / Focus:** Starlight defaults; focus rings use the accent.

### Cards / Containers
- **Corner Style:** Gently rounded (0.5rem, Starlight default).
- **Background:** One ramp step off the page ground (see Elevation).
- **Border:** Hairline in the mid-ramp (Deep Currant on dark, Rose Paper on light).
- **Shadow Strategy:** None (The Tonal-Depth Rule).

### Asides / Callouts
- Starlight `<Aside>` components carry all notices (the Pre-1.0 caution is site-wide via `PreReleaseNotice.astro`). Use semantic types (`note`, `caution`, `tip`); never hand-build a callout.

### Code Blocks
- Spline Sans Mono at 0.8125rem on a tinted berry surface with hairline border. Code blocks are the site's most-read component; they must look deliberate in both themes.

### Navigation
- Starlight sidebar; current page marked with accent background tint + accent text. Wordmark image replaces the site title (light/dark variants in `src/assets/`).

## 6. Do's and Don'ts

### Do:
- **Do** place every new color on the berry ramp and verify ≥4.5:1 body contrast in both themes (The Two-Ends Rule).
- **Do** use variable weight (400 → 650) as the only hierarchy axis in type; 650 is the heading weight, exactly.
- **Do** keep code in Spline Sans Mono everywhere — code is first-class content (The Designed Code Rule).
- **Do** elevate surfaces tonally, one ramp step at a time (The Tonal-Depth Rule).

### Don't:
- **Don't** build "generic SaaS landing" grammar — gradient heroes, hero metrics, identical icon-heading-text card grids (PRODUCT.md anti-reference, verbatim).
- **Don't** let any surface regress to "sterile default Starlight" — the unthemed template look is a named anti-reference.
- **Don't** ship anything that reads as a "toy project": placeholder copy, broken polish, sparse half-pages.
- **Don't** use gradient text (`background-clip: text`). The splash hero currently does this; it is scheduled for removal, not imitation.
- **Don't** introduce true grays, blue-tinted slates, a third typeface, or box-shadow hierarchy.
