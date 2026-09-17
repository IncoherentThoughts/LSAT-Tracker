# `project.pbxproj` delta — Russian Tracker → LSAT Tracker

Research output for [#5](https://github.com/IncoherentThoughts/LSAT-Tracker/issues/5), part of the
macOS port map [#3](https://github.com/IncoherentThoughts/LSAT-Tracker/issues/3).

**Sources compared (read directly, verbatim):**

- `LSAT Tracker.xcodeproj/project.pbxproj` (this repo, 835 lines, `objectVersion = 77`)
- `~/Desktop/Misc./Projects/Russian/Russian-Tracker/Russian Tracker.xcodeproj/project.pbxproj` (893 lines, `objectVersion = 77`)
- the `*.entitlements`, `*-Info.plist` and `xcshareddata/xcschemes/*.xcscheme` files on both sides
- `Russian-Tracker/docs/plans/2026-09-05-mac-app-and-sync.md` (Russian Tracker's plan of record, cited where it explains *why* a setting exists)

**Audience:** whoever picks up [#6 “Set up the macOS + Supabase build”](https://github.com/IncoherentThoughts/LSAT-Tracker/issues/6), which per the map is the *only* ticket permitted to edit `LSAT Tracker.xcodeproj/project.pbxproj`.

---

## 0. Orientation — how similar the two files really are

Russian Tracker was cloned from LSAT Tracker, and **every object UUID is identical between the two
files**. `FAA686DA2F52427900481D93` is the app target in both; `FA7311262F52A42600E4A16C` is the
widget extension in both; `FA284E202F54EE7D00726B60` is the `ActivityKit.framework` file reference
in both. Only the `/* comment */` names differ (`Russian` vs `LSAT`).

This is unusually good news: the port is a **pure settings diff**, not a project restructure. No
object needs to be created with a new identity except the five SPM objects in §2 and the two
entitlements file references in §3. Nothing needs renumbering.

Both sides already share, byte-for-byte identical, all of:

- `objectVersion = 77`, `preferredProjectObjectVersion = 77`, `archiveVersion = 1`
- `LastSwiftUpdateCheck = 2620`, `LastUpgradeCheck = 2620`, `CreatedOnToolsVersion = 26.2` on all four targets
- the four `PBXFileSystemSynchronizedRootGroup`s (app, Tests, UITests, widget folder)
- the project-level `Debug`/`Release` `XCBuildConfiguration`s (`FAA686FA…` / `FAA686FB…`) — **zero differences**, do not touch them
- all four `XCConfigurationList`s, all `PBXResourcesBuildPhase`/`PBXSourcesBuildPhase` entries (all empty), the `Embed Foundation Extensions` copy phase shape, and both widget `Info.plist` files

Everything below is what actually differs.

---

## 1. Build settings, per target and configuration

### 1.1 App target — `LSAT Tracker` (`FAA686DA2F52427900481D93`)

Configs `FAA686FD2F52427B00481D93` (Debug) and `FAA686FE2F52427B00481D93` (Release). Apply every
change to **both** configs unless noted.

| Setting | LSAT now | Russian | Action |
|---|---|---|---|
| `SDKROOT` | `auto` | `auto` | — already correct |
| `SUPPORTED_PLATFORMS` | `"iphoneos iphonesimulator macosx xros xrsimulator"` | `"iphoneos iphonesimulator macosx"` | **Change** — drop `xros xrsimulator` (§1.5) |
| `TARGETED_DEVICE_FAMILY` | `"1,2,7"` | `"1,2"` | **Change** — drop `,7` (visionOS) |
| `XROS_DEPLOYMENT_TARGET` | `26.2` | *(absent)* | **Delete the line** |
| `MACOSX_DEPLOYMENT_TARGET` | `15.6` | `15.0` | **Change** to `15.0` (§1.5) |
| `IPHONEOS_DEPLOYMENT_TARGET` | `17.6` | `17.6` | — unchanged |
| `CODE_SIGN_ENTITLEMENTS` | `"LSAT Tracker/LSAT Tracker.entitlements"` | `"Russian Tracker/Russian Tracker.entitlements"` | — keep LSAT path |
| `"CODE_SIGN_ENTITLEMENTS[sdk=macosx*]"` | *(absent)* | `"Russian Tracker/Russian Tracker.macOS.entitlements"` | **Add** as `"LSAT Tracker/LSAT Tracker.macOS.entitlements"` |
| `CODE_SIGN_IDENTITY` | `"Apple Development"` | `"Apple Development"` | — unchanged |
| `CODE_SIGN_STYLE` | `Automatic` | `Automatic` | — unchanged |
| `DEVELOPMENT_TEAM` | `3LYN963K9A` | `3LYN963K9A` | — unchanged (same personal team) |
| `PROVISIONING_PROFILE_SPECIFIER` | `""` | `""` | — unchanged |
| `REGISTER_APP_GROUPS` | `YES` | `YES` | — unchanged |
| `ENABLE_APP_SANDBOX` | `YES` | `YES` | — unchanged |
| `ENABLE_USER_SELECTED_FILES` | `readonly` | `readonly` | — unchanged |
| `SWIFT_DEFAULT_ACTOR_ISOLATION` | `MainActor` | `MainActor` | — unchanged |
| `LD_RUNPATH_SEARCH_PATHS` | `"@executable_path/Frameworks"` | same | — unchanged |
| `"LD_RUNPATH_SEARCH_PATHS[sdk=macosx*]"` | `"@executable_path/../Frameworks"` | same | — unchanged |
| `PRODUCT_BUNDLE_IDENTIFIER` | `com.evan.lsattracker` | `com.evan.russiantracker` | — **keep LSAT's**, per the map's rename rule |

The `INFOPLIST_KEY_*` block is **byte-for-byte identical** on both sides — all ten keys
(`NSSupportsLiveActivities`, the four `[sdk=iphoneos*]`/`[sdk=iphonesimulator*]` pairs for
`UIApplicationSceneManifest_Generation`, `UIApplicationSupportsIndirectInputEvents`,
`UILaunchScreen_Generation`, `UIStatusBarStyle`, plus the two
`UISupportedInterfaceOrientations_*` strings). **No change needed.** Note that Russian Tracker did
*not* add any macOS-specific `INFOPLIST_KEY_*` — the macOS-only keys live in the `Info.plist` file
instead (§4).

### 1.2 Widget extension — `LSAT Timer WidgetExtension` (`FA7311262F52A42600E4A16C`)

Configs `FA73113C2F52A42700E4A16C` (Debug) and `FA73113D2F52A42700E4A16C` (Release). **This is the
heaviest part of the diff** — LSAT's widget is currently iOS-only.

| Setting | LSAT now | Russian | Action |
|---|---|---|---|
| `SDKROOT` | `iphoneos` | `auto` | **Change** to `auto` — the single most important edit |
| `SUPPORTED_PLATFORMS` | *(absent)* | `"iphoneos iphonesimulator macosx"` | **Add** |
| `MACOSX_DEPLOYMENT_TARGET` | *(absent)* | `15.0` | **Add** |
| `IPHONEOS_DEPLOYMENT_TARGET` | `17.6` | `17.6` | — unchanged |
| `"CODE_SIGN_ENTITLEMENTS[sdk=macosx*]"` | *(absent)* | `"Russian Timer WidgetExtension.macOS.entitlements"` | **Add** as `"LSAT Timer WidgetExtension.macOS.entitlements"` |
| `"LD_RUNPATH_SEARCH_PATHS[sdk=macosx*]"` | *(absent)* | see below | **Add** |
| `CODE_SIGN_ENTITLEMENTS` | `"LSAT Timer WidgetExtension.entitlements"` | Russian equivalent | — keep LSAT path |
| `PRODUCT_BUNDLE_IDENTIFIER` | `com.evan.lsattracker.widget` | `com.evan.russiantracker.widget` | — keep LSAT's |
| `TARGETED_DEVICE_FAMILY` | `"1,2"` | `"1,2"` | — unchanged (widget was never visionOS) |
| `SKIP_INSTALL`, `VALIDATE_PRODUCT` (Release), `STRING_CATALOG_GENERATE_SYMBOLS`, `ASSETCATALOG_COMPILER_*`, `GENERATE_INFOPLIST_FILE`, `INFOPLIST_FILE`, `INFOPLIST_KEY_CFBundleDisplayName`, `INFOPLIST_KEY_NSHumanReadableCopyright`, `DEVELOPMENT_TEAM`, `CODE_SIGN_IDENTITY`, `CODE_SIGN_STYLE`, `CURRENT_PROJECT_VERSION`, `MARKETING_VERSION`, `SWIFT_*` | — | — | — all identical, no change |

The macOS runpath addition, verbatim from Russian Tracker (both configs):

```
"LD_RUNPATH_SEARCH_PATHS[sdk=macosx*]" = (
    "$(inherited)",
    "@executable_path/../Frameworks",
    "@executable_path/../../../../Frameworks",
);
```

The existing non-macOS `LD_RUNPATH_SEARCH_PATHS` array is unchanged on both sides:

```
LD_RUNPATH_SEARCH_PATHS = (
    "$(inherited)",
    "@executable_path/Frameworks",
    "@executable_path/../../Frameworks",
);
```

Russian Tracker's plan records the intent behind this block directly:

> the widget extension now builds for `iphoneos iphonesimulator macosx` (`SDKROOT = auto`, own
> `Russian Timer WidgetExtension.macOS.entitlements` with sandbox + App Group); the ActivityKit
> link and the whole Live Activity file are iOS-only
>
> — `docs/plans/2026-09-05-mac-app-and-sync.md`, line 130

### 1.3 `LSAT TrackerTests` (`FAA686E72F52427B00481D93`)

Configs `FAA687002F52427B00481D93` / `FAA687012F52427B00481D93`.

| Setting | LSAT now | Russian | Action |
|---|---|---|---|
| `SUPPORTED_PLATFORMS` | `"iphoneos iphonesimulator macosx xros xrsimulator"` | `"iphoneos iphonesimulator macosx"` | **Change** — drop xros |
| `TARGETED_DEVICE_FAMILY` | `"1,2,7"` | `"1,2"` | **Change** |
| `XROS_DEPLOYMENT_TARGET` | `26.2` | *(absent)* | **Delete** |
| `IPHONEOS_DEPLOYMENT_TARGET` | `26.2` | `26.2` | — unchanged |
| `MACOSX_DEPLOYMENT_TARGET` | `15.7` | `15.7` | — unchanged (note: *higher* than the app's 15.0; matches Russian, leave it) |
| `SDKROOT` | `auto` | `auto` | — unchanged |
| `TEST_HOST` | `"$(BUILT_PRODUCTS_DIR)/LSAT Tracker.app/$(BUNDLE_EXECUTABLE_FOLDER_PATH)/LSAT Tracker"` | Russian equivalent | — keep LSAT's |
| `PRODUCT_BUNDLE_IDENTIFIER` | `"Evan.LSAT-TrackerTests"` | `"Evan.Russian-TrackerTests"` | — keep LSAT's |

### 1.4 `LSAT TrackerUITests` (`FAA686F12F52427B00481D93`)

Configs `FAA687032F52427B00481D93` / `FAA687042F52427B00481D93`. Identical treatment to §1.3:
drop `xros xrsimulator` from `SUPPORTED_PLATFORMS`, `TARGETED_DEVICE_FAMILY` `"1,2,7"` → `"1,2"`,
delete `XROS_DEPLOYMENT_TARGET = 26.2`. `TEST_TARGET_NAME = "LSAT Tracker"` stays.

### 1.5 Two judgement calls flagged, not silently applied

Neither is a Study-Types or CloudKit artefact; both are cases where LSAT is currently *ahead of* or
*behind* Russian for unrelated reasons, so #6 should decide deliberately.

1. **Dropping visionOS.** LSAT currently declares `xros xrsimulator` + device family `7` +
   `XROS_DEPLOYMENT_TARGET = 26.2` on three targets; Russian Tracker never had them. Dropping them
   is what "feature-identical twin" implies and removes a platform nobody is testing, but it *is* a
   capability reduction rather than a port requirement. If #6 would rather keep visionOS, the only
   consequence is that `SUPPORTED_PLATFORMS` keeps two extra values — nothing else in this document
   depends on it. **Recommendation: drop, matching Russian.**
2. **`MACOSX_DEPLOYMENT_TARGET` 15.6 → 15.0 on the app target.** Lowering it widens macOS support
   and matches Russian exactly. Russian's plan notes Control Center controls are gated at runtime
   with `if #available(iOS 18.0, macOS 26.0, *)` rather than by the deployment target, so 15.0 is
   safe (`docs/plans/2026-09-05-mac-app-and-sync.md`, line 130). **Recommendation: set 15.0.**

---

## 2. Swift Package Manager references

LSAT Tracker currently has **no SPM packages at all** — it has no `packageReferences` key in the
`PBXProject`, no `XCRemoteSwiftPackageReference` section, and no `XCSwiftPackageProductDependency`
section. All five objects below must be added.

### 2.1 Package references (new `XCRemoteSwiftPackageReference` section)

Verbatim from Russian Tracker, lines 859–876:

```
/* Begin XCRemoteSwiftPackageReference section */
		KS0000000000000000000003 /* XCRemoteSwiftPackageReference "KeyboardShortcuts" */ = {
			isa = XCRemoteSwiftPackageReference;
			repositoryURL = "https://github.com/sindresorhus/KeyboardShortcuts";
			requirement = {
				kind = upToNextMajorVersion;
				minimumVersion = 2.0.0;
			};
		};
		SB0000000000000000000003 /* XCRemoteSwiftPackageReference "supabase-swift" */ = {
			isa = XCRemoteSwiftPackageReference;
			repositoryURL = "https://github.com/supabase/supabase-swift";
			requirement = {
				kind = upToNextMajorVersion;
				minimumVersion = 2.0.0;
			};
		};
/* End XCRemoteSwiftPackageReference section */
```

Exact values to reproduce:

| Package | `repositoryURL` | `kind` | `minimumVersion` |
|---|---|---|---|
| KeyboardShortcuts | `https://github.com/sindresorhus/KeyboardShortcuts` | `upToNextMajorVersion` | `2.0.0` |
| supabase-swift | `https://github.com/supabase/supabase-swift` | `upToNextMajorVersion` | `2.0.0` |

Note the hand-written placeholder UUIDs (`KS000…0003`, `SB000…0003`). Xcode accepts these and will
keep them; they were evidently written by hand rather than generated. Reuse them verbatim so the
two projects stay diffable.

### 2.2 Product dependencies (new `XCSwiftPackageProductDependency` section)

```
/* Begin XCSwiftPackageProductDependency section */
		KS0000000000000000000002 /* KeyboardShortcuts */ = {
			isa = XCSwiftPackageProductDependency;
			package = KS0000000000000000000003 /* XCRemoteSwiftPackageReference "KeyboardShortcuts" */;
			productName = KeyboardShortcuts;
		};
		SB0000000000000000000002 /* Supabase */ = {
			isa = XCSwiftPackageProductDependency;
			package = SB0000000000000000000003 /* XCRemoteSwiftPackageReference "supabase-swift" */;
			productName = Supabase;
		};
/* End XCSwiftPackageProductDependency section */
```

### 2.3 Which target links which product

**Only the app target links anything.** The widget extension's `packageProductDependencies` is
empty `()` in Russian Tracker, and its `Frameworks` phase (`FA7311242F52A42600E4A16C`) contains only
the three system frameworks. Do not add Supabase or KeyboardShortcuts to the widget.

Add to the app target `FAA686DA2F52427900481D93`, replacing its empty `packageProductDependencies = ()`:

```
			packageProductDependencies = (
				KS0000000000000000000002 /* KeyboardShortcuts */,
				SB0000000000000000000002 /* Supabase */,
			);
```

Add to the `PBXProject` object `FAA686D32F52427900481D93`, between `minimizedProjectReferenceProxies`
and `preferredProjectObjectVersion` (Xcode's alphabetical ordering):

```
			packageReferences = (
				KS0000000000000000000003 /* XCRemoteSwiftPackageReference "KeyboardShortcuts" */,
				SB0000000000000000000003 /* XCRemoteSwiftPackageReference "supabase-swift" */,
			);
```

Add to the app's `PBXFrameworksBuildPhase` `FAA686D82F52427900481D93` (currently `files = ()`):

```
			files = (
				KS0000000000000000000001 /* KeyboardShortcuts in Frameworks */,
				SB0000000000000000000001 /* Supabase in Frameworks */,
			);
```

And the two matching `PBXBuildFile` entries (§2.4).

### 2.4 `PBXBuildFile` entries and the platform filter on KeyboardShortcuts

Russian Tracker, lines 14–15:

```
		KS0000000000000000000001 /* KeyboardShortcuts in Frameworks */ = {isa = PBXBuildFile; platformFilters = (macos, ); productRef = KS0000000000000000000002 /* KeyboardShortcuts */; };
		SB0000000000000000000001 /* Supabase in Frameworks */ = {isa = PBXBuildFile; productRef = SB0000000000000000000002 /* Supabase */; };
```

Two things to carry across exactly:

- **KeyboardShortcuts carries `platformFilters = (macos, )`.** It links on macOS only. KeyboardShortcuts is a global-hotkey library with no iOS story; linking it on iOS would break the iOS build. This filter is load-bearing.
- **Supabase carries no filter.** It links on every platform, because sync runs on both iOS and macOS.

---

## 3. Entitlements files

### 3.1 What exists on each side

| File | Russian Tracker | LSAT Tracker |
|---|---|---|
| App, iOS | `Russian Tracker/Russian Tracker.entitlements` | `LSAT Tracker/LSAT Tracker.entitlements` ✅ exists |
| App, macOS | `Russian Tracker/Russian Tracker.macOS.entitlements` | ❌ **missing — create** |
| Widget, iOS | `Russian Timer WidgetExtension.entitlements` (repo root) | `LSAT Timer WidgetExtension.entitlements` (repo root) ✅ exists |
| Widget, macOS | `Russian Timer WidgetExtension.macOS.entitlements` (repo root) | ❌ **missing — create** |

### 3.2 App Group id

Russian Tracker uses `group.evan.russiantimer` in all four of its entitlements files. LSAT Tracker
uses `group.evan.lsattimer` in both of its existing ones. Per the map's standing rule, **the App
Group stays `group.evan.lsattimer`** — the two new macOS files use the LSAT id, not a renamed
Russian one. Every entitlements file on both sides uses the plain, un-prefixed `group.` form; no
team prefix (`3LYN963K9A.`) appears anywhere.

### 3.3 Existing iOS files — no change required

`LSAT Tracker/LSAT Tracker.entitlements` and `LSAT Timer WidgetExtension.entitlements` are both
already structurally identical to their Russian counterparts (a single
`com.apple.security.application-groups` array, one entry), differing only in the group id — which
is meant to differ. **Leave both files exactly as they are.**

### 3.4 New file: `LSAT Tracker/LSAT Tracker.macOS.entitlements`

Russian's version, with the group id swapped:

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>com.apple.security.app-sandbox</key>
	<true/>
	<key>com.apple.security.files.user-selected.read-only</key>
	<true/>
	<key>com.apple.security.network.client</key>
	<true/>
	<key>com.apple.security.application-groups</key>
	<array>
		<string>group.evan.lsattimer</string>
	</array>
</dict>
</plist>
```

Why each key is here, and whether it carries across:

| Key | Reason | Carry across? |
|---|---|---|
| `com.apple.security.app-sandbox` | `ENABLE_APP_SANDBOX = YES` is already set on both sides; a sandboxed Mac app must declare it | **Yes** |
| `com.apple.security.network.client` | Supabase sync makes outbound HTTPS calls; a sandboxed Mac app cannot open sockets without it | **Yes** — Supabase is in scope for this port |
| `com.apple.security.files.user-selected.read-only` | Pairs with `ENABLE_USER_SELECTED_FILES = readonly`, already set identically on both sides | **Yes** |
| `com.apple.security.application-groups` | Shared `UserDefaults` suite between app and widget | **Yes**, with `group.evan.lsattimer` |

### 3.5 New file: `LSAT Timer WidgetExtension.macOS.entitlements` (repo root)

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>com.apple.security.app-sandbox</key>
	<true/>
	<key>com.apple.security.application-groups</key>
	<array>
		<string>group.evan.lsattimer</string>
	</array>
</dict>
</plist>
```

Sandbox + App Group only — the widget makes no network calls of its own and touches no user-selected
files.

### 3.6 New `PBXFileReference` entries and group membership

Russian declares its two root-level widget entitlements files as file references and lists them as
children of the main group. LSAT declares only the iOS one. Add the macOS sibling:

```
		FA7311432F52A4E000E4A16C /* LSAT Timer WidgetExtension.macOS.entitlements */ = {isa = PBXFileReference; lastKnownFileType = text.plist.entitlements; path = "LSAT Timer WidgetExtension.macOS.entitlements"; sourceTree = "<group>"; };
```

and add `FA7311432F52A4E000E4A16C` to the `children` of main group `FAA686D22F52427900481D93`,
immediately after the existing `FA7311422F52A4E000E4A16C` entry — matching Russian's ordering.

The two app-target entitlements files need no `PBXFileReference`: they live inside the
`PBXFileSystemSynchronizedRootGroup` `LSAT Tracker` and are picked up automatically.

### 3.7 Open question this document cannot close

The map's "Not yet specified" list flags whether a sandboxed Mac app needs a team-prefixed App Group
id. Russian Tracker shipped the plain `group.` form in all four files, which is evidence — but not
proof — that the plain form is accepted. Russian's own plan leaves the same door open:

> App Group on macOS: sandboxed Mac apps historically require a team-prefixed group id. Xcode 16+
> accepts `group.*` for macOS with a provisioning profile. Build once on macOS with signing on; if
> the entitlement is rejected, add `3LYN963K9A.group.evan.russiantimer` as a second group for the
> Mac targets and key the suite name by platform
>
> — `docs/plans/2026-09-05-mac-app-and-sync.md`, line 46

**Only a signed macOS build answers this.** Start with the plain form as written above; if signing
rejects it, add `3LYN963K9A.group.evan.lsattimer` as a *second* array entry in the two macOS files
and key the suite name by platform in `LSATTimerAttributes.swift`.

---

## 4. `Info.plist` differences

Both widget `Info.plist` files (`LSAT Timer Widget/Info.plist`, `Russian Timer Widget/Info.plist`)
are **byte-for-byte identical** — a single `NSExtension` dict with
`NSExtensionPointIdentifier = com.apple.widgetkit-extension`. No change.

The app-level plists differ by exactly **one key**:

| Key | `Russian-Tracker-Info.plist` | `LSAT-Tracker-Info.plist` | Action |
|---|---|---|---|
| `LSUIElement` | `<true/>` | *(absent)* | **Add** |
| `NSExtensionPointerIdentifier` | `com.apple.widgetkit-extension` | same | — |
| `NSSupportsLiveActivities` | `<true/>` | same | — |
| `NSServices` | one-element array, empty `NSMenuItem` dict + empty `NSMessage` string | same | — |

Add to `LSAT-Tracker-Info.plist`, as the first key in the dict (matching Russian's ordering):

```xml
	<key>LSUIElement</key>
	<true/>
```

**`LSUIElement` goes in the shared plist, not behind an `INFOPLIST_KEY_*[sdk=macosx*]` condition.**
That looks wrong at first glance but is correct: `LSUIElement` is a macOS-only Launch Services key
and is simply ignored on iOS, which is why Russian Tracker put it in the common file rather than
splitting the plist per platform. Do the same.

What it does — the reason it is the menu-bar-agent switch named in the map's destination:

> `Info.plist`: `LSUIElement = YES` for macOS. An `AppDelegate` (`NSApplicationDelegateAdaptor`)
> switches `NSApp.setActivationPolicy(.regular)` when the main window opens and `.accessory` when it
> closes. Closing the window never quits.
>
> — `docs/plans/2026-09-05-mac-app-and-sync.md`, line 87

Setting `LSUIElement` alone gives a Dock-less agent. The accompanying `AppDelegate` activation-policy
code is a **code** change and belongs to a different ticket, not to the pbxproj edit — but the two
must land together or the Mac app will have no way to show a window.

---

## 5. `membershipExceptions`

The widget extension pulls source out of the app's synchronized folder via
`PBXFileSystemSynchronizedBuildFileExceptionSet` `FA284E1E2F54DD4E00726B60`.

**LSAT Tracker today (3 entries):**

```
			membershipExceptions = (
				Models/LSATTimerAttributes.swift,
				Models/ToggleTimerIntent.swift,
				Theme.swift,
			);
```

**Russian Tracker (5 entries):**

```
			membershipExceptions = (
				Models/ClockSnapshot.swift,
				Models/RussianTimerAttributes.swift,
				Models/ToggleTimerIntent.swift,
				Theme.swift,
				Views/Shared/SharedWidgetViews.swift,
			);
```

**Target state for LSAT Tracker — add two entries, keeping the list alphabetically sorted as Xcode writes it:**

```
			membershipExceptions = (
				Models/ClockSnapshot.swift,
				Models/LSATTimerAttributes.swift,
				Models/ToggleTimerIntent.swift,
				Theme.swift,
				Views/Shared/SharedWidgetViews.swift,
			);
```

This matches the map's standing rule verbatim — widget-visible code must live in one of
`Models/LSATTimerAttributes.swift`, `Models/ToggleTimerIntent.swift`, `Models/ClockSnapshot.swift`,
`Theme.swift`, `Views/Shared/SharedWidgetViews.swift`.

**Ordering caveat:** the sort is by path string, so `Models/ClockSnapshot.swift` sorts before
`Models/LSATTimerAttributes.swift` — the reverse of Russian's `ClockSnapshot` / `RussianTimerAttributes`
ordering, which happens to be the same relative order. No trap here, but do not blind-copy Russian's
lines.

**Sequencing:** neither `LSAT Tracker/Models/ClockSnapshot.swift` nor
`LSAT Tracker/Views/Shared/SharedWidgetViews.swift` exists in this repo yet (`Views/Shared/` is not
even a directory). Adding a `membershipException` for a nonexistent path will fail the build.
**#6 must either land after the tickets that create those two files, or create them as stubs.**

The second exception set `FA73113A2F52A42700E4A16C` (`Info.plist` in the widget folder) is identical
on both sides. No change.

### 5.1 Study Types live inside these files, not in the pbxproj

Worth stating plainly because it is the easiest way to accidentally import Study Types: the
`membershipExceptions` *list* is clean, but four of the five files it names are heavily
Study-Type-contaminated in Russian Tracker. Occurrence counts for
`StudyType|dailyByType|StudyTypeDots|SetStudyMode`:

| File | Matches in Russian Tracker |
|---|---|
| `Models/ClockSnapshot.swift` | 18 |
| `Models/RussianTimerAttributes.swift` | 7 |
| `Models/ToggleTimerIntent.swift` | 5 |
| `Views/Shared/SharedWidgetViews.swift` | 4 |
| `Theme.swift` | 1 |

The pbxproj edit is safe to make as written. The stripping happens in the file-porting tickets —
this note exists only so #6 does not treat "the exception list matches Russian" as meaning the
widget's shared code matches Russian.

---

## 6. `platformFilters` on the widget embed and the target dependency

**Finding: there are none, on either side. This part of the ticket's premise does not hold.**

The ticket asks for "the `membershipExceptions` lists and the `platformFilters` on the widget embed
/ target dependency". Having read both files: the widget embed `PBXBuildFile` and the widget
`PBXTargetDependency` carry **no platform filter in either project**, and the two objects are
character-for-character identical across the repos apart from the product name.

Widget embed `PBXBuildFile` — identical both sides (Russian line 13, LSAT line 13):

```
		FA7311392F52A42700E4A16C /* … Timer WidgetExtension.appex in Embed Foundation Extensions */ = {isa = PBXBuildFile; fileRef = FA7311272F52A42600E4A16C /* … */; settings = {ATTRIBUTES = (RemoveHeadersOnCopy, ); }; };
```

Widget `PBXTargetDependency` `FA7311382F52A42700E4A16C` — identical both sides, `target` +
`targetProxy` only, no `platformFilters` key. The `PBXCopyFilesBuildPhase`
`FA73113E2F52A42700E4A16C` (`dstSubfolderSpec = 13`) is identical too.

**Action: no change.** The widget embeds and the dependency applies on every platform, which is
correct — the widget extension builds for macOS as well once §1.2 lands.

### 6.1 The platform filter that *does* differ — `ActivityKit.framework`

The real filter delta is elsewhere, and it matters. Russian Tracker line 10 vs LSAT line 10:

```diff
-		FA284E212F54EE7D00726B60 /* ActivityKit.framework in Frameworks */ = {isa = PBXBuildFile; fileRef = FA284E202F54EE7D00726B60 /* ActivityKit.framework */; settings = {ATTRIBUTES = (Weak, ); }; };
+		FA284E212F54EE7D00726B60 /* ActivityKit.framework in Frameworks */ = {isa = PBXBuildFile; fileRef = FA284E202F54EE7D00726B60 /* ActivityKit.framework */; platformFilter = ios; settings = {ATTRIBUTES = (Weak, ); }; };
```

**Add `platformFilter = ios;` to the widget's ActivityKit link.** Note the singular key
`platformFilter` (one value) versus the plural `platformFilters = (macos, )` on KeyboardShortcuts —
both spellings are valid pbxproj and Russian uses each in its correct place; reproduce them exactly.

This is mandatory once §1.2 makes the widget build for macOS. The `PBXFileReference`
`FA284E202F54EE7D00726B60` is an absolute-ish `DEVELOPER_DIR` path into the **iPhoneOS** SDK:

```
path = Platforms/iPhoneOS.platform/Developer/SDKs/iPhoneOS26.2.sdk/System/Library/Frameworks/ActivityKit.framework;
```

Without the filter, a macOS build of the widget tries to link an iPhoneOS framework and fails. The
`ATTRIBUTES = (Weak, )` setting is present on both sides and stays. The corresponding Swift-side
work (`#if os(iOS)` around every ActivityKit import and the whole Live Activity file) is a code
ticket, per Russian's plan line 120.

`WidgetKit.framework` and `SwiftUI.framework` are unfiltered on both sides and stay unfiltered —
both exist on macOS.

---

## 7. The shared scheme's test action

Both repos ship two shared schemes with matching structure. The widget extension scheme
(`… Timer WidgetExtension.xcscheme`) is **identical on both sides** apart from names — same
`wasCreatedForAppExtension = "YES"`, same `version = "2.0"`, same `RemoteRunnable` against
`com.apple.springboard`, same three `_XCWidget*` environment variables. Its `TestAction` is empty in
both. **No change.**

The app scheme differs in exactly one place — **`LSAT Tracker.xcscheme`'s `TestAction` has no
`Testables` block at all**, so the unit-test target is never run by the shared scheme.

LSAT Tracker today:

```xml
   <TestAction
      buildConfiguration = "Debug"
      selectedDebuggerIdentifier = "Xcode.DebuggerFoundation.Debugger.LLDB"
      selectedLauncherIdentifier = "Xcode.DebuggerFoundation.Launcher.LLDB"
      shouldUseLaunchSchemeArgsEnv = "YES"
      shouldAutocreateTestPlan = "YES">
   </TestAction>
```

Russian Tracker — same five attributes, plus the `Testables` block:

```xml
      <Testables>
         <TestableReference
            skipped = "NO"
            parallelizable = "YES">
            <BuildableReference
               BuildableIdentifier = "primary"
               BlueprintIdentifier = "FAA686E72F52427B00481D93"
               BuildableName = "Russian TrackerTests.xctest"
               BlueprintName = "Russian TrackerTests"
               ReferencedContainer = "container:Russian Tracker.xcodeproj">
            </BuildableReference>
         </TestableReference>
      </Testables>
```

**Insert into `LSAT Tracker.xcodeproj/xcshareddata/xcschemes/LSAT Tracker.xcscheme`**, between the
`TestAction` open and close tags:

```xml
      <Testables>
         <TestableReference
            skipped = "NO"
            parallelizable = "YES">
            <BuildableReference
               BuildableIdentifier = "primary"
               BlueprintIdentifier = "FAA686E72F52427B00481D93"
               BuildableName = "LSAT TrackerTests.xctest"
               BlueprintName = "LSAT TrackerTests"
               ReferencedContainer = "container:LSAT Tracker.xcodeproj">
            </BuildableReference>
         </TestableReference>
      </Testables>
```

`BlueprintIdentifier` is unchanged (`FAA686E72F52427B00481D93` is the Tests target in both projects);
only the three name strings change. Note Russian includes **only** `…TrackerTests`, not
`…TrackerUITests`, in its test action — match that.

The rest of the app scheme (`version = "1.7"`, `LastUpgradeVersion = "2620"`, BuildAction,
LaunchAction, ProfileAction, AnalyzeAction, ArchiveAction) is identical on both sides. No change.

---

## 8. Settings that exist only because of Study Types or CloudKit

**The ticket's central question. Answer: none — the pbxproj is clean on both counts.**

### CloudKit

A case-insensitive search for `icloud|cloudkit|ubiquit` across Russian Tracker's `project.pbxproj`
and all four of its entitlements files returns **zero matches**. There is no
`com.apple.developer.icloud-container-identifiers`, no
`com.apple.developer.icloud-services`, no `RT_CLOUDKIT` build setting, no CloudKit framework link,
and no CloudKit-conditioned entitlements variant.

This is consistent with Russian Tracker's ADR 0003 having removed CloudKit outright rather than
disabling it. Its plan still carries the historical note —

> iCloud needs the paid developer program. The project team (3LYN963K9A) is a personal team, so
> `RT_CLOUDKIT = NO` selects local-only entitlements until enrolment
>
> — `docs/plans/2026-09-05-mac-app-and-sync.md`, line 30

— and line 149 of the same plan still lists the entitlements files as covering "iCloud, app groups",
but **both are stale**: the mechanism they describe is gone from the shipped project. Do not
resurrect `RT_CLOUDKIT`, an `LT_CLOUDKIT`, or any conditioned-entitlements scheme when porting. If
#6 finds itself adding a build setting to switch entitlements variants, that is the CloudKit ghost
and should be dropped.

**One adjacent setting that is *not* a CloudKit artefact and must be carried:**
`com.apple.security.network.client` in the macOS entitlements (§3.4). It looks like sync
infrastructure and it is — but it is *Supabase* sync, which is explicitly in scope for this port.
Dropping it would break sync on macOS silently, with the failure surfacing only as network errors
inside the sandbox.

### Study Types

No build setting, entitlement, plist key, scheme entry, SPM reference, platform filter, or
`membershipExceptions` entry in Russian Tracker's project file encodes the Study Type dimension.
The `StudyType` concept lives entirely in Swift source — see §5.1 for where it is concentrated and
why that still matters to #6's sequencing.

The one name that might look Study-Type-shaped is `Models/ClockSnapshot.swift` in
`membershipExceptions`. It is not: `ClockSnapshot` is the shared-clock type from ADR 0001, the
foundation of cross-device sync, and is required. Its *contents* carry 18 Study-Type references that
the file-porting ticket must strip, but the pbxproj entry itself is correct as written.

### Not a Study-Types or CloudKit artefact, but still a deliberate decision

The visionOS removal and the `MACOSX_DEPLOYMENT_TARGET` change in §1.5 are neither — they are
independent divergences between the two projects. They are flagged there rather than here so they
are not waved through on "Russian doesn't have it" grounds.

---

## 9. Condensed checklist for #6

Every item is mechanical and sourced above.

**`project.pbxproj`**

- [ ] App target, both configs: `SUPPORTED_PLATFORMS` → `"iphoneos iphonesimulator macosx"`; `TARGETED_DEVICE_FAMILY` → `"1,2"`; delete `XROS_DEPLOYMENT_TARGET`; `MACOSX_DEPLOYMENT_TARGET` → `15.0`
- [ ] App target, both configs: add `"CODE_SIGN_ENTITLEMENTS[sdk=macosx*]" = "LSAT Tracker/LSAT Tracker.macOS.entitlements";`
- [ ] Widget target, both configs: `SDKROOT` → `auto`; add `SUPPORTED_PLATFORMS = "iphoneos iphonesimulator macosx";`, `MACOSX_DEPLOYMENT_TARGET = 15.0;`, the macOS `LD_RUNPATH_SEARCH_PATHS` array, and `"CODE_SIGN_ENTITLEMENTS[sdk=macosx*]" = "LSAT Timer WidgetExtension.macOS.entitlements";`
- [ ] Tests + UITests targets, all four configs: drop `xros xrsimulator`, `TARGETED_DEVICE_FAMILY` → `"1,2"`, delete `XROS_DEPLOYMENT_TARGET`
- [ ] Add `platformFilter = ios;` to the ActivityKit `PBXBuildFile` `FA284E212F54EE7D00726B60`
- [ ] Add the `XCRemoteSwiftPackageReference` and `XCSwiftPackageProductDependency` sections (§2.1, §2.2)
- [ ] Add `packageReferences` to the `PBXProject`; `packageProductDependencies` to the app target; two `PBXBuildFile`s (KeyboardShortcuts with `platformFilters = (macos, )`); populate the app's `Frameworks` phase
- [ ] Extend `membershipExceptions` to five entries (§5) — **after** `ClockSnapshot.swift` and `SharedWidgetViews.swift` exist
- [ ] Add the `PBXFileReference` for `LSAT Timer WidgetExtension.macOS.entitlements` and list it in main group `FAA686D22F52427900481D93`

**Files**

- [ ] Create `LSAT Tracker/LSAT Tracker.macOS.entitlements` (§3.4)
- [ ] Create `LSAT Timer WidgetExtension.macOS.entitlements` at repo root (§3.5)
- [ ] Add `LSUIElement = true` to `LSAT-Tracker-Info.plist` (§4)
- [ ] Add the `Testables` block to `LSAT Tracker.xcscheme` (§7)

**Do not**

- [ ] Do not add any CloudKit/iCloud entitlement, framework, or `*_CLOUDKIT` build setting (§8)
- [ ] Do not link Supabase or KeyboardShortcuts into the widget extension (§2.3)
- [ ] Do not add a `platformFilter` to the widget embed or the widget target dependency (§6)
- [ ] Do not rename the App Group away from `group.evan.lsattimer` (§3.2)
- [ ] Do not touch the project-level `Debug`/`Release` configs `FAA686FA…` / `FAA686FB…` (§0)
