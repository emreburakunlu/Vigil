# Vigil — Architecture & rules for agents

Vigil is a native SwiftUI iPhone app (iOS 27.0+, portrait) that **reads** Apple Health and turns it into
Recovery, Sleep and Strain scores plus running/lifting progress. Product constraints that shape every decision:

- **Read-only HealthKit.** Nothing is ever written to Health. No in-app logging of sets/reps.
- **All data local.** No accounts, servers, analytics or CloudKit. SwiftData in the app sandbox.
- **Free Apple ID signing.** No paid-only capabilities (no CloudKit, no push).
- Units default metric (switchable to imperial); appearance Light / Dark / System.
- First launch imports 90 days of history and builds 30-day baselines.

Design reference: `Design/*.dc.html` (one board per screen, `Design/canvas.json` lists titles). Open them in a
browser; `{{…}}` placeholders are filled by the `<script type="text/x-dc">` block at the bottom of each file.

---

## 1. Build & test

Every agent uses its **own** derived-data path so parallel builds don't collide (`build/` is git-ignored):

```sh
# Build (app + widget extension)
xcodebuild -project Vigil.xcodeproj -scheme Vigil \
  -destination 'platform=iOS Simulator,name=iPhone 17' \
  -derivedDataPath build/DD-<agent-name> \
  CODE_SIGNING_ALLOWED=NO build

# Unit tests (Swift Testing, hosted in Vigil.app)
xcodebuild -project Vigil.xcodeproj -scheme Vigil \
  -destination 'platform=iOS Simulator,name=iPhone 17' \
  -derivedDataPath build/DD-<agent-name> \
  CODE_SIGNING_ALLOWED=NO -parallel-testing-enabled NO test

# Run on the simulator (mock data is automatic in the simulator)
APP=build/DD-<agent-name>/Build/Products/Debug-iphonesimulator/Vigil.app
xcrun simctl install booted "$APP"
xcrun simctl launch booted com.emreburakunlu.vigil -VigilSkipOnboarding
xcrun simctl io booted screenshot /tmp/vigil.png
```

- `-parallel-testing-enabled NO` avoids cloning the simulator per run (slow, and 10 agents × clones is heavy).
- Filter tests with `-only-testing:VigilTests/FormatterTests`.
- Launch arguments (see `Vigil/App/LaunchConfiguration.swift`):

| Argument | Effect |
|---|---|
| `-VigilMockData` | Force mock data (device builds). |
| `-VigilLiveData` | Force real HealthKit in the simulator. |
| `-VigilMockScenario <name>` | `standard`, `newUser`, `healthAccessDenied`, `noSleepLastNight`, `noRunsThisWeek`, `partialData`, `empty`. |
| `-VigilSkipOnboarding` | Mark onboarding complete at launch. |
| `-VigilResetData` | Wipe the local SwiftData store at launch. |
| `-VigilInMemoryStore` | Don't touch the on-disk store. |

Deep links can be tested with `xcrun simctl openurl booted 'vigil://sleep/night/2026-10-18'` (table in
`Shared/Navigation/DeepLink.swift`).

---

## 2. Project layout & ownership

The project uses **file-system synchronized groups** (`PBXFileSystemSynchronizedRootGroup`): any file you add
under a folder is automatically part of that folder's target(s). **Never edit `project.pbxproj`**; ask the
orchestrator for build-setting or target changes.

