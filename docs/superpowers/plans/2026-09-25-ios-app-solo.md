# iOS App Solo (Playable Single-Player) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build a minimal but complete and playable single-player Knuckled iOS app (Xcode project + SwiftUI) reusing the `KnuckledCore` engine, installable and tappable in the Simulator: start screen with name entry, full game screen (two boards, 2D die, turn pill, result overlays, play-again, leave flow), CPU opponent over an in-memory link — no Bluetooth, no 3D die, no sound, no settings yet (those are the follow-up parity plan).

**Architecture:** New `Knuckled.xcodeproj` at the repo root with three targets (`Knuckled` app, `KnuckledTests` hosted unit tests, `KnuckledUITests` XCUITest smoke) plus a local SwiftPM dependency on the existing `KnuckledCore` package. A `GameSession` ObservableObject owns one solo session (`GameHost` + `runCpuClient` over `InMemoryLinkPair`, main-thread state publishing); SwiftUI views render `GameState` exactly like the Android screens (peer board top, own board bottom). Verification is `xcodebuild build` + `xcodebuild test` (unit + UI tests in Simulator) + simctl install/launch/screenshot.

**Tech Stack:** Swift 5 language mode (`SWIFT_VERSION = 5.0`), SwiftUI, Combine (`@Published`), XCTest + XCUITest, iOS 17.0+, iPhone + iPad (universal, all orientations), `xcodebuild`/`xcrun simctl` from the CLI with `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer`.

**Reference:** Android original at `/Users/robison/AndroidStudioProjects/KnuckleGame` (`ui/KnuckledApp.kt`, `ui/ConnectionScreens.kt`, `ui/GameScreen.kt`, `ui/ColumnDisplay.kt`, `ui/components/`, `ui/GameViewModel.kt`, `ui/ConnectionViewModel.kt`, `game/LocalConnector.kt`, `game/CpuClient.kt`, `ui/theme/Color.kt`, `ui/theme/Type.kt`, `res/values/strings.xml`, `res/font/cinzel_bold.ttf`). Design spec: `docs/superpowers/specs/2026-09-24-crossplay-ios-design.md`.

**Environment rule (every task):** this machine's `xcode-select` points at CommandLineTools and `sudo` is unavailable. Prefix EVERY `xcodebuild`/`xcrun` invocation with `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer`, e.g. `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild -list`. Bare `xcodebuild` fails.

---

### Task 0: Environment preflight

**Files:** none (verification only)

- [ ] **Step 1: Verify Xcode + simulator runtime**

Run: `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcrun simctl list devices available | head -15`
Expected: a device list including `"iPhone 17"` (or similar) with a UDID and `(Shutdown)` state.

- [ ] **Step 2: Confirm repo base state**

Run: `git log --oneline -1 && ls Package.swift Sources/KnuckledCore/Game/GameHost.swift`
Expected: HEAD is `docs: close out iOS core plan ...` (or later main) and both paths exist.

---

### Task 1: Xcode project scaffold (project, scheme, Info.plist)

**Files:**
- Create: `Knuckled.xcodeproj/project.pbxproj`
- Create: `Knuckled.xcodeproj/xcshareddata/xcschemes/Knuckled.xcscheme`
- Create: `Knuckled/Info.plist`

This task creates ONLY the three project files (no Swift sources yet — the first build comes in Task 3 after sources land; here we verify the project *parses* and lists targets).

- [ ] **Step 1: Write `Knuckled.xcodeproj/project.pbxproj`**

Write the file EXACTLY as below. Object IDs are fixed 24-hex strings — transcribe them verbatim; cross-references must match (a single typo breaks the project). The project contains: app target `Knuckled`, hosted unit-test target `KnuckledTests`, XCUITest target `KnuckledUITests`, and a local package reference to `..` (the repo-root `KnuckledCore` package).

