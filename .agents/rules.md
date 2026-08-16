# Rules

These are repository coding and testing conventions. Codex command permission rules belong in `.codex/rules/*.rules`; see `.agents/agent-config.md` before adding those.

## Dart and Flutter Style

The lint set lives in `lint_options.yaml` at the repo root. The root `analysis_options.yaml` and every local plugin under
`plugins/*` include it, so application and plugin code are held to the same rules. Add or change a rule there, not in an
individual `analysis_options.yaml`; those files carry only their own `analyzer.exclude` entries.

`lint_options.yaml` enforces these non-default rules:

- `prefer_single_quotes: true`: always use single quotes.
- `require_trailing_commas: true`: use trailing commas in multi-line argument lists.
- `sort_child_properties_last: true`: `child:` must be the last named parameter.
- `avoid_print: true`: do not use `print()` calls.
- `prefer_const_constructors: true` and `prefer_const_declarations: true`.
- `prefer_final_locals: true` and `prefer_final_in_for_each: true`.
- `always_declare_return_types: true`.

Generated directories are excluded from analysis:

- `build/**`
- `lib/l10n/intl/**`
- `lib/**/generated/**`
- `plugins/**`

## Comments

Comments are opt-in and reserved for the few places that genuinely need one. Density is the point: every comment that
restates the code devalues the comments that carry real information, until readers skim past all of them. A file with
three comments that matter is more readable than one with thirty.

### Writing Comments

- Never add a comment on your own initiative. This covers explanatory, narrative, TODO, section-divider, and
  documentation comments, in Dart, Kotlin, Swift, Go, Rust, YAML, Gradle, and any other file you touch.
- Never annotate line by line or statement by statement, and never restate in prose what the code already says. If a
  block needs a comment per step, the block needs better names or a smaller decomposition instead.
- When a change genuinely cannot be understood without a comment, do not write it silently. Explain what is unclear,
  propose the exact comment text, and wait for the user to approve it before adding it.
- Delete commented-out code, stale version notes, and comments that only restate the code, whenever you edit the file
  that contains them. This does not need approval.
- These are not comments and must be preserved: analyzer and linter directives (`// ignore:`, `// ignore_for_file:`,
  `// coverage:ignore`), license and copyright headers, code-generation markers, and comments inside vendored upstream
  code such as `lib/widgets/open_container.dart`.

### Where Knowledge Belongs

Pick the destination by where the constraint would be violated, not by how important it feels.

- **Assertable behavior goes in a test.** A test is the only form that cannot drift, because it fails when the behavior
  it describes is broken. Prefer it over both a comment and a document whenever the fact can be checked in code.
- **Repository-wide defaults, ownership, and invariants go in `.agents/*.md` or a `.agents/skills/*/SKILL.md`.** They
  are violated from many files, so they must reach every future agent at session start. A comment in one file cannot do
  that.
- **A fact that is true only at one call site, and is not visible from that call site, stays a comment there.** Its
  value is being in the reader's line of sight at the moment of the edit. `lib/common/constant.dart` is the model case:
  the delay-test concurrency cap is bound to `mBatch` in `core/common.go`, and whoever changes that number must see the
  constraint on the same screen.

Both failure directions are real. Moving a local constraint into `.agents/` hides it from the person editing the line;
leaving a repo-wide policy as a comment reaches only the reader of that one file.

Before any of the three, prefer encoding the intent in structure and naming — a named mixin, type, or method that makes
the invariant hard to break beats prose that asks the next reader not to break it.

## Core API Safety

- Do not expose direct filesystem deletion APIs through Core or helper IPC; use
  a scope-specific cleanup API instead.
- Keep the shared `CoreMethodCall`/`CoreMethodResponse` JSON envelope structurally identical across Dart, Go, JNI, and
  desktop IPC. Do not double-encode `arguments`, `result`, or event batches.
- Keep high-volume log/request events separate from state-bearing events in `core/message.go`; bulk backpressure must not
  evict delay, loaded-provider, or geo-update state.

## Lifecycle Rules

- Desktop process ownership belongs to `DesktopCoreLifecycle`; do not start/kill `FlClashCore` from providers, widgets,
  managers, or ad hoc exit callbacks. Acquire and release it through a `CoreProcessLease`.
- `CoreController.close()` and platform `close()` implementations are terminal and idempotent. Application shutdown must
  stay centralized in `SystemAction`/`SystemExitCoordinator`.
- Android start/stop MethodChannel calls are optimistic UI commands. Keep latest-wins arbitration in native
  `ServiceState`; do not add a Flutter completion callback that creates a second lifecycle owner.