| Folder | Compiled into | Owner | Contents |
|---|---|---|---|
| `Vigil/App/` | app | orchestrator | `VigilApp`, `RootView`, `MainTabView`, `AppContainer` (DI), `LaunchConfiguration`, `AppRouter`/`AppRoute`, `RouteDestinationView`, preview support, temporary `ScreenPlaceholder` |
| `Vigil/Core/Models/` | app | orchestrator (contract) | Domain value types |
| `Vigil/Core/HealthKit/` | app | HealthKit agent (protocol file: orchestrator) | `HealthDataSource` protocol, `LiveHealthDataSource` |
| `Vigil/Core/Mock/` | app | mock-data agent | `MockHealthDataSource`, `MockScenario` |
| `Vigil/Core/Engine/` | app | engine agent (`ScoreEngine.swift`: orchestrator) | `ScoreEngine` protocol, `DefaultScoreEngine`, `SplitCalculator` |
| `Vigil/Core/Persistence/` | app | orchestrator | SwiftData schema, `PersistenceController`, `SettingsStore`, `DailySummaryStore` |
| `Vigil/Core/Services/` | app | orchestrator | `VigilRepository`, screen models, import, widget snapshot, notifications |
| `Vigil/DesignSystem/` | app | design-system agent | Appearance override, shared components (`vCard()`, rings, chips…) |
| `Shared/DesignSystem/` | app + widget | design-system agent | Colour tokens, typography roles, spacing/radii |
| `Shared/` (rest) | app + widget | orchestrator | `AppGroup`, `WidgetSnapshot` + store, `LocalDay`, `DeepLink`, `VigilFormatter`, score bands, `UnitSystem`/`AppearanceMode` |
| `Shared/Resources/Fonts/` | app + widget | design-system agent | `BricolageGrotesque-Variable.ttf`, `Figtree-Variable.ttf` (SIL OFL) |
| `Vigil/Features/Onboarding/` | app | onboarding agent | Welcome ×3, Health access, About you, Goals, History import, Health-access-denied state |
| `Vigil/Features/Today/` | app | Today agent | Today (incl. partial-data state), Recovery, Strain, Metric detail |
| `Vigil/Features/Sleep/` | app | Sleep agent | Sleep, Sleep calendar, Sleep night, no-sleep state |
| `Vigil/Features/Train/` | app | Train agent | Train (Run/Lift), Run detail, Lift detail, no-runs state |
| `Vigil/Features/Progress/` | app | Progress agent | Progress (Running/Lifting/Body) |
| `Vigil/Features/Profile/` | app | Profile agent | Profile & settings |
| `VigilWidgets/` | widget | widget agent | Widget bundle, timeline provider, 3 widgets |
| `VigilTests/` | tests | everyone (own files) | Swift Testing suites; name files after the unit under test |
| `Config/` | — | orchestrator | Info.plists and entitlements |

Rules:
- Only edit files inside folders you own. Need a contract change (model field, repository method, route)?
  Ask the orchestrator; until then, compute it locally in your feature from existing contracts.
- Feature folders may contain subfolders (`Today/Components/`, `Today/TodayModel.swift`). Prefix shared-looking
  private types with the feature name (`TodayVitalRow`) to avoid cross-feature name clashes — all app code lives
  in one module.
- `Shared/` is compiled into **both** app and widget: it must not reference app-only types (Core, Features).

---

## 3. Contracts (where they live)

| Contract | File(s) | Notes |
|---|---|---|
| Domain models | `Vigil/Core/Models/*.swift`, `Shared/Models/*.swift` | `Sendable`, `Codable`, `Hashable` value types. Canonical metric units. |
| Health data source | `Vigil/Core/HealthKit/HealthDataSource.swift` | async throwing, nonisolated, "no data" = empty, never trap. |
| Score engine | `Vigil/Core/Engine/ScoreEngine.swift` (+ outputs in `Core/Models/Scores.swift`) | Pure & deterministic; time only via inputs. |
| Repository (what screens call) | `Vigil/Core/Services/VigilRepository.swift`, `ScreenModels.swift` | `@MainActor`; returns screen models (`DayOverview`, `RunDetail`, …). |
| Settings | `Vigil/Core/Models/Settings.swift`, `Vigil/Core/Persistence/SettingsStore.swift` | `VigilSettings` value; mutate through `SettingsStore.update {}` / `binding(\.x)`. |
| Navigation | `Vigil/App/AppRouter.swift`, `RouteDestinationView.swift`, `Shared/Navigation/DeepLink.swift` | Screen initializers listed below are part of the contract. |
| Formatting | `Shared/Formatting/VigilFormatter.swift` | The only place unit maths/symbols exist. |
| Design tokens | `Shared/DesignSystem/*.swift` | `.vInk`, `.vTextStyle(.headline)`, `VSpacing`, `VRadius`. |
| Widget snapshot | `Shared/Models/WidgetSnapshot.swift`, `Shared/Storage/WidgetSnapshotStore.swift` | Written by `WidgetSnapshotService`, read by the widget. Add only optional fields. |