```pbxproj
// !$*UTF8*$!
{
	archiveVersion = 1;
	classes = {
	};
	objectVersion = 77;
	objects = {

/* Begin PBXBuildFile section */
		420000000000000000000001 /* KnuckledApp.swift in Sources */ = {isa = PBXBuildFile; fileRef = 410000000000000000000001 /* KnuckledApp.swift */; };
		420000000000000000000002 /* Theme.swift in Sources */ = {isa = PBXBuildFile; fileRef = 410000000000000000000002 /* Theme.swift */; };
		420000000000000000000003 /* StartScreen.swift in Sources */ = {isa = PBXBuildFile; fileRef = 410000000000000000000003 /* StartScreen.swift */; };
		420000000000000000000004 /* GameSession.swift in Sources */ = {isa = PBXBuildFile; fileRef = 410000000000000000000004 /* GameSession.swift */; };
		420000000000000000000005 /* GameScreen.swift in Sources */ = {isa = PBXBuildFile; fileRef = 410000000000000000000005 /* GameScreen.swift */; };
		420000000000000000000006 /* BoardViews.swift in Sources */ = {isa = PBXBuildFile; fileRef = 410000000000000000000006 /* BoardViews.swift */; };
		420000000000000000000007 /* DieView.swift in Sources */ = {isa = PBXBuildFile; fileRef = 410000000000000000000007 /* DieView.swift */; };
		420000000000000000000008 /* ResultOverlays.swift in Sources */ = {isa = PBXBuildFile; fileRef = 410000000000000000000008 /* ResultOverlays.swift */; };
		420000000000000000000009 /* CinzelBold.ttf in Resources */ = {isa = PBXBuildFile; fileRef = 410000000000000000000009 /* CinzelBold.ttf */; };
		420000000000000000000010 /* GameSessionTests.swift in Sources */ = {isa = PBXBuildFile; fileRef = 410000000000000000000010 /* GameSessionTests.swift */; };
		420000000000000000000011 /* ColumnDisplayTests.swift in Sources */ = {isa = PBXBuildFile; fileRef = 410000000000000000000011 /* ColumnDisplayTests.swift */; };
		420000000000000000000012 /* SoloSmokeTests.swift in Sources */ = {isa = PBXBuildFile; fileRef = 410000000000000000000012 /* SoloSmokeTests.swift */; };
		420000000000000000000013 /* KnuckledCore in Frameworks */ = {isa = PBXBuildFile; productRef = 450000000000000000000002 /* KnuckledCore */; };
		420000000000000000000014 /* KnuckledCore in Frameworks */ = {isa = PBXBuildFile; productRef = 450000000000000000000002 /* KnuckledCore */; };
/* End PBXBuildFile section */

/* Begin PBXFileReference section */
		410000000000000000000001 /* KnuckledApp.swift */ = {isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = KnuckledApp.swift; sourceTree = "<group>"; };
		410000000000000000000002 /* Theme.swift */ = {isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = Theme.swift; sourceTree = "<group>"; };
		410000000000000000000003 /* StartScreen.swift */ = {isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = StartScreen.swift; sourceTree = "<group>"; };
		410000000000000000000004 /* GameSession.swift */ = {isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = GameSession.swift; sourceTree = "<group>"; };
		410000000000000000000005 /* GameScreen.swift */ = {isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = GameScreen.swift; sourceTree = "<group>"; };
		410000000000000000000006 /* BoardViews.swift */ = {isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = BoardViews.swift; sourceTree = "<group>"; };
		410000000000000000000007 /* DieView.swift */ = {isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = DieView.swift; sourceTree = "<group>"; };
		410000000000000000000008 /* ResultOverlays.swift */ = {isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = ResultOverlays.swift; sourceTree = "<group>"; };
		410000000000000000000009 /* CinzelBold.ttf */ = {isa = PBXFileReference; lastKnownFileType = file; path = CinzelBold.ttf; sourceTree = "<group>"; };
		410000000000000000000010 /* GameSessionTests.swift */ = {isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = GameSessionTests.swift; sourceTree = "<group>"; };
		410000000000000000000011 /* ColumnDisplayTests.swift */ = {isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = ColumnDisplayTests.swift; sourceTree = "<group>"; };
		410000000000000000000012 /* SoloSmokeTests.swift */ = {isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = SoloSmokeTests.swift; sourceTree = "<group>"; };
		410000000000000000000013 /* Info.plist */ = {isa = PBXFileReference; lastKnownFileType = text.plist.xml; path = Info.plist; sourceTree = "<group>"; };
		410000000000000000000014 /* Knuckled.app */ = {isa = PBXFileReference; explicitFileType = wrapper.application; includeInIndex = 0; path = Knuckled.app; sourceTree = BUILT_PRODUCTS_DIR; };
		410000000000000000000015 /* KnuckledTests.xctest */ = {isa = PBXFileReference; explicitFileType = wrapper.cfbundle; includeInIndex = 0; path = KnuckledTests.xctest; sourceTree = BUILT_PRODUCTS_DIR; };
		410000000000000000000016 /* KnuckledUITests.xctest */ = {isa = PBXFileReference; explicitFileType = wrapper.cfbundle; includeInIndex = 0; path = KnuckledUITests.xctest; sourceTree = BUILT_PRODUCTS_DIR; };
/* End PBXFileReference section */

/* Begin PBXFrameworksBuildPhase section */
		430000000000000000000003 /* Frameworks */ = {
			isa = PBXFrameworksBuildPhase;
			buildActionMask = 2147483647;
			files = (
				420000000000000000000013 /* KnuckledCore in Frameworks */,
			);
			runOnlyForDeploymentPostprocessing = 0;
		};
		430000000000000000000006 /* Frameworks */ = {
			isa = PBXFrameworksBuildPhase;
			buildActionMask = 2147483647;
			files = (
				420000000000000000000014 /* KnuckledCore in Frameworks */,
			);
			runOnlyForDeploymentPostprocessing = 0;
		};
		430000000000000000000009 /* Frameworks */ = {
			isa = PBXFrameworksBuildPhase;
			buildActionMask = 2147483647;
			files = (
			);
			runOnlyForDeploymentPostprocessing = 0;
		};
/* End PBXFrameworksBuildPhase section */

/* Begin PBXGroup section */
		400000000000000000000001 = {
			isa = PBXGroup;
			children = (
				400000000000000000000002 /* Knuckled */,
				400000000000000000000003 /* KnuckledTests */,
				400000000000000000000004 /* KnuckledUITests */,
				400000000000000000000005 /* Products */,
			);
			sourceTree = "<group>";
		};
		400000000000000000000002 /* Knuckled */ = {
			isa = PBXGroup;
			children = (
				410000000000000000000001 /* KnuckledApp.swift */,
				410000000000000000000002 /* Theme.swift */,
				410000000000000000000003 /* StartScreen.swift */,
				410000000000000000000004 /* GameSession.swift */,
				410000000000000000000005 /* GameScreen.swift */,
				410000000000000000000006 /* BoardViews.swift */,
				410000000000000000000007 /* DieView.swift */,
				410000000000000000000008 /* ResultOverlays.swift */,
				410000000000000000000013 /* Info.plist */,
				400000000000000000000006 /* Resources */,
			);
			path = Knuckled;
			sourceTree = "<group>";
		};
		400000000000000000000003 /* KnuckledTests */ = {
			isa = PBXGroup;
			children = (
				410000000000000000000010 /* GameSessionTests.swift */,
				410000000000000000000011 /* ColumnDisplayTests.swift */,
			);
			path = KnuckledTests;
			sourceTree = "<group>";
		};
		400000000000000000000004 /* KnuckledUITests */ = {
			isa = PBXGroup;
			children = (
				410000000000000000000012 /* SoloSmokeTests.swift */,
			);
			path = KnuckledUITests;
			sourceTree = "<group>";
		};
		400000000000000000000005 /* Products */ = {
			isa = PBXGroup;
			children = (
				410000000000000000000014 /* Knuckled.app */,
				410000000000000000000015 /* KnuckledTests.xctest */,
				410000000000000000000016 /* KnuckledUITests.xctest */,
			);
			name = Products;
			sourceTree = "<group>";
		};
		400000000000000000000006 /* Resources */ = {
			isa = PBXGroup;
			children = (
				410000000000000000000009 /* CinzelBold.ttf */,
			);
			path = Resources;
			sourceTree = "<group>";
		};
/* End PBXGroup section */

/* Begin PBXNativeTarget section */
		200000000000000000000001 /* Knuckled */ = {
			isa = PBXNativeTarget;
			buildConfigurationList = 300000000000000000000002 /* Build configuration list for PBXNativeTarget "Knuckled" */;
			buildPhases = (
				430000000000000000000001 /* Sources */,
				430000000000000000000002 /* Resources */,
				430000000000000000000003 /* Frameworks */,
			);
			buildRules = (
			);
			dependencies = (
			);
			name = Knuckled;
			packageProductDependencies = (
				450000000000000000000002 /* KnuckledCore */,
			);
			productName = Knuckled;
			productReference = 410000000000000000000014 /* Knuckled.app */;
			productType = "com.apple.product-type.application";
		};
		200000000000000000000002 /* KnuckledTests */ = {
			isa = PBXNativeTarget;
			buildConfigurationList = 300000000000000000000003 /* Build configuration list for PBXNativeTarget "KnuckledTests" */;
			buildPhases = (
				430000000000000000000004 /* Sources */,
				430000000000000000000006 /* Frameworks */,
			);
			buildRules = (
			);
			dependencies = (
				440000000000000000000001 /* PBXTargetDependency */,
			);
			name = KnuckledTests;
			packageProductDependencies = (
				450000000000000000000002 /* KnuckledCore */,
			);
			productName = KnuckledTests;
			productReference = 410000000000000000000015 /* KnuckledTests.xctest */;
			productType = "com.apple.product-type.bundle.unit-test";
		};
		200000000000000000000003 /* KnuckledUITests */ = {
			isa = PBXNativeTarget;
			buildConfigurationList = 300000000000000000000004 /* Build configuration list for PBXNativeTarget "KnuckledUITests" */;
			buildPhases = (
				430000000000000000000007 /* Sources */,
				430000000000000000000009 /* Frameworks */,
			);
			buildRules = (
			);
			dependencies = (
				440000000000000000000002 /* PBXTargetDependency */,
			);
			name = KnuckledUITests;
			productName = KnuckledUITests;
			productReference = 410000000000000000000016 /* KnuckledUITests.xctest */;
			productType = "com.apple.product-type.bundle.ui-testing";
		};
/* End PBXNativeTarget section */

/* Begin PBXProject section */
		100000000000000000000001 /* Project object */ = {
			isa = PBXProject;
			attributes = {
				BuildIndependentTargetsInParallel = 1;
				LastSwiftUpdateCheck = 1700;
				TargetAttributes = {
					200000000000000000000001 /* Knuckled */ = {
						CreatedOnToolsVersion = 17.0;
					};
					200000000000000000000002 /* KnuckledTests */ = {
						CreatedOnToolsVersion = 17.0;
						TestTargetID = 200000000000000000000001 /* Knuckled */;
					};
					200000000000000000000003 /* KnuckledUITests */ = {
						CreatedOnToolsVersion = 17.0;
						TestTargetID = 200000000000000000000001 /* Knuckled */;
					};
				};
			};
			buildConfigurationList = 300000000000000000000001 /* Build configuration list for PBXProject "Knuckled" */;
			compatibilityVersion = "Xcode 16.0";
			developmentRegion = en;
			hasScannedForEncodings = 0;
			knownRegions = (
				en,
				Base,
			);
			mainGroup = 400000000000000000000001;
			packageReferences = (
				450000000000000000000001 /* XCRemoteSwiftPackageReference "KnuckledCore" */,
			);
			productRefGroup = 400000000000000000000005 /* Products */;
			projectDirPath = "";
			projectRoot = "";
			targets = (
				200000000000000000000001 /* Knuckled */,
				200000000000000000000002 /* KnuckledTests */,
				200000000000000000000003 /* KnuckledUITests */,
			);
		};
/* End PBXProject section */

/* Begin PBXResourcesBuildPhase section */
		430000000000000000000002 /* Resources */ = {
			isa = PBXResourcesBuildPhase;
			buildActionMask = 2147483647;
			files = (
				420000000000000000000009 /* CinzelBold.ttf in Resources */,
			);
			runOnlyForDeploymentPostprocessing = 0;
		};
/* End PBXResourcesBuildPhase section */

/* Begin PBXSourcesBuildPhase section */
		430000000000000000000001 /* Sources */ = {
			isa = PBXSourcesBuildPhase;
			buildActionMask = 2147483647;
			files = (
				420000000000000000000001 /* KnuckledApp.swift in Sources */,
				420000000000000000000002 /* Theme.swift in Sources */,
				420000000000000000000003 /* StartScreen.swift in Sources */,
				420000000000000000000004 /* GameSession.swift in Sources */,
				420000000000000000000005 /* GameScreen.swift in Sources */,
				420000000000000000000006 /* BoardViews.swift in Sources */,
				420000000000000000000007 /* DieView.swift in Sources */,
				420000000000000000000008 /* ResultOverlays.swift in Sources */,
			);
			runOnlyForDeploymentPostprocessing = 0;
		};
		430000000000000000000004 /* Sources */ = {
			isa = PBXSourcesBuildPhase;
			buildActionMask = 2147483647;
			files = (
				420000000000000000000010 /* GameSessionTests.swift in Sources */,
				420000000000000000000011 /* ColumnDisplayTests.swift in Sources */,
			);
			runOnlyForDeploymentPostprocessing = 0;
		};
		430000000000000000000007 /* Sources */ = {
			isa = PBXSourcesBuildPhase;
			buildActionMask = 2147483647;
			files = (
				420000000000000000000012 /* SoloSmokeTests.swift in Sources */,
			);
			runOnlyForDeploymentPostprocessing = 0;
		};
/* End PBXSourcesBuildPhase section */

/* Begin PBXTargetDependency section */
		440000000000000000000001 /* PBXTargetDependency */ = {
			isa = PBXTargetDependency;
			target = 200000000000000000000001 /* Knuckled */;
			targetProxy = 440000000000000000000003 /* PBXContainerItemProxy */;
		};
		440000000000000000000002 /* PBXTargetDependency */ = {
			isa = PBXTargetDependency;
			target = 200000000000000000000001 /* Knuckled */;
			targetProxy = 440000000000000000000004 /* PBXContainerItemProxy */;
		};
		440000000000000000000003 /* PBXContainerItemProxy */ = {
			isa = PBXContainerItemProxy;
			containerPortal = 100000000000000000000001 /* Project object */;
			proxyType = 1;
			remoteGlobalIDString = 200000000000000000000001;
			remoteInfo = Knuckled;
		};
		440000000000000000000004 /* PBXContainerItemProxy */ = {
			isa = PBXContainerItemProxy;
			containerPortal = 100000000000000000000001 /* Project object */;
			proxyType = 1;
			remoteGlobalIDString = 200000000000000000000001;
			remoteInfo = Knuckled;
		};
/* End PBXTargetDependency section */

/* Begin XCBuildConfiguration section */
		310000000000000000000001 /* Debug */ = {
			isa = XCBuildConfiguration;
			buildSettings = {
				ALWAYS_SEARCH_USER_PATHS = NO;
				CLANG_ANALYZER_NONNULL = YES;
				CLANG_ANALYZER_NUMBER_OBJECT_CONVERSION = YES_AGGRESSIVE;
				CLANG_CXX_LANGUAGE_STANDARD = "gnu++20";
				CLANG_ENABLE_MODULES = YES;
				CLANG_ENABLE_OBJC_ARC = YES;
				COPY_PHASE_STRIP = NO;
				DEBUG_INFORMATION_FORMAT = dwarf;
				ENABLE_STRICT_OBJCM_MSGSEND = YES;
				ENABLE_TESTABILITY = YES;
				ENABLE_USER_SCRIPT_SANDBOXING = NO;
				GCC_C_LANGUAGE_STANDARD = gnu17;
				GCC_DYNAMIC_NO_PIC = NO;
				GCC_OPTIMIZATION_LEVEL = 0;
				GCC_PREPROCESSOR_DEFINITIONS = (
					"DEBUG=1",
					"$(inherited)",
				);
				IPHONEOS_DEPLOYMENT_TARGET = 17.0;
				MTL_ENABLE_DEBUG_INFO = INCLUDE_SOURCE;
				MTL_FAST_MATH = YES;
				ONLY_ACTIVE_ARCH = YES;
				SDKROOT = iphoneos;
				SWIFT_ACTIVE_COMPILATION_CONDITIONS = DEBUG;
				SWIFT_OPTIMIZATION_LEVEL = "-Onone";
			};
			name = Debug;
		};
		310000000000000000000002 /* Release */ = {
			isa = XCBuildConfiguration;
			buildSettings = {
				ALWAYS_SEARCH_USER_PATHS = NO;
				CLANG_ANALYZER_NONNULL = YES;
				CLANG_ANALYZER_NUMBER_OBJECT_CONVERSION = YES_AGGRESSIVE;
				CLANG_CXX_LANGUAGE_STANDARD = "gnu++20";
				CLANG_ENABLE_MODULES = YES;
				CLANG_ENABLE_OBJC_ARC = YES;
				COPY_PHASE_STRIP = NO;
				DEBUG_INFORMATION_FORMAT = "dwarf-with-dsym";
				ENABLE_NS_ASSERTIONS = NO;
				ENABLE_STRICT_OBJCM_MSGSEND = YES;
				ENABLE_USER_SCRIPT_SANDBOXING = NO;
				GCC_C_LANGUAGE_STANDARD = gnu17;
				MTL_ENABLE_DEBUG_INFO = NO;
				MTL_FAST_MATH = YES;
				SDKROOT = iphoneos;
				SWIFT_COMPILATION_MODE = wholemodule;
				SWIFT_OPTIMIZATION_LEVEL = "-O";
			};
			name = Release;
		};
		310000000000000000000003 /* Debug */ = {
			isa = XCBuildConfiguration;
			buildSettings = {
				ASSETCATALOG_COMPILER_GENERATE_SWIFT_ASSET_SYMBOL_EXTENSIONS = YES;
				CODE_SIGN_STYLE = Automatic;
				CURRENT_PROJECT_VERSION = 1;
				GENERATE_INFOPLIST_FILE = NO;
				INFOPLIST_FILE = Knuckled/Info.plist;
				IPHONEOS_DEPLOYMENT_TARGET = 17.0;
				LD_RUNPATH_SEARCH_PATHS = (
					"$(inherited)",
					"@executable_path/Frameworks",
				);
				MARKETING_VERSION = 1.0;
				PRODUCT_BUNDLE_IDENTIFIER = com.example.knucklegame;
				PRODUCT_NAME = "$(TARGET_NAME)";
				SWIFT_EMIT_LOC_STRINGS = YES;
				SWIFT_VERSION = 5.0;
				TARGETED_DEVICE_FAMILY = "1,2";
			};
			name = Debug;
		};
		310000000000000000000004 /* Release */ = {
			isa = XCBuildConfiguration;
			buildSettings = {
				ASSETCATALOG_COMPILER_GENERATE_SWIFT_ASSET_SYMBOL_EXTENSIONS = YES;
				CODE_SIGN_STYLE = Automatic;
				CURRENT_PROJECT_VERSION = 1;
				GENERATE_INFOPLIST_FILE = NO;
				INFOPLIST_FILE = Knuckled/Info.plist;
				IPHONEOS_DEPLOYMENT_TARGET = 17.0;
				LD_RUNPATH_SEARCH_PATHS = (
					"$(inherited)",
					"@executable_path/Frameworks",
				);
				MARKETING_VERSION = 1.0;
				PRODUCT_BUNDLE_IDENTIFIER = com.example.knucklegame;
				PRODUCT_NAME = "$(TARGET_NAME)";
				SWIFT_EMIT_LOC_STRINGS = YES;
				SWIFT_VERSION = 5.0;
				TARGETED_DEVICE_FAMILY = "1,2";
			};
			name = Release;
		};
		310000000000000000000005 /* Debug */ = {
			isa = XCBuildConfiguration;
			buildSettings = {
				BUNDLE_LOADER = "$(TEST_HOST)";
				CODE_SIGN_STYLE = Automatic;
				CURRENT_PROJECT_VERSION = 1;
				GENERATE_INFOPLIST_FILE = YES;
				IPHONEOS_DEPLOYMENT_TARGET = 17.0;
				MARKETING_VERSION = 1.0;
				PRODUCT_BUNDLE_IDENTIFIER = com.example.knucklegame.KnuckledTests;
				PRODUCT_NAME = "$(TARGET_NAME)";
				SWIFT_EMIT_LOC_STRINGS = YES;
				SWIFT_VERSION = 5.0;
				TARGETED_DEVICE_FAMILY = "1,2";
				TEST_HOST = "$(BUILT_PRODUCTS_DIR)/Knuckled.app/Knuckled";
			};
			name = Debug;
		};
		310000000000000000000006 /* Release */ = {
			isa = XCBuildConfiguration;
			buildSettings = {
				BUNDLE_LOADER = "$(TEST_HOST)";
				CODE_SIGN_STYLE = Automatic;
				CURRENT_PROJECT_VERSION = 1;
				GENERATE_INFOPLIST_FILE = YES;
				IPHONEOS_DEPLOYMENT_TARGET = 17.0;
				MARKETING_VERSION = 1.0;
				PRODUCT_BUNDLE_IDENTIFIER = com.example.knucklegame.KnuckledTests;
				PRODUCT_NAME = "$(TARGET_NAME)";
				SWIFT_EMIT_LOC_STRINGS = YES;
				SWIFT_VERSION = 5.0;
				TARGETED_DEVICE_FAMILY = "1,2";
				TEST_HOST = "$(BUILT_PRODUCTS_DIR)/Knuckled.app/Knuckled";
			};
			name = Release;
		};
		310000000000000000000007 /* Debug */ = {
			isa = XCBuildConfiguration;
			buildSettings = {
				CODE_SIGN_STYLE = Automatic;
				CURRENT_PROJECT_VERSION = 1;
				GENERATE_INFOPLIST_FILE = YES;
				IPHONEOS_DEPLOYMENT_TARGET = 17.0;
				MARKETING_VERSION = 1.0;
				PRODUCT_BUNDLE_IDENTIFIER = com.example.knucklegame.KnuckledUITests;
				PRODUCT_NAME = "$(TARGET_NAME)";
				SWIFT_EMIT_LOC_STRINGS = YES;
				SWIFT_VERSION = 5.0;
				TARGETED_DEVICE_FAMILY = "1,2";
				TEST_TARGET_NAME = Knuckled;
			};
			name = Debug;
		};
		310000000000000000000008 /* Release */ = {
			isa = XCBuildConfiguration;
			buildSettings = {
				CODE_SIGN_STYLE = Automatic;
				CURRENT_PROJECT_VERSION = 1;
				GENERATE_INFOPLIST_FILE = YES;
				IPHONEOS_DEPLOYMENT_TARGET = 17.0;
				MARKETING_VERSION = 1.0;
				PRODUCT_BUNDLE_IDENTIFIER = com.example.knucklegame.KnuckledUITests;
				PRODUCT_NAME = "$(TARGET_NAME)";
				SWIFT_EMIT_LOC_STRINGS = YES;
				SWIFT_VERSION = 5.0;
				TARGETED_DEVICE_FAMILY = "1,2";
				TEST_TARGET_NAME = Knuckled;
			};
			name = Release;
		};
/* End XCBuildConfiguration section */

/* Begin XCConfigurationList section */
		300000000000000000000001 /* Build configuration list for PBXProject "Knuckled" */ = {
			isa = XCConfigurationList;
			buildConfigurations = (
				310000000000000000000001 /* Debug */,
				310000000000000000000002 /* Release */,
			);
			defaultConfigurationIsVisible = 0;
			defaultConfigurationName = Release;
		};
		300000000000000000000002 /* Build configuration list for PBXNativeTarget "Knuckled" */ = {
			isa = XCConfigurationList;
			buildConfigurations = (
				310000000000000000000003 /* Debug */,
				310000000000000000000004 /* Release */,
			);
			defaultConfigurationIsVisible = 0;
			defaultConfigurationName = Release;
		};
		300000000000000000000003 /* Build configuration list for PBXNativeTarget "KnuckledTests" */ = {
			isa = XCConfigurationList;
			buildConfigurations = (
				310000000000000000000005 /* Debug */,
				310000000000000000000006 /* Release */,
			);
			defaultConfigurationIsVisible = 0;
			defaultConfigurationName = Release;
		};
		300000000000000000000004 /* Build configuration list for PBXNativeTarget "KnuckledUITests" */ = {
			isa = XCConfigurationList;
			buildConfigurations = (
				310000000000000000000007 /* Debug */,
				310000000000000000000008 /* Release */,
			);
			defaultConfigurationIsVisible = 0;
			defaultConfigurationName = Release;
		};
/* End XCConfigurationList section */

/* Begin XCLocalSwiftPackageReference section */
		450000000000000000000001 /* XCRemoteSwiftPackageReference "KnuckledCore" */ = {
			isa = XCLocalSwiftPackageReference;
			relativePath = .;
		};
/* End XCLocalSwiftPackageReference section */

/* Begin XCSwiftPackageProductDependency section */
		450000000000000000000002 /* KnuckledCore */ = {
			isa = XCSwiftPackageProductDependency;
			package = 450000000000000000000001 /* XCRemoteSwiftPackageReference "KnuckledCore" */;
			productName = KnuckledCore;
		};
/* End XCSwiftPackageProductDependency section */

	};
	rootObject = 100000000000000000000001 /* Project object */;
}
```