- Android service callbacks are not automatically user intent. Route explicit Quick Settings, Always-on VPN, and revoke
  actions through `ServiceState` and keep `ServiceController` as the sole binding/run-time owner.
- Every `BroadcastReceiver.goAsync()` path must finish its `PendingResult` exactly once. A watchdog may release the
  broadcast lease, but must not cancel, reverse, or otherwise redefine the service operation.
- Presentation smoothing such as `CoreStatusButton`'s connecting hold must remain local display state. It must not delay or
  overwrite `coreStatusProvider`, and a real failure must bypass/cancel the hold immediately.
- `Tray.hide()` is idempotent on all three desktop platforms and returns native state to "`show` was never called".
  `AppTray.shutdown()` latches, so no later `update()`/`updateTitle()` can resurrect the icon once shutdown begins.
  Keep it that way; a resurrected icon outlives `exit(0)` as a Windows ghost icon, because `setPreventClose(true)`
  means `WM_DESTROY` never runs.
- The `tray` plugin owns call ordering, idempotency, serialization, and unchanged-payload suppression. Application code
  declares desired state through one `Tray.show(TraySpec)` call and must not add platform branches to work around
  ordering. Platform branches in `lib/common/tray.dart` are only for deliberate product differences (macOS speed title
  and group submenus); query `Tray.instance.capabilities` for ability differences.
- Every native `show` returns whether the tray now reflects the payload, and reports `false` instead of showing a broken
  icon. `Tray` caches the payload signature only on `true`, so a rejected `show` is retried by the next update rather
  than suppressed until restart. Any test that mocks the `tray` channel must return `true` from `show`.

## Testing Rules

The `core/` directory is excluded from automated coverage accounting. Do not add coverage instrumentation or coverage
collection for code under `core/`. CI still runs `CGO_ENABLED=0 go test .` and `go vet .` to compile/check the Go wrapper;
verify cross-language protocol behavior through shared Dart contract tests under `test/core/` and native platform build
checks.

Use `CoreController.test(mock)` to inject a mocked `CoreHandlerInterface`. Call `CoreController.resetInstance()` in `tearDown` to clean up the singleton between tests.

Register fallback values for freezed params used with `any()` matchers.

`tool/check_coverage.dart` enforces a total floor passed by CI plus per-group floors declared in `_groupFloors`. Raise a
group's floor when new tests lift it; do not lower one to make a run pass.

Every measured group needs a floor. A group the report measures but `_groupFloors` does not declare fails the run, so
adding a top-level directory under `lib/` means adding its floor in the same change. Set a new floor at or just below
the coverage the directory actually has; the point is to stop a slide, not to backfill tests before the directory can
land.

Prefer `coreHandlerProvider.overrideWithValue(CoreController.scoped(fake))` over `CoreController.test(fake)` in new and
touched tests. `CoreController.test` claims the process-wide singleton, which makes a global read and a provider read
resolve to the same fake, so it cannot fail on a call site that still reaches for the global.

Use `ProviderContainer` directly for simple Riverpod provider tests. The generated Riverpod `update()` method takes a callback:

```dart
notifier.update((state) => newValue);
```

When testing freezed models with nested objects, always round-trip through `jsonEncode` and `jsonDecode`. Direct `fromJson(toJson())` fails for nested freezed types because `toJson()` stores child objects directly instead of maps.

For async widgets, put visual cleanup in `finally` when the action may throw. Focused widget tests should cover success,
failure, disposal, and any timer boundary that changes visible state.

## Commit Messages

Subjects follow Conventional Commits and are enforced by the `commit-msg` hook in `.pre-commit-config.yaml`, which runs
`tool/check_commit_msg.sh`:

```text
<type>[(scope)][!]: <description>
```

- Types: `feat`, `fix`, `docs`, `style`, `refactor`, `perf`, `test`, `build`, `ci`, `chore`, `revert`.
- Scope is optional and lower case; use a comma to list several, as in `fix(core,android)`.
- `!` before the colon marks a breaking change.
- Descriptions start in lower case, omit the trailing period, and keep the whole subject within 100 characters.
- `Merge`/`Revert` subjects and `fixup!`/`squash!` commits are exempt.

Write what the change does, not that something changed: `perf(views): stop redoing per-frame work in build`, not
`Optimize more details`.

Install the hooks once with `pre-commit install --hook-type pre-commit --hook-type pre-push --hook-type commit-msg`.

## Generated Code

Do not manually edit generated files under:

- `lib/l10n/l10n.dart`
- `lib/models/generated/`
- `lib/providers/generated/`
- `lib/database/generated/`
- `lib/l10n/intl/`

After schema, model, or provider changes, run build generation and include focused tests when behavior changes.
