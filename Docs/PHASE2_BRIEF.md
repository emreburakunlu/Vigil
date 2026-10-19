# Phase 2 brief: screen agents (shared rules)

You are one of six screen agents building Vigil's UI in parallel. Each of you works in your own git worktree and owns one feature folder. These rules apply to all of you.

## Read first
1. `Docs/ARCHITECTURE.md`, all of it, especially §5 (mock data and previews), §7 (units and formatting), §10 (definition of done) and §12 (design system usage).
2. The design HTML for your screens in `Design/` (listed in your prompt). The HTML is the source of truth for layout, copy, hierarchy and spacing. Data in `{{…}}` / `<sc-for>` templates is sample data; read the `<script>` blocks to see the sample values.
3. `Vigil/Core/Services/VigilRepository.swift` and `ScreenModels.swift`: the only API your screens should call for data.
4. The design-system components in `Shared/DesignSystem/` and `Vigil/DesignSystem/`. Use them; don't rebuild rings, cards, segmented controls, chips, zone bars, etc.

## Rules
- **Edit only your own folder(s)**, listed in your prompt. You may add new files there freely: views, `@Observable` screen models, small helpers.
- **Need more data than the repository gives?**
  - First try computing it in your screen model from existing repository calls.
  - If a new repository query is truly needed, put it in an `extension VigilRepository` in a file named `VigilRepository+<Feature>.swift` inside your folder, and list it in your report. The orchestrator will move shared ones into Services later.
  - Don't edit `Vigil/Core/**`, `Shared/**`, `Vigil/App/**` or other features.
- **Design system gaps**: if a component is missing or needs an option, build a private one in your folder (prefixed with your feature, e.g. `SleepHypnogram`) and mention it in your report. Don't edit the design system.
- **Navigation** goes through `AppRouter` routes that already exist (see `Vigil/App/AppRouter.swift` and `RouteDestinationView.swift`). Keep each placeholder view's type name and initializer so routing keeps compiling. If you need a new route, list it in your report and use the closest existing one meanwhile.
- **No hard-coded colors or fonts** in feature code; use tokens. All numbers with units go through `VigilFormatter` (must respect kg/km vs lb/mi). Don't hard-code sample values from the HTML. Everything shown comes from the repository (mock data in the simulator).
- **Both appearances**: check every screen in light and dark mode. Sleep screens use the night palette (`.vNightScreen()`).
- **States**: every screen handles loading (subtle skeleton/redacted placeholder, no spinners blocking the screen), no data / partial data (hide unavailable cards or show "Not available"), and errors.
- **Accessibility**: VoiceOver labels on rings, charts (use `accessibilityChartDescriptor` or summary labels) and icon buttons. Dynamic Type must not break layouts (test at least XL). Respect Reduce Motion (the design-system motion helpers do).
- **Performance**: load data in `.task(id:)`, never in `body`. Don't recompute heavy arrays in `body`; precompute them in the screen model. Downsample chart points to at most about 300 per series.
- **Swift 6 strict concurrency**: screen models are `@MainActor @Observable`. Zero warnings in your files.

## Build, test, screenshots
- Create your own simulator: `xcrun simctl create "Vigil-<Feature>" "iPhone 17"`. Boot it, and delete it when done.
- Build and test with your own derived data path, `-derivedDataPath build/DD-<feature>`, plus `CODE_SIGNING_ALLOWED=NO` and `-parallel-testing-enabled NO` (exact commands are in ARCHITECTURE.md §1). All tests must pass.
- Launch with `-VigilSkipOnboarding`, and `-VigilMockScenario <name>` for state screens. Use `xcrun simctl openurl` with `vigil://` deep links to reach detail screens (see `Shared/Navigation/DeepLink.swift`), or temporarily change the initial route in a DEBUG-only way inside your own folder. Never commit changes to `Vigil/App`.
- Screenshot every screen in light and dark mode (`xcrun simctl ui <id> appearance dark|light`, then `xcrun simctl io <id> screenshot build/screenshots/<feature>-<screen>-<mode>.png`). **Open the screenshots and compare them with the HTML design.** Fix mismatches in layout, spacing, hierarchy and copy before you finish. Scroll long screens and capture them in parts.
- Add Swift Testing tests for screen-model logic (formatting decisions, state selection, derived values) in `VigilTests/<Feature>*.swift`.

## Finish
Commit on your worktree branch with message `Phase 2: <feature> screens`.

Report, concisely:
- branch name
- screens done
- repository extensions or new routes you need
- private components that could move into the design system
- known gaps against the design
- absolute screenshot paths