- [ ] **Step 2: Write `Knuckled.xcodeproj/xcshareddata/xcschemes/Knuckled.xcscheme`**

Write EXACTLY (BlueprintIdentifiers must match the PBXNativeTarget IDs from Step 1):

```xml
<?xml version="1.0" encoding="UTF-8"?>
<Scheme
   LastUpgradeVersion = "1700"
   version = "1.7">
   <BuildAction
      parallelizeBuildables = "YES"
      buildImplicitDependencies = "YES"
      runPostActionsOnFailure = "NO">
      <BuildActionEntries>
         <BuildActionEntry
            buildForTesting = "YES"
            buildForRunning = "YES"
            buildForProfiling = "YES"
            buildForArchiving = "YES"
            buildForAnalyzing = "YES">
            <BuildableReference
               BuildableIdentifier = "primary"
               BlueprintIdentifier = "200000000000000000000001"
               BuildableName = "Knuckled.app"
               BlueprintName = "Knuckled"
               ReferencedContainer = "container:Knuckled.xcodeproj">
            </BuildableReference>
         </BuildActionEntry>
         <BuildActionEntry
            buildForTesting = "YES"
            buildForRunning = "NO"
            buildForProfiling = "NO"
            buildForArchiving = "NO"
            buildForAnalyzing = "YES">
            <BuildableReference
               BuildableIdentifier = "primary"
               BlueprintIdentifier = "200000000000000000000002"
               BuildableName = "KnuckledTests.xctest"
               BlueprintName = "KnuckledTests"
               ReferencedContainer = "container:Knuckled.xcodeproj">
            </BuildableReference>
         </BuildActionEntry>
         <BuildActionEntry
            buildForTesting = "YES"
            buildForRunning = "NO"
            buildForProfiling = "NO"
            buildForArchiving = "NO"
            buildForAnalyzing = "YES">
            <BuildableReference
               BuildableIdentifier = "primary"
               BlueprintIdentifier = "200000000000000000000003"
               BuildableName = "KnuckledUITests.xctest"
               BlueprintName = "KnuckledUITests"
               ReferencedContainer = "container:Knuckled.xcodeproj">
            </BuildableReference>
         </BuildActionEntry>
      </BuildActionEntries>
   </BuildAction>
   <TestAction
      buildConfiguration = "Debug"
      selectedDebuggerIdentifier = "Xcode.DebuggerFoundation.Debugger.LLDB"
      selectedLauncherIdentifier = "Xcode.DebuggerFoundation.Launcher.LLDB"
      shouldUseLaunchSchemeArgsEnv = "YES"
      shouldAutocreateTestPlan = "YES">
      <Testables>
         <TestableReference
            skipped = "NO"
            parallelizable = "NO">
            <BuildableReference
               BuildableIdentifier = "primary"
               BlueprintIdentifier = "200000000000000000000002"
               BuildableName = "KnuckledTests.xctest"
               BlueprintName = "KnuckledTests"
               ReferencedContainer = "container:Knuckled.xcodeproj">
            </BuildableReference>
         </TestableReference>
         <TestableReference
            skipped = "NO"
            parallelizable = "NO">
            <BuildableReference
               BuildableIdentifier = "primary"
               BlueprintIdentifier = "200000000000000000000003"
               BuildableName = "KnuckledUITests.xctest"
               BlueprintName = "KnuckledUITests"
               ReferencedContainer = "container:Knuckled.xcodeproj">
            </BuildableReference>
         </TestableReference>
      </Testables>
   </TestAction>
   <LaunchAction
      buildConfiguration = "Debug"
      selectedDebuggerIdentifier = "Xcode.DebuggerFoundation.Debugger.LLDB"
      selectedLauncherIdentifier = "Xcode.DebuggerFoundation.Launcher.PosixSpawn"
      launchStyle = "0"
      useCustomWorkingDirectory = "NO"
      ignoresPersistentStateOnLaunch = "NO"
      debugDocumentVersioning = "YES"
      debugServiceExtension = "internal"
      allowLocationSimulation = "YES">
      <BuildableProductRunnable
         runnableDebuggingMode = "0">
         <BuildableReference
            BuildableIdentifier = "primary"
            BlueprintIdentifier = "200000000000000000000001"
            BuildableName = "Knuckled.app"
            BlueprintName = "Knuckled"
            ReferencedContainer = "container:Knuckled.xcodeproj">
         </BuildableReference>
      </BuildableProductRunnable>
   </LaunchAction>
   <ProfileAction
      buildConfiguration = "Release"
      shouldUseLaunchSchemeArgsEnv = "YES"
      savedToolIdentifier = ""
      useCustomWorkingDirectory = "NO"
      debugDocumentVersioning = "YES">
      <BuildableProductRunnable
         runnableDebuggingMode = "0">
         <BuildableReference
            BuildableIdentifier = "primary"
            BlueprintIdentifier = "200000000000000000000001"
            BuildableName = "Knuckled.app"
            BlueprintName = "Knuckled"
            ReferencedContainer = "container:Knuckled.xcodeproj">
         </BuildableReference>
      </BuildableProductRunnable>
   </ProfileAction>
   <AnalyzeAction
      buildConfiguration = "Debug">
   </AnalyzeAction>
   <ArchiveAction
      buildConfiguration = "Release"
      revealArchiveInOrganizer = "YES">
   </ArchiveAction>
</Scheme>
```

