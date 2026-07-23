# Codex Pulse Design QA

- Source visual truth: `Design/reference-option-2.png`
- Installed implementation: `/Applications/CodexPulse.app`
- Implementation screenshot: `work/qa/installed-overview-final.png`
- Side-by-side comparison: `work/qa/comparison-option2-final.png`
- Viewport: `1420 × 972`, dark appearance
- State: Overview / live local activity / official rolling quota / live CodexRadar

The reference uses illustrative values. The implementation intentionally keeps the real quota, reset, project, token, and model values, so fidelity is judged on hierarchy, proportions, typography, spacing, visual tokens, and behavior rather than matching the sample numbers.

## Findings

No actionable P0, P1, or P2 issue remains.

- Typography: system San Francisco hierarchy and monospaced numbers match the compact native target.
- Layout: native translucent source-list sidebar, unified toolbar, one dominant chart, and one bottom status strip match the selected composition.
- Visual language: graphite surfaces, restrained separators, one blue data accent, and a single green live indicator avoid the previous card-wall treatment.
- Chart: official used percentage anchors the observed curve; local activity supplies its shape; forecast, ideal pace, reset marker, direct labels, and 0–100% axis remain visually distinct and unclipped.
- Projects: native table, adaptive inspector, search, and subset-correct Token composition were checked with live data.
- Time: one primary Token chart uses hourly or daily buckets; duration is not mixed onto the Token axis.
- Model intelligence: native table uses `https://api.codexradar.com/api/v1/table`, re-sorts for live/recent/long-term IQ, and renders missing IQ as `—`.
- Settings and menu bar: all controls were opened on the installed build; missing quota renders as `—`, and the user threshold drives the warning state.
- Accessibility: sidebar destinations, refresh, chart summary, project table, and inspector expose usable accessibility labels.

## Comparison History

1. Pass 1 — blocked.
   - `[P1]` The legacy implementation used a manual fixed sidebar and a dense card wall rather than the selected native split-view hierarchy.
   - Fix: replace the shell with `NavigationSplitView`, remove branding/footer clutter from the sidebar, and move controls into the unified toolbar.
2. Pass 2 — blocked.
   - `[P1]` The quota chart initially grouped all lines as one series; `[P2]` plot padding detached marks from axis positions.
   - Fix: give actual, forecast, and ideal marks independent series; use whole-chart trailing space and explicit internal x-axis ticks.
3. Pass 3 — blocked.
   - `[P2]` Catmull-Rom interpolation dipped below 0%; project Token composition double-counted cached input and reasoning output.
   - Fix: use monotone interpolation and split Token subsets into uncached input, cached input, visible output, and reasoning.
4. Final pass — passed.
   - Installed `/Applications` build was opened at the target viewport.
   - Overview, Projects, Time, Model Intelligence, General Settings, About, menu-bar state, and the official quota loading/result states were inspected.

## Verification

- [x] `swift test` — 17 tests, 0 failures, 2 opt-in visual tests skipped.
- [x] Ad-hoc bundle signature passes `codesign --verify --deep --strict`.
- [x] Installed executable path is `/Applications/CodexPulse.app/Contents/MacOS/CodexPulse`.
- [x] Installed build exposes official quota status, remaining value, and reset time.
- [x] README screenshots were recaptured from the installed app.

## Open Questions

None.

final result: passed
