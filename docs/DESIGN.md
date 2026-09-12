# KeyRecord native design contract

## 0. Reference selection
Task 10 establishes primitives, not capture or settings business flows. The reference
is macOS Human Interface Guidelines and standard AppKit/SwiftUI controls:
- https://developer.apple.com/design/human-interface-guidelines/menus
- https://developer.apple.com/design/human-interface-guidelines/buttons
- https://developer.apple.com/design/human-interface-guidelines/accessibility
- https://developer.apple.com/design/human-interface-guidelines/typography
The frontend design-system gate was consulted. Web marketing research, Lazyweb,
Imagen, custom branding and browser Lighthouse are not needed for this native
contract; no claim is made that those research tools ran. System conventions are
the reference, not a website screenshot. Native XCTest is the verification surface.

## 1. Information architecture and scope
A single accessory-policy AppKit process owns an NSStatusItem, native menu and
SwiftUI hosting window. Menu order: status, start, pause, resume, settings, quit.
Before capture integration, capture actions remain disabled and status unstarted;
settings opens an explicitly labeled primitive demonstration, never a fake product
success. No capture, store, Keychain, login registration or network calls occur.
Later consent must explain local aggregation, excluded apps/Secure Input/locked or
unknown contexts, no text or sequence storage, and loss since the last durable
commit on crash/lock. Rejection never starts capture or registers login items.
Later settings exposes exclusions, login item, language, reset and confirmed local
deletion. Later aggregates expose cycle totals, shortcut/app buckets, bare keys,
stateful/system/source-confidence/side-unknown labels; no mapping/recommendations.

## 2. Typography and localization
System Text styles only: title2 for window title, headline for section/state,
body for content and buttons, caption for explanatory values. AppKit uses
preferredFont(forTextStyle:). No font files or custom font names.
All UI strings resolve from bundled Localizable.strings in en and zh-Hans lproj
directories; keys and accessibility identifiers are not translated. Dynamic labels
wrap vertically without line limits. Empty aggregate labels use a localized fallback.
The state harness accepts an explicit locale, independent of the host language.

## 3. Colors and materials
Use primary/secondary semantic foregrounds, native windowBackgroundColor,
native grouped controls and separators. SF Symbols accompany status words; colors
never carry unique meaning. No custom RGB values, remote assets or decorative
animation. Native controls own focus rings, borders, corner radii and pressed states.
Light/dark and increased contrast are environment inputs. In high contrast all
essential text uses primary foreground. No custom material is necessary.

## 4. Layout tokens
Native spacing tokens: compact=8 pt, group=16 pt, page=24 pt. Standard controls
choose intrinsic sizes; there are no fixed text heights. A vertical scroll view
owns overflow. Minimum utility window 640x480 pt; later aggregate window minimum
1000x700 pt. Harness snapshots use 640x900 pt to include all primitives; stress
also exercises 640x480 and 1000x700. Large-text harness uses system title2 body
scale, not a custom font. Longer content expands and scrolls rather than shrinks.

## 5. Primitive contract
All six primitives render in each of unstarted/paused/collecting/blocked/error.
Actions are injected closures; state is supplied, not a capture controller.

| Primitive | Anatomy / native role | Stable accessibility identifiers |
|---|---|---|
| ConsentPanel | GroupBox, wrapping disclosure, accept/reject Buttons | consent.panel, consent.accept, consent.reject |
| CaptureStatus | Label with status text and SF Symbol; combined static text, value=status | capture.status |
| PrimaryAction | Button, Return shortcut; supplied closure | capture.primary |
| AggregateRow | combined static text label plus count/value and classification | aggregates.row |
| SettingsRow | Button with exclusions label | settings.exclusions |
| DestructiveConfirmation | GroupBox, warning text, Cancel and destructive Button; no implicit deletion | destructive.panel, destructive.cancel, destructive.confirm |

Names are localized visible text; values convey status/count. Buttons expose the
native button role and press action. Containers do not hide interactive children.
Native AppKit leaf controls may be hosted through NSViewRepresentable inside the
SwiftUI primitives. This keeps actual NSButton/NSTextField accessibility and key
equivalents inspectable in hostless XCTest without enabling private SwiftUI AX
switches. NativeAction and NativeLabel are adapters, not custom-drawn controls.
The native adapters receive explicit system text styles; large-text fixtures
scale their fonts to title2 as well as scaling SwiftUI text.
Status mapping: unstarted=circle/Start; paused=pause.circle/Resume;
collecting=record.circle/Pause; blocked=lock.circle/Review settings;
error=exclamationmark.triangle/Retry. Blocked/error do not claim saved data.
Harness actions only increment an injected test counter. Consent and destructive
controls do not change production state or persist anything.

## 6. Keyboard and motion
Focus follows visual order: accept, reject, primary, exclusions, cancel, confirm.
Tab/Shift-Tab use native focus traversal; Return activates only PrimaryAction.
Destructive confirmation has no default Return shortcut; Escape cancels.
Menu settings uses Command-comma and quit Command-Q. Menu items have identifiers
menu.status/start/pause/resume/settings/quit. Harness selector controls have
harness.state/locale/appearance IDs. No animations or timers: Reduce Motion
therefore preserves the same immediate, deterministic state feedback.

## 7. Accessibility constraints and validation
Primary users include keyboard-only, VoiceOver, low-vision/high-contrast and
Simplified Chinese readers. Every interactive element must have a nonempty name,
stable ID and native role. Inspect actual in-process NSHostingView accessibility
elements, not just model metadata. Tests exercise key equivalents, AX press,
non-color state words/icons, all 20 state/locale/appearance combinations, long CJK,
large text, empty/error, high contrast and Reduce Motion. Bitmap evidence is
NSHostingView-rendered PNG of seeded data only; missing Window Server bitmaps
must produce an exact BLOCKED screenshot receipt, not blank/fabricated success.

## 8. Accepted debt and handoff
Task 14 owns state orchestration; task 18 owns product screens and signed end-to-end
flows; task 22 owns full native visual/VoiceOver qualification. The present harness
does not prove permission dialogs, capture, persistence, signed UI automation,
macOS 14 runtime execution or Intel runtime performance. Unsigned Universal build
proves compilation for both architectures, not signing or entitlements enforcement.

### Verification execution limitation
On the task-10 agent session, `xcodebuild test` timed out with “The test runner
timed out while preparing to run tests.” Q10 uses `xcodebuild build-for-testing`
followed by Apple's direct `xcrun xctest` against the built hostless bundle.
These are real XCTest assertions, not a successful Xcode test-manager session;
no `xcodebuild test` PASS is claimed. The shared QA dispatcher is unchanged.
Window Server may clamp the requested 640x900 window to the available screen;
the PNG's actual dimensions are evidence, not an assertion of the requested size.