- [ ] **Step 3: Write `Knuckled/Info.plist`**

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>CFBundleDevelopmentRegion</key>
	<string>en</string>
	<key>CFBundleDisplayName</key>
	<string>Knuckled</string>
	<key>CFBundleExecutable</key>
	<string>$(EXECUTABLE_NAME)</string>
	<key>CFBundleIdentifier</key>
	<string>$(PRODUCT_BUNDLE_IDENTIFIER)</string>
	<key>CFBundleInfoDictionaryVersion</key>
	<string>6.0</string>
	<key>CFBundleName</key>
	<string>$(PRODUCT_NAME)</string>
	<key>CFBundlePackageType</key>
	<string>APPL</string>
	<key>CFBundleShortVersionString</key>
	<string>1.0</string>
	<key>CFBundleVersion</key>
	<string>1</string>
	<key>ITSAppUsesNonExemptEncryption</key>
	<false/>
	<key>LSRequiresIPhoneOS</key>
	<true/>
	<key>UIAppFonts</key>
	<array>
		<string>CinzelBold.ttf</string>
	</array>
	<key>UILaunchScreen</key>
	<dict/>
	<key>UIRequiredDeviceCapabilities</key>
	<array>
		<string>arm64</string>
	</array>
	<key>UISupportedInterfaceOrientations</key>
	<array>
		<string>UIInterfaceOrientationPortrait</string>
		<string>UIInterfaceOrientationLandscapeLeft</string>
		<string>UIInterfaceOrientationLandscapeRight</string>
	</array>
	<key>UISupportedInterfaceOrientations~ipad</key>
	<array>
		<string>UIInterfaceOrientationPortrait</string>
		<string>UIInterfaceOrientationPortraitUpsideDown</string>
		<string>UIInterfaceOrientationLandscapeLeft</string>
		<string>UIInterfaceOrientationLandscapeRight</string>
	</array>
