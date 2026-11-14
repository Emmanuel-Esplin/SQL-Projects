# Design System Master File

> **LOGIC:** When building a specific page, first check `design-system/pages/[page-name].md`.
> If that file exists, its rules **override** this Master file.
> If not, strictly follow the rules below.

---

**Project:** Diamond Tracker
**Generated:** 2026-10-23 16:33:34 (UI UX Pro Max). **Revised:** 2026-11-14 to match the built app: dark theme, contrast fixes, and Flat rules applied throughout. The generated shadow and hover-lift specs contradicted Flat style and were removed.
**Category:** Inventory & Stock Management (internal tool, used at a desk and on a phone by the safe)
**Design Dials:** Density 7/10 (Standard)

Tokens live in `diamond_app/static/css/app.css` under `:root`. Components use the semantic tokens only, never raw hex, so the dark theme only has to redefine them.

---

## Global Rules

### Color Palette

| Role | Light | Dark | CSS Variable |
| --- | --- | --- | --- |
| Primary (chrome) | `#334155` | `#CBD5E1` | `--color-primary` |
| Accent/CTA | `#059669` | `#10B981` | `--color-accent` |
| On Accent/CTA | `#000000` | `#000000` | `--color-on-accent` |
| Accent hover | `#047857` + white text | `#34D399` + black text | `--color-accent-hover` |
| Background | `#F8FAFC` | `#0F172A` | `--color-background` |
| Foreground | `#0F172A` | `#E2E8F0` | `--color-foreground` |
| Card | `#FFFFFF` | `#1E293B` | `--color-card` |
| Muted | `#F2F3F4` | `#273548` | `--color-muted` |
| Muted Foreground | `#475569` | `#A3B1C6` | `--color-muted-foreground` |
| Border (decorative) | `#E6E8EA` | `#334155` | `--color-border` |
| Input border | `#7B8BA3` | `#64748B` | `--color-input-border` |
| Link | `#334155` | `#CBD5E1` | `--color-link` |
| Destructive | `#DC2626` | `#DC2626` | `--color-destructive` |
| Error text | `#B91C1C` | `#FCA5A5` | `--color-destructive-text` |
| Focus ring | `#334155` | `#94A3B8` | `--color-ring` |
| Sidebar | `#334155` | `#020617` | `--sidebar-bg` |

Status tints come in `bg` / `fg` / `border` triples: `--ok-*` (in stock), `--warn-*` (in polishing), `--danger-*` (in repair, overdue), `--info-*` (being sold), `--done-*` (sold), `--grade-*` (polished). Each badge also shows its status as text, so color is never the only signal.

**Contrast (checked):** body text ≥ 11:1, muted text ≥ 5.7:1, CTA 5.6:1 (light) / 8.3:1 (dark), every badge and alert ≥ 8:1 in dark mode. Input borders ≥ 3:1 against the card (WCAG 1.4.11); the original `#94A3B8` was 2.6:1.

**Theme:** follows the operating system (`prefers-color-scheme`). QR codes, printed labels and certificate previews stay black on white in both themes so they scan and print.

**Color Notes:** Industrial slate + stock green

### Typography

- **Heading Font:** Cormorant 600 (self-hosted)
- **Body Font:** Montserrat variable (self-hosted, preloaded)
- **Data Font:** JetBrains Mono for codes, weights and prices, with tabular figures
- **Mood:** luxury, high-end, elegant, refined, but plain-spoken in copy

### Signature element: the inscription

The tracking code is the thing people read aloud, scan and copy by hand. Where a code is the subject of the page (the diamond page, its label), it is set like a girdle inscription with the `inscription` macro: monospaced, spaced 0.08em, `DC-yy-` muted and the six identifying characters bold. Lists keep plain monospaced codes. Do not add other decorative flourishes; this is the one.

### Spacing Variables

*Density: 7/10 — Standard*

| Token | Value | Usage |
| --- | --- | --- |
| `--space-xs` | `4px` / `0.25rem` | Tight gaps |
| `--space-sm` | `8px` / `0.5rem` | Icon gaps, inline spacing |
| `--space-md` | `16px` / `1rem` | Standard padding |
| `--space-lg` | `24px` / `1.5rem` | Section padding |
| `--space-xl` | `32px` / `2rem` | Large gaps |
| `--space-2xl` | `48px` / `3rem` | Section margins |

### Elevation

None. Surfaces are separated by 1px borders and tints, never shadows. The only `box-shadow` uses are focus rings and the current-page marker in the navigation, both of which encode state.

---

## Component Specs

### Buttons

- Primary: accent background, black text, 8px radius, 600 weight, min height 44px. Hover changes color only (no transform).
- Secondary: transparent, 2px link-colored border; hover fills with the link color.
- After a POST form is submitted, its button is disabled with a spinner (`.is-busy`) so a safe movement cannot be recorded twice. Re-enabled when the page is restored by Back.
- One primary action per view.

### Cards

Card background, 1px border, 12px radius, 24px padding. No hover effect unless the whole card is a link (`.tile`), which changes only its border color.

### Inputs

1px input-border, 8px radius, min height 44px, 16px text (no iOS zoom). Focus: ring-colored border plus a 3px soft ring. Invalid: destructive border, inline message linked by `aria-describedby`, and a focused error summary at the top of the form.

### Navigation

Sidebar at ≥ 900px. Below that it becomes a header, and with JavaScript the links fold behind a **Menu** button (`aria-expanded`, Escape closes it). Without JavaScript the links stay visible. The code search bar is sticky; `scroll-padding-top` keeps focused fields clear of it.

### Loading

HTMX regions get `aria-busy` and dim to 60% while refreshing.

---

## Style Guidelines

**Style:** Flat Design

**Keywords:** 2D, minimalist, no shadows, clean lines, typography-focused, icon-supported

**Key Effects:** No gradients or shadows, simple hover (color shift), transitions of 150ms ease, reduced motion respected

### Page Pattern

**Pattern Name:** Data workspace

- Page header: title, one-line purpose, at most one primary action.
- Then the working area: forms beside the live list they change (Safe, Sales), or filters above results (Diamonds).
- Empty states say what is true and what to do ("Every stone is in the safe.").

---

## Anti-Patterns (Do NOT Use)

- ❌ Shadows, gradients, 3D effects, hover lifts
- ❌ Emojis as icons (use the bundled Lucide SVGs)
- ❌ Inline `style=` or inline scripts (the CSP blocks them)
- ❌ Raw hex in components (use tokens)
- ❌ Color as the only signal
- ❌ Invisible focus states
- ❌ Text under 4.5:1, or control borders under 3:1

---

## Pre-Delivery Checklist

- [ ] SVG icons from the bundled Lucide set, decorative ones `aria-hidden`
- [ ] `cursor: pointer` on clickable elements; 44px targets
- [ ] Contrast checked in **both** themes (text 4.5:1, controls 3:1)
- [ ] Focus visible and never hidden under the sticky bar
- [ ] `prefers-reduced-motion` and forced-colors respected
- [ ] Works at 375px, 768px, 1024px and 1440px with no horizontal scroll
- [ ] Works without JavaScript