Canonical units (stored & passed everywhere): metres, kilograms, seconds, seconds-per-km (pace), bpm, ms (HRV),
breaths/min, °C (absolute wrist temperature; baseline deltas computed by the engine), SpO₂ as percent 0–100,
kcal, mL/kg/min. Convert only for display, via `VigilFormatter`.

Day semantics: `LocalDay` (year/month/day) is the key for all daily data. A sleep night belongs to the day the
user **woke up**. Never compare `Date`s for "same day" in feature code; use `LocalDay(date, calendar:)`.

Screen initializers (keep these signatures):

```swift
TodayView()  SleepView()  TrainView()  ProgressTabView()  ProfileView()   // tab roots
RecoveryDetailView(day: LocalDay)     StrainDetailView(day: LocalDay)
MetricDetailView(metric: HealthMetric, day: LocalDay)
SleepCalendarView(month: LocalDay)    SleepNightView(day: LocalDay)
RunDetailView(workoutID: UUID)        LiftDetailView(workoutID: UUID)
OnboardingFlowView()                  HealthAccessDeniedView(onRetry: () -> Void)
NoSleepStateView()  NoRunsStateView() // embedded by their tab when empty
```

Navigate with `NavigationLink(value: AppRoute.runDetail(id)) { … }` or `router.push(.sleepNight(day))`.
Never create your own `NavigationStack` inside a tab (each tab already has one) and never use
`navigationDestination` for `AppRoute` yourself (registered once by `withAppRoutes()`).

---

## 4. Concurrency

Swift 6 language mode, strict concurrency, **default isolation = nonisolated** (Swift's default; we do *not*
use `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor`, so `Shared/` code behaves identically in app and widget).

- **UI layer is `@MainActor`.** SwiftUI views are MainActor via `View`. Every `@Observable` class
  (view models, stores, router, container) must be annotated `@MainActor`.
- **Data & engine layers are nonisolated `Sendable` value types.** `HealthDataSource` implementations are
  `Sendable` structs (or actors); their `async` methods run off the main actor. `ScoreEngine` is synchronous and
  pure; heavy calls should be made from a nonisolated async context, not in `body`.
- Persistence (`SettingsStore`, `DailySummaryStore`, `VigilRepository`) is `@MainActor` and uses the container's
  `mainContext`. SwiftData `@Model` objects never leave the persistence layer — features get value types.
- Load data with `.task { … }` / `.task(id:)` (auto-cancelled), not `onAppear { Task { … } }`.
- No `DispatchQueue`, no `@unchecked Sendable`, no `nonisolated(unsafe)` without orchestrator review.

---

## 5. Dependency injection & mock data

`AppContainer` (`Vigil/App/AppContainer.swift`) builds everything once and is injected by `VigilApp`:

```swift
@Environment(AppContainer.self) private var container      // container.repository, .importer, .dataSource …
@Environment(SettingsStore.self) private var settingsStore // settingsStore.settings, .formatter, .binding(\.units)
@Environment(AppRouter.self) private var router
```

Data source selection (`LaunchConfiguration.resolve`): previews and unit tests → mock + in-memory store;
simulator → mock (store `Vigil-Mock`) unless `-VigilLiveData`; device → live (store `Vigil`) unless `-VigilMockData`.
The mock is deterministic (seeded per day) and anchored to "now", so the simulator always looks current.

**Previews** — every screen file ends with previews using the mock container:

```swift
#Preview { TodayView().vigilPreview() }                         // standard data, in a NavigationStack
#Preview("Partial data") { TodayView().vigilPreview(.partialData) }
#Preview("Dark") { TodayView().vigilPreview().preferredColorScheme(.dark) }
```