</dict>
</plist>
```

- [ ] **Step 4: Verify the project parses and resolves the package**

Run: `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild -list -project Knuckled.xcodeproj`
Expected: lists targets `Knuckled`, `KnuckledTests`, `KnuckledUITests` and scheme `Knuckled`, with no "missing package" error. (A full build comes in Task 9 — Swift sources don't exist yet, so `build` would fail on missing files; do NOT run it here.)
Troubleshooting (resolved during implementation — record): Xcode resolves the local-package path relative to the project directory (repo root, where `Package.swift` lives), so the correct value is `relativePath = .` as written above. If the package ever fails to resolve, verify `Package.swift` sits beside the `.xcodeproj`; `xcodebuild -resolvePackageDependencies -project Knuckled.xcodeproj` shows the resolution. Do not restructure — fix the path.

- [ ] **Step 5: Commit**

```bash
git add Knuckled.xcodeproj/project.pbxproj Knuckled.xcodeproj/xcshareddata/xcschemes/Knuckled.xcscheme Knuckled/Info.plist
git commit -m "feat: Xcode project scaffold (app + unit + UI test targets)"
```

---

### Task 2: Theme (colors, font, shared chrome)

**Files:**
- Copy: Android `res/font/cinzel_bold.ttf` → Create: `Knuckled/Resources/CinzelBold.ttf`
- Create: `Knuckled/Theme.swift`

- [ ] **Step 1: Copy the font**

Run: `cp /Users/robison/AndroidStudioProjects/KnuckleGame/app/src/main/res/font/cinzel_bold.ttf Knuckled/Resources/CinzelBold.ttf && ls -la Knuckled/Resources/`
Expected: `CinzelBold.ttf` listed (~122 KB).

- [ ] **Step 2: Write `Knuckled/Theme.swift`**

Exact palette from Android `ui/theme/Color.kt` + `Type.kt` (Cinzel Bold for display text, system elsewhere):

```swift
import SwiftUI

enum AppColors {
    static let feltLight = Color(red: 0x1F / 255.0, green: 0x6B / 255.0, blue: 0x3E / 255.0)
    static let feltMid = Color(red: 0x0E / 255.0, green: 0x3A / 255.0, blue: 0x22 / 255.0)
    static let feltDark = Color(red: 0x07 / 255.0, green: 0x1A / 255.0, blue: 0x10 / 255.0)
    static let gold = Color(red: 0xE2 / 255.0, green: 0xC2 / 255.0, blue: 0x6A / 255.0)
    static let goldDark = Color(red: 0xB8 / 255.0, green: 0x90 / 255.0, blue: 0x2E / 255.0)
    static let ivory = Color(red: 0xF3 / 255.0, green: 0xE7 / 255.0, blue: 0xC3 / 255.0)
    static let dieIvoryLight = Color(red: 0xFF / 255.0, green: 0xFA / 255.0, blue: 0xF0 / 255.0)
    static let pipBrown = Color(red: 0x1A / 255.0, green: 0x12 / 255.0, blue: 0x07 / 255.0)
    static let glassWhite = Color.white.opacity(0.07)
    static let glassBorderGold = AppColors.gold.opacity(0.45)
    static let error = Color(red: 0xE5 / 255.0, green: 0x73 / 255.0, blue: 0x73 / 255.0)
}

enum AppFont {
    /// Cinzel Bold for display text (title, PIN, scores). The name must match the font's Bold instance; a missing name silently falls back to system (packaging bug — verify in the Task 9 screenshot).
    static func display(size: CGFloat) -> Font {
        .custom("CinzelRoman-Bold", size: size, relativeTo: .largeTitle)
    }
}

struct FeltBackground: View {
    var body: some View {
        RadialGradient(
            colors: [AppColors.feltLight, AppColors.feltMid, AppColors.feltDark],
            center: .center,
            startRadius: 20,
            endRadius: 700
        )
        .ignoresSafeArea()
    }
}

struct GlassCard<Content: View>: View {
    let content: Content
    init(@ViewBuilder content: () -> Content) { self.content = content() }
    var body: some View {
        content
            .background(AppColors.glassWhite)
            .clipShape(RoundedRectangle(cornerRadius: 16))
            .overlay(RoundedRectangle(cornerRadius: 16).stroke(AppColors.glassBorderGold, lineWidth: 1))
    }
}

struct GoldButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .background(
                LinearGradient(
                    colors: [AppColors.gold, AppColors.goldDark],
                    startPoint: .leading, endPoint: .trailing
                )
                .opacity(isEnabled ? 1 : 0.4)
            )
            .foregroundStyle(AppColors.pipBrown)
            .clipShape(RoundedRectangle(cornerRadius: 28))
            .scaleEffect(configuration.isPressed ? 0.97 : 1.0)
    }
}

struct GoldSecondaryButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .background(AppColors.gold.opacity(0.25))
            .foregroundStyle(AppColors.gold)
            .opacity(isEnabled ? 1 : 0.4)
            .clipShape(RoundedRectangle(cornerRadius: 28))
            .scaleEffect(configuration.isPressed ? 0.97 : 1.0)
    }
}
```

- [ ] **Step 3: Commit**

```bash
git add Knuckled/Resources/CinzelBold.ttf Knuckled/Theme.swift
git commit -m "feat: app theme (felt palette, Cinzel display font, buttons)"
```

### Task 3: GameSession tests (failing)

**Files:**
- Test: `KnuckledTests/GameSessionTests.swift`

- [ ] **Step 1: Write the failing tests**

```swift
import XCTest
@testable import Knuckled
import KnuckledCore

private enum TestError: Error { case timeout }

final class GameSessionTests: XCTestCase {

    private func waitFor(_ condition: @autoclosure () -> Bool, timeout: TimeInterval) throws {
        let deadline = Date().addingTimeInterval(timeout)
        while !condition() {
            if Date() > deadline { throw TestError.timeout }
            RunLoop.main.run(until: Date().addingTimeInterval(0.05))
        }
    }

    private func startedSession() throws -> GameSession {
        let session = GameSession()
        session.startSinglePlayer(
            name: "Tester",
            rollDelayMs: 0,
            rollValue: { 3 },
            firstPlayer: { .HOST },
            preRollDelayMs: 0,
            thinkDelay: { 0 }
        )
        try waitFor(session.state != nil, timeout: 10)
        return session
    }

    func testStartPublishesFirstState() throws {
        let session = try startedSession()
        let s = session.state!
        XCTAssertEqual(s.hostName, "Tester")
        XCTAssertEqual(s.clientName, "CPU")
        XCTAssertEqual(s.status, .IN_PROGRESS)
        XCTAssertEqual(s.currentTurn, .HOST)
        XCTAssertTrue(session.inGame)
        XCTAssertTrue(session.canRoll)
    }

    func testRollPlaceAndCpuAnswers() throws {
        let session = try startedSession()
        session.roll()
        try waitFor(session.state!.phase == .AWAITING_PLACEMENT, timeout: 10)
        XCTAssertEqual(session.state!.lastRoll, 3)
        session.place(0)
        try waitFor(session.state!.grid[.HOST]![0] == [3], timeout: 10)
        // CPU answers on its turn (think delays are 0 in this session)
        try waitFor(session.state!.currentTurn == .HOST, timeout: 10)
        XCTAssertEqual(session.state!.grid[.CLIENT]!.flatMap { $0 }.count, 1)
    }

    func testPlayAgainMidGameIsIgnored() throws {
        let session = try startedSession()
        let before = session.state!
        session.playAgain()
        XCTAssertEqual(session.state!, before)
    }

