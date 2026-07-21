# Codex Pulse Design QA

- Source visual truth: `Design/reference-option-1.png`
- Implementation screenshot: `work/qa/implementation-pass8.png`
- Viewport: `1440 × 1024`, dark appearance
- State: Overview / Today / live local Codex data / live CodexRadar / one official seven-day quota window
- Full-view comparison evidence: `work/qa/comparison-pass8.png`
- Focused comparison evidence:
  - `work/qa/comparison-pass8-top.png`
  - `work/qa/comparison-pass8-bottom.png`

The mock contains illustrative values while the implementation intentionally shows live values. Fidelity was therefore judged on information hierarchy, region proportions, typography, spacing, visual tokens, controls, and content semantics rather than matching the numbers themselves. The rendered capture excludes the outer NSWindow traffic-light chrome; the packaged app was separately verified as an on-screen `Codex Pulse` window.

## Findings

No actionable P0, P1, or P2 mismatch remains.

- Fonts and typography: system San Francisco hierarchy, weights, compact captions, monospaced numeric behavior, wrapping, and truncation are consistent with the native macOS target. The final chart labels no longer clip.
- Spacing and layout rhythm: the fixed sidebar, overview header, chart/quota split, lower project/model split, panel padding, radii, borders, and bottom metadata align with the selected composition. All persistent controls and cards remain visible at the target viewport.
- Colors and visual tokens: near-black backgrounds, graphite panels, muted borders, mint live/actual accents, cyan ranking accents, and subdued secondary text preserve the selected palette and contrast hierarchy.
- Image quality and asset fidelity: the dashboard has no raster product imagery. Interface symbols use SF Symbols rather than handcrafted substitutes. The generated app icon follows the selected graphite-and-mint pulse art direction and is packaged as a multi-resolution ICNS.
- Copy and content: Chinese labels are concise and app-specific; local-only privacy, source freshness, quota reset, real project names, actual model/effort labels, and the CodexRadar attribution are explicit.
- Affordances and states: today/7-day/30-day range controls, refresh, sidebar destinations, settings, CodexRadar link, menu-bar window, stale/error fallbacks, and loading states are implemented. The range changes drive the presentation model; refresh updates all three sources.

## Comparison History

1. Pass 1 — blocked.
   - Earlier finding: `[P0]` `ImageRenderer` produced a forbidden-symbol placeholder instead of the app view.
   - Fix: render through a real `NSHostingView` in an off-screen `NSWindow`.
   - Post-fix evidence: `work/qa/implementation-pass2.png`.
2. Passes 2–3 — blocked.
   - Earlier finding: `[P1]` the native split-view/material sidebar was blank in deterministic rendering and did not reproduce the reference's fixed dark rail.
   - Fix: use a native SwiftUI fixed-width sidebar with `List`, SF Symbols, selection state, and system settings link.
   - Post-fix evidence: `work/qa/implementation-pass4.png`.
3. Passes 4–5 — blocked.
   - Earlier finding: `[P1]` quota and ranking panels overflowed/cropped; `[P2]` actual and forecast points joined as one series; `[P2]` a missing second official quota left an unbalanced region; `[P2]` stale unfinished tasks inflated the running count; `[P2]` settings placement and early-day forecast weakened fidelity and truthfulness.
   - Fix: responsive `GeometryReader` proportions; independent actual/forecast series; a real account summary in place of a fabricated second quota; 10-minute active-event freshness; settings inside navigation; forecasts only after three observed hours.
   - Post-fix evidence: `work/qa/comparison-pass5.png` and `work/qa/implementation-pass6.png`.
4. Pass 7 — blocked.
   - Earlier finding: `[P2]` the final intraday x-axis label clipped at the chart edge.
   - Fix: reserve plot-end padding while retaining the full data endpoint.
   - Post-fix evidence: `work/qa/implementation-pass8.png`, `work/qa/comparison-pass8.png`, and both pass-8 focused comparisons.

## Open Questions

None.

## Implementation Checklist

- [x] Match selected overview composition and dark native visual language.
- [x] Keep project, time, model, settings, menu-bar, and refresh paths functional.
- [x] Use real local, app-server, and CodexRadar data without fabricated quota windows.
- [x] Preserve privacy boundaries and communicate freshness/degraded states.
- [x] Verify at `1440 × 1024`, run full tests, sign the app bundle, and launch it.

## Follow-up Polish

- `[P3]` A notarized Developer ID build would remove the normal local-development distribution warning; this is packaging work and does not affect the current UI or core use.

final result: passed