For pure subviews, prefer passing values (`DayOverview`, `VitalReading`) built in the preview over
loading through the repository.

Tests construct containers explicitly with a fixed clock:
`AppContainer(configuration: …, calendar: utc, now: { fixedDate })` (see `VigilTests/CoreTests.swift`).

---

## 6. Design system

- **No hard-coded colours, fonts or magic numbers in feature code.** Use:
  - Colours: `Color.vX` / `.vX` (`foregroundStyle(.vInkSecondary)`, `.background(Color.vCard)`).
    Surfaces `vBackground vCard vCardRaised vFill vControlTrack vSeparator vHairline`; ink `vInk vInkLabel
    vInkSecondary vInkTertiary vInkDisabled`; scores `vRecovery/Tint/Ink vSleep/Tint/Ink vStrain/Tint/Ink`;
    training `vRun vRunSoft vRunTint vLift vLiftSoft vLiftTint`; status `vPositive vWarning vWarningInk vDanger …`;
    sleep stages `vStageAwake/REM/Core/Deep`; zones `Color.vZone(n)`; bands `Color.vRecoveryBand(_)`,
    `Color.vSleepScoreBand(_)`. The **Sleep tab uses the night palette** (`vNight*`) in both appearances.
  - Type: `Text("Vitals").vTextStyle(.headline)` (font + tracking + case) or `.font(.vBody)`.
    Roles: `largeTitle title title2 headline display score statValue statValueSmall body bodyStrong callout
    subheadline footnote caption caption2 overline`. All scale with Dynamic Type.
  - Layout: `VSpacing` (`screenGutter` 16, `cardPadding` 18, …), `VRadius` (`card` 24, `tile` 16, …),
    `VSize.minTapTarget` (44). Card surface: `.vCard()`.
- Tokens are dynamic `UIColor`s; the in-app Appearance override sets the window's `overrideUserInterfaceStyle`
  (`Vigil/DesignSystem/Appearance.swift`), so tokens follow it automatically. Dark values are temporary until the
  design-system agent finalises them.
- Missing a token? Ask the design-system agent; don't inline a value.
- SF Symbols are fine for icons; set `.accessibilityHidden(true)` on decorative ones.

---

## 7. Units, strings & formatting

- Never format numbers with units by hand. `settingsStore.formatter` (app) / `VigilFormatter(units:)` (widget):
  `distance(meters:)`, `pace(secondsPerKilometer:)`, `weight(kilograms:)`, `elevation(meters:)`,
  `temperatureDelta(celsius:)`, `heartRate(bpm:)`, `format(metric, value)`, `duration(_, style:)`,
  `timeOfDay(_:)`, `signed(_:fractionDigits:)` (true minus sign `−`).
- They return `FormattedValue(value:unit:)` so the number and unit can be styled separately; `.text` joins them.
- Dates: use `Date.FormatStyle` (`.dateTime.weekday().day().month()`), never fixed format strings.
- User-facing copy lives in the view (`Text("Last 7 days")` is auto-extracted for localization). Never build
  unit strings ("km", "lb") in features.

---

## 8. Persistence, import & widgets

- SwiftData schema `VigilSchemaV1` (`SettingsRecord` singleton, `DailySummaryRecord` per day with a JSON
  `DailySummary` payload). Changes need a new `VersionedSchema` + migration stage.
- Store lives in the app sandbox (`groupContainer: .none`, `cloudKitDatabase: .none`).
- `HistoryImportService.importHistory()` (onboarding) fetches 90 + 30 days, builds summaries, caches them,
  refreshes the widget snapshot and sets `onboarding.historyImportedAt`. `refreshRecent()` recomputes the last
  2 days on launch and on every `HealthDataSource.updates()` event.
- Widgets read only `WidgetSnapshot` from the App Group (`group.com.emreburakunlu.vigil`) via
  `WidgetSnapshotStore`; the app writes it in `WidgetSnapshotService.refresh()` and reloads timelines.
  When the App Group is unavailable (unsigned builds) both sides fall back to a private directory — the widget
  then shows placeholder data.