    func testDisconnectClearsState() throws {
        let session = try startedSession()
        session.disconnect()
        XCTAssertNil(session.state)
        XCTAssertFalse(session.inGame)
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild test -project Knuckled.xcodeproj -scheme Knuckled -destination 'platform=iOS Simulator,name=iPhone 17' CODE_SIGNING_ALLOWED=NO 2>&1 | tail -20`
(use the exact device name verified in Task 0 if `iPhone 17` differs)
Expected: FAIL — `GameSession` undefined (compile error in `KnuckledTests`). The UI-test target will also fail to build (it references screens not yet written) — that is expected; the gate here is the compile failure naming `GameSession`.

---

### Task 4: GameSession (green)

**Files:**
- Create: `Knuckled/GameSession.swift`

- [ ] **Step 1: Implement `GameSession.swift`**

Solo session owner (mirrors Android `GameViewModel` HOST side + `LocalConnector` wiring). `GameHost.onState` fires on arbitrary threads, so state is republished on main:

```swift
import Foundation
import Combine
import KnuckledCore

/// Owns one solo session: GameHost (us, HOST) + CPU client over an in-memory link.
/// All @Published updates happen on the main thread.
final class GameSession: ObservableObject {
    @Published private(set) var state: GameState?
    @Published private(set) var playerName: String = "Player"

    let myId: PlayerId = .HOST
    let peerId: PlayerId = .CLIENT

    private var host: GameHost?
    private var link: GameLink?

    var inGame: Bool { state != nil }

    var isMyTurn: Bool {
        guard let s = state else { return false }
        return s.status == .IN_PROGRESS && s.currentTurn == myId
    }

    var canRoll: Bool {
        guard let s = state else { return false }
        return KnucklebonesRules.canRoll(s, myId)
    }

    func canPlace(_ column: Int) -> Bool {
        guard let s = state else { return false }
        return KnucklebonesRules.canPlace(s, myId, column)
    }

    func startSinglePlayer(
        name: String,
        rollDelayMs: Int = 2000,
        rollValue: @escaping () -> Int = { Int.random(in: 1...6) },
        firstPlayer: @escaping () -> PlayerId = { Bool.random() ? .HOST : .CLIENT },
        preRollDelayMs: Double = CpuPacing.preRollSeconds,
        thinkDelay: @escaping () -> Double = CpuPacing.naturalThink
    ) {
        disconnect()
        let clean = MessageCodec.sanitizeName(name)
        let (humanLink, cpuLink) = InMemoryLinkPair.make()
        runCpuClient(cpuLink, preRollDelayMs: preRollDelayMs, thinkDelay: thinkDelay)
        let h = GameHost(
            link: humanLink,
            hostName: clean.isEmpty ? "Player" : clean,
            rollValue: rollValue,
            rollDelayMs: rollDelayMs,
            firstPlayer: firstPlayer,
            onState: { [weak self] s in
                DispatchQueue.main.async { self?.state = s }
            }
        )
        self.link = humanLink
        self.host = h
        self.playerName = clean.isEmpty ? "Player" : clean
        h.connect()
    }

    /// Async: the host roll blocks ~rollDelayMs mid-roll (same as Android's IO dispatcher).
    func roll() {
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            self?.host?.hostRoll()
        }
    }

    func place(_ column: Int) {
        host?.hostPlace(column)
    }

    func playAgain() {
        host?.restart()
    }

    func disconnect() {
        link?.close()
        link = nil
        host = nil
        state = nil
    }
}
```

- [ ] **Step 2: Run the tests**

Run: `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild test -project Knuckled.xcodeproj -scheme Knuckled -destination 'platform=iOS Simulator,name=iPhone 17' CODE_SIGNING_ALLOWED=NO 2>&1 | tail -8`
Expected: `KnuckledTests` green (4 tests pass). `KnuckledUITests` still fails to build (its screens land in Tasks 5-8) — that is expected; gate on the unit-test result only.

- [ ] **Step 3: Commit**

```bash
git add Knuckled/GameSession.swift KnuckledTests/GameSessionTests.swift
git commit -m "feat: solo game session (host + CPU over in-memory link)"
```

### Task 5: Board views + column helpers

**Files:**
- Create: `Knuckled/BoardViews.swift`
- Test: `KnuckledTests/ColumnDisplayTests.swift`

- [ ] **Step 1: Write the failing tests**

Pure layout helpers ported from Android `ui/ColumnDisplay.kt` (growth outward from the middle: own board top-anchored oldest-first, peer board bottom-anchored oldest-last):

```swift
import XCTest
@testable import Knuckled

final class ColumnDisplayTests: XCTestCase {
    func testOwnColumnPadsBelow() {
        XCTAssertEqual(ownColumnTopToBottom([4, 1, 4]), [4, 1, 4])
        XCTAssertEqual(ownColumnTopToBottom([4]), [4, nil, nil])
        XCTAssertEqual(ownColumnTopToBottom([]), [nil, nil, nil])
    }

    func testPeerColumnPadsAbove() {
        XCTAssertEqual(peerColumnTopToBottom([3, 3]), [nil, 3, 3])
        XCTAssertEqual(peerColumnTopToBottom([2, 3]), [nil, 3, 2])
        XCTAssertEqual(peerColumnTopToBottom([]), [nil, nil, nil])
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run the Task 4 test command. Expected: FAIL — `ownColumnTopToBottom` / `peerColumnTopToBottom` undefined.

- [ ] **Step 3: Implement `Knuckled/BoardViews.swift`**

`GameBoard` (peer top / own bottom variants), `DieColumn` (52pt cells, Ivory numerals, gold border when placeable), `ColumnScoreChip`, and the two pure helpers:

```swift
import SwiftUI
import KnuckledCore

/// Own board: oldest die nearest the middle (top). Returns exactly 3 rows, top-anchored.
func ownColumnTopToBottom(_ dice: [Int]) -> [Int?] {
    dice.map { Optional($0) } + Array(repeating: nil, count: max(0, 3 - dice.count))
}

/// Peer board: oldest die nearest the middle (bottom). Newest-first after front-padding.
/// Returns exactly 3 rows, bottom-anchored. Mirrors Android `topColumnTopToBottom`.
func peerColumnTopToBottom(_ dice: [Int]) -> [Int?] {
    Array(repeating: nil, count: max(0, 3 - dice.count)) + dice.reversed().map { Optional($0) }
}

struct DieCell: View {
    let value: Int?
    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 8)
                .fill(value == nil ? Color.white.opacity(0.25) : AppColors.glassWhite)
                .frame(width: 52, height: 52)
            if let value {
                Text("\(value)")
                    .font(.title3.bold())
                    .foregroundStyle(AppColors.ivory)
            }
        }
        .padding(3)
    }
}

struct ColumnScoreChip: View {
    let value: Int
    var body: some View {
        Text("\(value)")
            .font(.caption2)
            .foregroundStyle(AppColors.gold)
            .frame(width: 44, height: 18)
            .background(AppColors.glassWhite)
            .clipShape(RoundedRectangle(cornerRadius: 6))
    }
}

struct GameBoard: View {
    let isMine: Bool
    let name: String
    let grid: Grid
    let destroyed: [DieRef]
    let active: Bool
    let canPlace: Bool
    let onColumnTap: ((Int) -> Void)?

    private func columnPlaceable(_ column: Int) -> Bool {
        guard column < grid.count else { return false }
        return onColumnTap != nil && active && canPlace && grid[column].count < 3
    }

    var body: some View {
        VStack(spacing: 6) {
            if isMine {
                ForEach(0..<3, id: \.self) { column in
                    columnView(column)
                }
                header
            } else {
                header
                ForEach(0..<3, id: \.self) { column in
                    columnView(column)
                }
            }
        }
    }

    private var header: some View {
        HStack {
            Text(name)
                .font(.headline)
                .foregroundStyle(AppColors.gold)
            Spacer()
            Text("\(KnucklebonesRules.totalScore(grid))")
                .font(.title2.bold())
                .foregroundStyle(AppColors.ivory)
                .accessibilityIdentifier(isMine ? "score-mine" : "score-peer")
        }
    }

    private func columnView(_ column: Int) -> some View {
        let dice = column < grid.count ? grid[column] : []
        let cells = isMine ? ownColumnTopToBottom(dice) : peerColumnTopToBottom(dice)
        let placeable = columnPlaceable(column)
        return VStack(spacing: 4) {
            if isMine { ColumnScoreChip(value: KnucklebonesRules.columnScore(dice)) }
            ForEach(0..<cells.count, id: \.self) { row in
                DieCell(value: cells[row])
            }
            if !isMine { ColumnScoreChip(value: KnucklebonesRules.columnScore(dice)) }
            destroyGhosts(column: column)
        }
        .padding(2)
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(placeable ? AppColors.gold : AppColors.glassBorderGold, lineWidth: 1)
        )
        .accessibilityIdentifier("\(isMine ? "own" : "peer")-col-\(column)")
        .accessibilityLabel("\(isMine ? "own" : "peer") column \(column)")
        .onTapGesture {
            if placeable { onColumnTap?(column) }
        }
    }

    @ViewBuilder
    private func destroyGhosts(column: Int) -> some View {
        let ghosts = destroyed.filter { $0.column == column }
        if !ghosts.isEmpty {
            HStack(spacing: 4) {
                ForEach(0..<ghosts.count, id: \.self) { _ in
                    ZStack {
                        RoundedRectangle(cornerRadius: 8)
                            .fill(Color.red.opacity(0.35))
                            .frame(width: 30, height: 30)
                        Text("×").foregroundStyle(.white)
                    }
                }
            }
            .transition(.opacity)
        }
    }
}
```

Notes: peer board passes `onColumnTap: nil` (never tappable). Column containers share no single tag (Android's shared `"column"` tag is an Espresso-ism; the per-column identifiers above supersede it). The destroyed-ghost 500ms fade is simplified here to appear/disappear with state (the fade animation lands in the parity plan).

- [ ] **Step 4: Run the tests**

Run the Task 4 test command. Expected: `KnuckledTests` green (6 tests: 4 session + 2 column). UI tests still red (expected).

- [ ] **Step 5: Commit**

```bash
git add Knuckled/BoardViews.swift KnuckledTests/ColumnDisplayTests.swift
git commit -m "feat: game board views (peer top, own bottom, scores, ghosts)"
```

---

### Task 6: 2D die view (temporary stand-in for the 3D die)

**Files:**
- Create: `Knuckled/DieView.swift`

Context: Android renders a 3D die (`dice.glb`, orientation table, 720°/s tumble). The SceneKit 3D die lands in the parity plan; this task is a tappable 2D pip die with the same 120pt size, tap gating, and accessibility labels so the solo game is fully playable now.

- [ ] **Step 1: Implement `Knuckled/DieView.swift`**

```swift
import SwiftUI

/// Temporary 2D pip die (120pt). The SceneKit 3D die replaces this in the parity plan.
/// Same contract: fixed size, tap only when enabled && !rolling, spinning cue while rolling.
struct DieView: View {
    let value: Int?
    let rolling: Bool
    let enabled: Bool
    let onTap: () -> Void

    private static func pips(for value: Int) -> Set<Int> {
        switch value {
        case 1: return [5]
        case 2: return [1, 9]
        case 3: return [1, 5, 9]
        case 4: return [1, 3, 7, 9]
        case 5: return [1, 3, 5, 7, 9]
        case 6: return [1, 3, 4, 6, 7, 9]
        default: return []
        }
    }

    var body: some View {
        Button(action: {
            if enabled && !rolling { onTap() }
        }) {
            ZStack {
                RoundedRectangle(cornerRadius: 20)
                    .fill(AppColors.dieIvoryLight)
                    .frame(width: 120, height: 120)
                GeometryReader { geo in
                    let cell = min(geo.size.width, geo.size.height) / 3
                    ForEach(1...9, id: \.self) { pos in
                        if Self.pips(for: value ?? 0).contains(pos) {
                            Circle()
                                .fill(AppColors.pipBrown)
                                .frame(width: cell * 0.52, height: cell * 0.52)
                                .position(
                                    x: cell * (CGFloat((pos - 1) % 3) + 0.5),
                                    y: cell * (CGFloat((pos - 1) / 3) + 0.5)
                                )
                        }
                    }
                }
                .frame(width: 120, height: 120)
            }
            .rotationEffect(.degrees(rolling ? 360 : 0))
            .animation(rolling ? .linear(duration: 1.0) : .default, value: rolling)
            .opacity(value == nil && !rolling ? 0.4 : 1.0)
        }
        .buttonStyle(.plain)
        .disabled(!(enabled && !rolling))
        .accessibilityIdentifier("dice")
        .accessibilityLabel(rolling ? "Dice rolling" : value.map { "Dice showing \($0)" } ?? "Dice tap to roll")
    }
}
```

- [ ] **Step 2: Commit**

```bash
git add Knuckled/DieView.swift
git commit -m "feat: temporary 2D pip die (3D die lands in parity plan)"
```

### Task 7: Game screen + result overlays

**Files:**
- Create: `Knuckled/ResultOverlays.swift`
- Create: `Knuckled/GameScreen.swift`

- [ ] **Step 1: Implement `Knuckled/ResultOverlays.swift`**

Simplified Winner/Draw overlays (title, score, Play again, Disconnect). Confetti, trophy spring, and WIN/LOSE sounds land in the parity plan:

```swift
import SwiftUI
import KnuckledCore

struct WinnerOverlay: View {
    let state: GameState
    let myId: PlayerId
    let onPlayAgain: () -> Void
    let onLeave: () -> Void

    var body: some View {
        let winner = state.winner!
        let isWinner = winner == myId
        let winnerScore = KnucklebonesRules.totalScore(state.grid[winner]!)
        let loserScore = KnucklebonesRules.totalScore(state.grid[state.opponentOf(winner)]!)
        ZStack {
            AppColors.feltDark.opacity(0.85).ignoresSafeArea()
            VStack(spacing: 16) {
                Text(isWinner ? "🏆" : "🎲").font(.system(size: 72))
                Text(isWinner ? "You win!" : "You lose!")
                    .font(AppFont.display(size: 32))
                    .foregroundStyle(.white)
                Text("\(winnerScore) – \(loserScore)")
                    .font(AppFont.display(size: 28))
                    .foregroundStyle(AppColors.gold)
                if !isWinner {
                    Text("\(state.playerName(winner)) wins!")
                        .font(.body)
                        .foregroundStyle(.white)
                }
                Button("Play again", action: onPlayAgain)
                    .buttonStyle(GoldButtonStyle())
                Button("Disconnect", action: onLeave)
                    .buttonStyle(GoldSecondaryButtonStyle())
            }
            .padding(24)
        }
        .accessibilityIdentifier("winner-overlay")
    }
}

struct DrawOverlay: View {
    let state: GameState
    let myId: PlayerId
    let onPlayAgain: () -> Void
    let onLeave: () -> Void

    var body: some View {
        let myScore = KnucklebonesRules.totalScore(state.grid[myId]!)
        let peerScore = KnucklebonesRules.totalScore(state.grid[state.opponentOf(myId)]!)
        ZStack {
            AppColors.feltDark.opacity(0.85).ignoresSafeArea()
            VStack(spacing: 16) {
                Text("🎲").font(.system(size: 72))
                Text("Draw")
                    .font(AppFont.display(size: 32))
                    .foregroundStyle(.white)
                Text("\(myScore) – \(peerScore)")
                    .font(AppFont.display(size: 28))
                    .foregroundStyle(AppColors.gold)
                Button("Play again", action: onPlayAgain)
                    .buttonStyle(GoldButtonStyle())
                Button("Disconnect", action: onLeave)
                    .buttonStyle(GoldSecondaryButtonStyle())
            }
            .padding(24)
        }
        .accessibilityIdentifier("draw-overlay")
    }
}
```

- [ ] **Step 2: Implement `Knuckled/GameScreen.swift`**

Peer board top, roll area middle, own board bottom (matches Android). Turn pill, place hint, leave flow with confirmation, result overlay 1200ms after terminal:

```swift
import SwiftUI
import KnuckledCore

struct TurnPill: View {
    let state: GameState
    let myId: PlayerId
    let peerName: String

    var body: some View {
        Group {
            if state.status == .IN_PROGRESS {
                Text(state.phase == .ROLLING ? "Rolling…" : state.currentTurn == myId ? "Your turn" : "\(peerName)'s turn")
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .background(AppColors.glassWhite)
                    .overlay(Capsule().stroke(AppColors.glassBorderGold, lineWidth: 1))
                    .clipShape(Capsule())
                    .accessibilityIdentifier("turn-pill")
            }
        }
    }
}

struct GameScreen: View {
    @ObservedObject var session: GameSession
    @State private var showLeaveConfirm = false
    @State private var resultArmed = false

    var body: some View {
        ZStack {
            FeltBackground()
            if let s = session.state {
                ScrollView {
                    VStack(spacing: 14) {
                        topBar
                        GameBoard(
                            isMine: false,
                            name: s.clientName,
                            grid: s.grid[session.peerId] ?? [[], [], []],
                            destroyed: s.destroyed.filter { $0.player == session.peerId },
                            active: s.currentTurn == session.peerId && s.status == .IN_PROGRESS,
                            canPlace: false,
                            onColumnTap: nil
                        )
                        .accessibilityIdentifier("peer-board")
                        TurnPill(state: s, myId: session.myId, peerName: s.clientName)
                        DieView(
                            value: s.lastRoll,
                            rolling: s.phase == .ROLLING,
                            enabled: session.canRoll,
                            onTap: { session.roll() }
                        )
                        if s.phase == .AWAITING_PLACEMENT && s.currentTurn == session.myId {
                            Text("Tap a column to place the die")
                                .font(.caption)
                                .foregroundStyle(AppColors.ivory)
                                .accessibilityIdentifier("place-hint")
                        }
                        GameBoard(
                            isMine: true,
                            name: s.hostName,
                            grid: s.grid[session.myId] ?? [[], [], []],
                            destroyed: s.destroyed.filter { $0.player == session.myId },
                            active: s.currentTurn == session.myId && s.status == .IN_PROGRESS,
                            canPlace: s.phase == .AWAITING_PLACEMENT && s.currentTurn == session.myId,
                            onColumnTap: { session.place($0) }
                        )
                        .accessibilityIdentifier("own-board")
                    }
                    .padding(16)
                }
                if showResult(for: s) {
                    if s.status == .FINISHED {
                        WinnerOverlay(state: s, myId: session.myId, onPlayAgain: { session.playAgain() }, onLeave: leave)
                    } else {
                        DrawOverlay(state: s, myId: session.myId, onPlayAgain: { session.playAgain() }, onLeave: leave)
                    }
                }
            } else {
                Text("Waiting for state…").foregroundStyle(AppColors.ivory)
            }
            if showLeaveConfirm {
                leaveConfirm
                    .accessibilityIdentifier("leave-confirm")
            }
        }
        .task(id: session.state?.status) {
            // Re-arms on every status change; shows the overlay 1200ms after terminal.
            resultArmed = false
            let status = session.state?.status
            if status == .FINISHED || status == .DRAW {
                try? await Task.sleep(for: .milliseconds(1200))
                if session.state?.status == status { resultArmed = true }
            }
        }
    }

    private func showResult(for s: GameState) -> Bool {
        (s.status == .FINISHED || s.status == .DRAW) && resultArmed
    }

    private var topBar: some View {
        HStack {
            Button("Leave") { showLeaveConfirm = true }
                .accessibilityIdentifier("leave")
            Spacer()
        }
        .padding(.horizontal, 8)
    }

    private var leaveConfirm: some View {
        ZStack {
            Color.black.opacity(0.5).ignoresSafeArea()
            VStack(spacing: 16) {
                Text("Leave game?").font(.headline).foregroundStyle(AppColors.ivory)
                Text("Are you sure? Your progress will be lost.").font(.body).foregroundStyle(AppColors.ivory)
                HStack(spacing: 12) {
                    Button("Stay") { showLeaveConfirm = false }
                        .buttonStyle(GoldSecondaryButtonStyle())
                        .accessibilityIdentifier("stay")
                    Button("Leave") { leave() }
                        .buttonStyle(GoldButtonStyle())
                        .accessibilityIdentifier("confirm-leave")
                }
            }
            .padding(24)
            .background(AppColors.feltMid)
            .clipShape(RoundedRectangle(cornerRadius: 16))
            .padding(32)
        }
    }

    private func leave() {
        showLeaveConfirm = false
        session.disconnect()
    }
}

- [ ] **Step 3: Commit**

```bash
git add Knuckled/ResultOverlays.swift Knuckled/GameScreen.swift
git commit -m "feat: game screen (boards, turn pill, die, overlays, leave flow)"
```

---

### Task 8: Start screen + app entry + UI smoke test

**Files:**
- Create: `Knuckled/StartScreen.swift`
- Create: `Knuckled/KnuckledApp.swift`
- Test: `KnuckledUITests/SoloSmokeTests.swift`

- [ ] **Step 1: Implement `Knuckled/StartScreen.swift`**

Name field (empty default + inline error, Android-faithful) + Play vs CPU. Host/Join arrive in the parity plan:

```swift
import SwiftUI
import KnuckledCore

struct StartScreen: View {
    @ObservedObject var session: GameSession
    @State private var name: String = ""
    @State private var error: String?

    var body: some View {
        ZStack {
            FeltBackground()
            VStack(spacing: 16) {
                Text("⚂")
                    .font(.system(size: 56))
                    .foregroundStyle(AppColors.dieIvoryLight)
                Text("Knuckled")
                    .font(AppFont.display(size: 32))
                    .foregroundStyle(AppColors.gold)
                    .accessibilityIdentifier("start-title")
                TextField("Your name", text: $name)
                    .textFieldStyle(.roundedBorder)
                    .accessibilityIdentifier("name-field")
                if let error {
                    Text(error).foregroundStyle(AppColors.error)
                }
                Button("Play vs CPU") {
                    if MessageCodec.sanitizeName(name).isEmpty {
                        error = "Enter your name"
                    } else {
                        session.startSinglePlayer(name: name)
                    }
                }
                .buttonStyle(GoldButtonStyle())
                .accessibilityIdentifier("single-player-button")
            }
            .padding(24)
        }
    }
}
```

Note: `StartScreen.swift` uses `MessageCodec` — the `import KnuckledCore` above covers it. (If the Task 9 build reports a missing import, it is this one.)

- [ ] **Step 2: Implement `Knuckled/KnuckledApp.swift`**

```swift
import SwiftUI

@main
struct KnuckledApp: App {
    @StateObject private var session = GameSession()

    var body: some Scene {
        WindowGroup {
            ZStack {
                FeltBackground()
                if session.inGame {
                    GameScreen(session: session)
                } else {
                    StartScreen(session: session)
                }
            }
        }
    }
}
```

- [ ] **Step 3: Write `KnuckledUITests/SoloSmokeTests.swift`**

XCUITest smoke: launch → name → play → boards → roll → place. First player is random: if the CPU moves first, the test waits through it (CPU acts within ~3s with production pacing):

```swift
import XCTest

final class SoloSmokeTests: XCTestCase {
    func testSoloGameBootsAndFirstMove() {
        let app = XCUIApplication()
        app.launch()
        XCTAssertTrue(app.staticTexts["start-title"].waitForExistence(timeout: 10))

        let nameField = app.textFields["name-field"]
        XCTAssertTrue(nameField.waitForExistence(timeout: 5))
        nameField.tap()
        nameField.typeText("Tester")
        app.buttons["single-player-button"].tap()

        XCTAssertTrue(app.otherElements["own-board"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.otherElements["peer-board"].exists)
        XCTAssertTrue(app.buttons["dice"].waitForExistence(timeout: 5))

        // Wait for our turn (CPU may move first), then roll.
        let dice = app.buttons["dice"]
        XCTAssertTrue(dice.waitForExistence(timeout: 5))
        waitForEnabled(dice, timeout: 30)
        dice.tap()

        // Awaiting placement → place in column 0.
        XCTAssertTrue(app.staticTexts["place-hint"].waitForExistence(timeout: 10))
        app.otherElements["own-col-0"].tap()

        // Game continues (no crash): boards still present.
        XCTAssertTrue(app.otherElements["own-board"].waitForExistence(timeout: 10))
    }

    private func waitForEnabled(_ element: XCUIElement, timeout: TimeInterval) {
        let predicate = NSPredicate(format: "enabled == true")
        let expectation = XCTNSPredicateExpectation(predicate: predicate, object: element)
        let result = XCTWaiter().wait(for: [expectation], timeout: timeout)
        XCTAssertEqual(result, .completed, "element never became enabled")
    }
}
```

Notes: `GameBoard` root is a `VStack` → XCUITest sees it as `otherElements` (plus the explicit identifiers). Column containers are `VStack.onTapGesture` (not `Button`) → they appear as `otherElements["own-col-0"]` and are tappable. `DieView` root IS a `Button` → `app.buttons["dice"]`, enabled only when tappable. If any query shape mismatches at runtime, adjust the queries (not the app) and report the change.

- [ ] **Step 4: Commit**

```bash
git add Knuckled/StartScreen.swift Knuckled/KnuckledApp.swift KnuckledUITests/SoloSmokeTests.swift
git commit -m "feat: start screen, app entry, solo UI smoke test"
```

---

### Task 9: Build, test, install, launch, screenshot

**Files:** none (verification + evidence only — no commit unless fixes are needed)

- [ ] **Step 1: Boot a simulator (if needed)**

Run: `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcrun simctl list devices available | grep -i "iphone 17"`
Expected: a line with a UDID. If its state is `Shutdown`, boot it: `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcrun simctl boot "iPhone 17"`. (Use the exact device name verified in Task 0 everywhere below.)

- [ ] **Step 2: Build the app**

Run: `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild -project Knuckled.xcodeproj -scheme Knuckled -destination 'platform=iOS Simulator,name=iPhone 17' -derivedDataPath /tmp/KnuckledDD build CODE_SIGNING_ALLOWED=NO`
Expected: `** BUILD SUCCEEDED **` with no errors. Fix any compile errors (missing imports are the usual suspect: every file using game types needs `import KnuckledCore`).

- [ ] **Step 3: Run unit + UI tests in the Simulator**

Run: `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild test -project Knuckled.xcodeproj -scheme Knuckled -destination 'platform=iOS Simulator,name=iPhone 17' CODE_SIGNING_ALLOWED=NO 2>&1 | tail -15`
Expected: `KnuckledTests` 6/6 pass AND `SoloSmokeTests` 1/1 pass (`Test Suite 'All tests' passed`). The UI test takes ~30-60s (2s production roll + CPU pacing). If the UI test fails on element queries, fix the QUERIES in `SoloSmokeTests.swift` first (Task 8 note); only touch app code if an accessibilityIdentifier is genuinely missing.

- [ ] **Step 4: Install, launch, screenshot (human evidence)**

Run:
```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcrun simctl install booted /tmp/KnuckledDD/Build/Products/Debug-iphonesimulator/Knuckled.app
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcrun simctl launch booted com.example.knucklegame
sleep 3
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcrun simctl io booted screenshot /tmp/knuckled-start.png
```
Expected: `launch` prints the PID; screenshot file exists. Attach `/tmp/knuckled-start.png` as evidence in the final report (it should show the felt background, ⚂, Knuckled title, name field, Play vs CPU).

- [ ] **Step 5: Commit only if Step 3-4 required fixes**

If query fixes or import fixes were needed: `git add` the touched files and commit with `fix: ...` + `test: ...` messages as appropriate. Otherwise no commit (verification only).