- Notifications are local only (`NotificationService`): morning summary and bedtime reminder.

---

## 9. Naming conventions

- Types `UpperCamelCase`; one primary type per file, file named after it.
- Screens end in `View` (`SleepNightView`); feature view models end in `Model` (`SleepNightModel`,
  `@MainActor @Observable`); subviews are prefixed with their feature (`SleepStageBar`).
- Design tokens start with `v`/`V` (`.vInk`, `VSpacing`). Don't use the `v` prefix for anything else.
- Durations are `TimeInterval` seconds; distances `…Meters`; energy `…Kilocalories`; HR `…HeartRate` (bpm).
- Booleans read as assertions (`isPartial`, `hasRoute`). Avoid abbreviations except HR, HRV, VO₂ max, RHR.

---

## 10. Definition of done (screen agents)

A screen is done when:

1. It builds with the command above and **zero warnings in your files** (Swift 6 strict concurrency).
2. It matches the design board's content and hierarchy, using only design tokens (no literal colours,
   fonts, paddings or radii).
3. It loads data only through `VigilRepository` (or values passed in), using `.task`; shows sensible
   loading, empty and error states (including the relevant mock scenarios).
4. `#Preview`s exist for the standard mock data, the relevant state scenarios, and dark mode; they render.
5. Light and dark appearances both look right (dark uses the token dark values; report gaps to the
   design-system agent rather than inlining colours).
6. Dynamic Type: usable at `.accessibility2`; text wraps or scales, nothing is clipped; numbers use
   `monospacedDigit` (built into the type roles).
7. Accessibility: meaningful `accessibilityLabel`s for rings, charts and icon-only buttons (e.g. "Recovery 78
   percent, green"), headers marked with `.isHeader`, charts expose an `accessibilityValue` summary, decorative
   images hidden, tap targets ≥ 44 pt.
8. No hard-coded units or unit maths — all via `VigilFormatter`; switching Profile → Units updates the screen.
9. Unit tests for any non-trivial logic you add in your folder (view-model mapping, formatting decisions).
10. You haven't edited files outside your folder, `project.pbxproj`, or the contracts.

---

## 11. Known risks (signing with a free Personal Team)

- **App Groups**: verify when the user first signs with their Personal Team. If Xcode refuses the App Group
  capability, the widget falls back to placeholder data (the code already handles a nil container).
- **HealthKit background delivery** (`com.apple.developer.healthkit.background-delivery`): verify it provisions
  on a Personal Team. If not, remove that entitlement — the app still refreshes on launch/foreground; only
  "morning summary right after you wake" degrades to the scheduled fallback time.
- HealthKit cannot be exercised in the simulator without data: the simulator uses the mock unless
  `-VigilLiveData`. Real HealthKit testing requires a signed device build.
- Free-team builds expire after 7 days and are limited to 3 apps per device.

---

## 12. Design system usage

Fonts: `Font.custom` with the variable fonts' named instances (`VFontFamily.postScriptName`), so 600/700/800 really apply; all roles scale with Dynamic Type. Colours are dynamic (light/dark) tokens; the Sleep tab forces the dark scheme in `MainTabView`, so system chrome is dark there in both appearances. Pushed detail screens hide the floating tab bar. Browse everything in `Vigil/DesignSystem/DesignSystemGallery.swift` (DEBUG previews).

**Tokens** (`Shared/DesignSystem`)
- Colour: `.foregroundStyle(.vInk)`, `.background(Color.vCard)`; groups: surfaces, ink, brand (`vAccent vPrimaryButton vTabBar*`), scores, training (`vRun* vLift*`), status (`vPositive vWarning* vDanger*`), stages, zones `Color.vZone(3)`, activity (`vMove vExercise vStand`), chart (`vChartGrid vChartBaseline`), night (`vNight*`).
- Type: `Text("Today").vTextStyle(.largeTitle)`; free sizes `Font.vCustom(.heading, size: 29, weight: .bold, relativeTo: .title)`.
- Layout: `VSpacing.screenGutter`, `VRadius.card`, `VSize.minTapTarget`, `VSize.tabBarReservedHeight`.
- Motion: `view.vRiseIn(delay: 0.07)`, `Button {}.buttonStyle(.vPress)`, `VMotion.ease(duration:)`; all honour Reduce Motion.
- Rings (Shared, usable in widgets): `ScoreRing(kind: .sleep, progress: 0.84) { Text("84") }`, `ConcentricRings(recovery: 0.78, sleep: 0.84, strain: 0.62)`.

**Components** (`Vigil/DesignSystem`)
- `view.vCard()` / `VCard { }` / `view.vNightCard()`; `ScoreCard { ScoreTile(kind:progress:value:unit:caption:) x3 }`.
- `SectionHeader("Vitals", trailing: "vs. 30-day baseline")`, `OverlineLabel("Apple Health")`.
- `VitalTile(name:value:unit:delta:trend:trendColor:)`, `DeltaBadge("+12%", direction: .up, tone: .positive)`, `Sparkline(values:)`, `MetricRow` inside `MetricRowList`.
- `StatTile("Distance", value: "18.4", unit: "/ 25 km")` in `StatGrid(columns: 3) { }`.
- `ProgressBarGoal("Running", value:goal:valueText:goalText:color:)`, `SegmentedGoalBar`, `ZoneBar(zone: 3, fraction: 0.45, duration:percentText:)`.
- `VSegmentedControl(selection: $x, options: [...]) { LocalizedStringKey($0.title) }` (optional `selectedFill:`).
- `DayStrip(items: [DayStripItem], selection: $day) { delta in ... }` (swipe + VoiceOver adjustable).
- `CircleIconButton(systemImage:label:) { }`, `PrimaryButton("Continue", kind: .inverse) { }`, `SecondaryButton("Edit", isDestructive:) { }`, `VTextButton`, `.buttonStyle(.vPill(.primary))`.
- `VChip("via Hevy", tone: .run)`, `PRBadge(isNew:)`, `InsightRow(text, systemImage:)`, `EmptyStateView(systemImage:title:message:actionTitle:action:)`.
- Charts: `Chart { ... }.vChartAxes()`, `.vLineStyle(.vRecovery)`, `.vAreaStyle(_)`, `.vBarStyle(_)`, `VBaselineBand(low:high:)`, `VReferenceLine`, `VPointMarker`.
- Sleep tab screens: end the root view with `.vNightScreen()` (night background, night components via `\.vSurface`, dark nav bar). Other screens: `.vScreenBackground()`.

**Phase 4 design-system additions**
- Tab-bar clearance: `MainTabView` applies `contentMargins(.bottom, barHeight + gap + 28, for: .scrollContent)` to each tab root (only while the bar is visible), so every `ScrollView` on a tab root scrolls clear of the floating bar with no per-screen code. Pushed screens do not inherit it. The bar is an overlay, not a safe-area inset (avoids double padding).
- `VTabBar` stays 66 pt; Dynamic Type is capped at `.xxxLarge`; labels hide at accessibility sizes (icons only, VoiceOver labels kept, large content viewer on long press).
- `CircleIconButton` is neutral (card circle, ink glyph, hairline); `usesAccent: true` is opt-in. Header buttons must use it rather than a bare `Button` (StrainDetailView calendar, RecoveryDetailView help).
- Charts: `vLineStyle`/`vAreaStyle` use `.linear`; do not apply `.monotone`/`.catmullRom` in feature charts. `VBaselineBand` is a solid tint. `VEndDot(x:y:color:)` draws the white-filled end dot (r 5, 3 pt stroke).
- `vNightScreen()` also fades the night surface under the status bar.
- `VSkeletonStack(heights: [210, 300, 240], label:)` replaces ad-hoc skeletons (surface from `\.vSurface`); `VErrorCard(title:message:retry:)` replaces ad-hoc failure cards.
