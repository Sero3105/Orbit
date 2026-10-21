#!/bin/zsh
# SPDX-License-Identifier: GPL-3.0-or-later
# Copyright (C) 2026 Vorssaint

# Builds Orbit, assembles the .app bundle, signs it and (with --install)
# installs it into /Applications.
#
# The bundle is staged in a temporary directory outside ~/Documents: folders synced
# by File Provider gain xattrs (com.apple.provenance etc.) that invalidate codesign.
set -euo pipefail
cd "$(dirname "$0")"

# The icon catalog and the bundle are staged in temp dirs; sweep both however
# the script ends.
ICON_TMP=""
STAGE_TMP=""

cleanup() {
    [[ -n "$ICON_TMP" ]] && rm -rf "$ICON_TMP"
    [[ -n "$STAGE_TMP" ]] && rm -rf "$STAGE_TMP"
    return 0
}
trap cleanup EXIT
# zsh runs the EXIT trap when the script is hung up, but not when it is
# interrupted or terminated; route those through exit so a Ctrl-C partway
# into the build sweeps like any other ending.
trap 'exit 1' INT TERM HUP

# Flags: --dev builds the local-only "Orbit (Developer)" variant (its own
# bundle id, so it coexists with the official app); --install puts it in /Applications.
DEV=0
INSTALL=0
TEST=0
TEST_ARGS=()
for arg in "$@"; do
    case "$arg" in
        --dev)     DEV=1 ;;
        --install) INSTALL=1 ;;
        --test)    TEST=1 ;;
        --test-suite=*) TEST=1; TEST_ARGS+=("--suite=${arg#*=}") ;;
        --list-tests) TEST=1; TEST_ARGS+=(--list) ;;
    esac
done

if (( DEV )); then
    APP_NAME="Orbit (Developer)"
    EXECUTABLE="OrbitDeveloper"
    APP_BUNDLE_ID="com.orbit.Orbit.dev"
    BUILD_VARIANT_FLAGS=(-D ORBIT_DEVELOPMENT)
    APP_OPTIMIZATION_FLAGS=(-Onone)
    BUILD_CONFIGURATION="debug"
else
    APP_NAME="Orbit"
    EXECUTABLE="Orbit"
    APP_BUNDLE_ID="com.orbit.Orbit"
    BUILD_VARIANT_FLAGS=()
    APP_OPTIMIZATION_FLAGS=(-O)
    BUILD_CONFIGURATION="release"
fi
FAN_HELPER_ID="$APP_BUNDLE_ID.fan-control"
# Now Playing is read through /usr/bin/perl loading this library; see
# Sources/NowPlayingAdapter. Staged under Contents/Frameworks, signed on its own.
NOW_PLAYING_ADAPTER_ID="$APP_BUNDLE_ID.now-playing"
NOW_PLAYING_ADAPTER="libOrbitNowPlaying.dylib"
TARGET="arm64-apple-macosx14.0"
ENTITLEMENTS="Resources/Orbit.entitlements"
LEGACY_IDENTITY="Orbit Utils Signing"

developer_id_identity() {
    security find-identity -v -p codesigning 2>/dev/null \
        | grep 'Developer ID Application' \
        | head -1 \
        | sed -E 's/.*"(.*)".*/\1/' || true
}

# A find-identity listing also names certificates codesign then rejects (an
# expired one fails the build with errSecInternalComponent), and -v excludes
# every self-signed one; ask codesign itself with a throwaway copy of /bin/echo.
legacy_identity_installed() {
    local probe signed=1
    # A locked keychain still lists its identities but cannot sign with them,
    # and this one is locked after every reboot; unlock it before asking.
    security unlock-keychain -p orbit-signing \
        "$HOME/Library/Keychains/orbit-signing.keychain-db" 2>/dev/null || true
    probe="$(mktemp)"
    cp /bin/echo "$probe"
    /usr/bin/codesign --force --strip-disallowed-xattrs --sign "$LEGACY_IDENTITY" "$probe" \
        >/dev/null 2>&1 && signed=0
    rm -f "$probe"
    return $signed
}

# Any build that lands in /Applications needs a stable signature, not just the
# Developer one: macOS ties Accessibility and Screen Recording grants to the
# exact binary hash, so an ad-hoc rebuild orphans them while System Settings
# keeps showing them as granted, and no new prompt ever appears. A plain
# --install strands them under the released bundle id, on the app the user
# actually relies on. When no identity is installed, create the stable local one
# up front instead of falling through to ad-hoc — setup-signing.sh is free,
# offline and idempotent. Gating on the install rather than the variant keeps
# this off CI, where neither ci.yml nor release.yml passes --install.
if (( DEV || INSTALL )) && [[ -z "$(developer_id_identity)" ]] \
    && ! legacy_identity_installed; then
    echo "▸ No signing identity installed; creating the stable local one…"
    if ! ./Tools/setup-signing.sh; then
        echo "  ⚠ Tools/setup-signing.sh failed; signing ad-hoc instead." >&2
        echo "    Accessibility and Screen Recording grants will not survive rebuilds:" >&2
        echo "    System Settings will show them as granted while the app is not trusted." >&2
        echo "    After fixing the identity, clear the stale grant once with:" >&2
        echo "      tccutil reset Accessibility $APP_BUNDLE_ID" >&2
    fi
fi

codesign_with_timestamp_retry() {
    local attempt
    for attempt in 1 2 3; do
        if /usr/bin/codesign "$@"; then
            return 0
        fi
        if (( attempt < 3 )); then
            echo "  Developer ID signing failed; retrying ($((attempt + 1))/3)"
            sleep "$attempt"
        fi
    done
    return 1
}

write_swift_output_file_map() {
    local output_file="$1"
    local object_dir="$2"
    shift 2
    local source artifact

    {
        print -r -- "{"
        print -r -- "  \"\": {"
        print -r -- "    \"swift-dependencies\": \"$object_dir/master.swiftdeps\""
        print -r -- "  }"
        for source in "$@"; do
            artifact="${source//\//__}"
            artifact="${artifact%.swift}"
            print -r -- ","
            print -r -- "  \"$source\": {"
            print -r -- "    \"object\": \"$object_dir/$artifact.o\","
            print -r -- "    \"swift-dependencies\": \"$object_dir/$artifact.swiftdeps\""
            print -r -- "  }"
        done
        print -r -- "}"
    } > "$output_file"
}

finalize_installed_bundle_after_child() {
    local bundle="$1"
    local helper="$bundle/Contents/Library/LaunchServices/$FAN_HELPER_ID"
    local adapter="$bundle/Contents/Frameworks/$NOW_PLAYING_ADAPTER"
    local devid
    devid="$(developer_id_identity)"

    echo "▸ Finalizing installed signature…"
    sleep 3
    if [[ -n "$devid" ]]; then
        [[ -f "$helper" ]] && codesign_with_timestamp_retry --force --strip-disallowed-xattrs \
            --options runtime --timestamp --identifier "$FAN_HELPER_ID" --sign "$devid" "$helper"
        [[ -f "$adapter" ]] && codesign_with_timestamp_retry --force --strip-disallowed-xattrs \
            --options runtime --timestamp --identifier "$NOW_PLAYING_ADAPTER_ID" --sign "$devid" "$adapter"
        codesign_with_timestamp_retry --force --strip-disallowed-xattrs --options runtime --timestamp \
            --entitlements "$ENTITLEMENTS" --sign "$devid" "$bundle"
    elif legacy_identity_installed; then
        [[ -f "$helper" ]] && /usr/bin/codesign --force --strip-disallowed-xattrs \
            --identifier "$FAN_HELPER_ID" --sign "$LEGACY_IDENTITY" "$helper"
        [[ -f "$adapter" ]] && /usr/bin/codesign --force --strip-disallowed-xattrs \
            --identifier "$NOW_PLAYING_ADAPTER_ID" --sign "$LEGACY_IDENTITY" "$adapter"
        /usr/bin/codesign --force --strip-disallowed-xattrs --sign "$LEGACY_IDENTITY" "$bundle"
    else
        [[ -f "$helper" ]] && /usr/bin/codesign --force --strip-disallowed-xattrs \
            --identifier "$FAN_HELPER_ID" --sign - "$helper"
        [[ -f "$adapter" ]] && /usr/bin/codesign --force --strip-disallowed-xattrs \
            --identifier "$NOW_PLAYING_ADAPTER_ID" --sign - "$adapter"
        /usr/bin/codesign --force --strip-disallowed-xattrs --sign - "$bundle"
    fi
    [[ -f "$helper" ]] && /usr/bin/codesign --verify --strict "$helper"
    [[ -f "$adapter" ]] && /usr/bin/codesign --verify --strict "$adapter"
    /usr/bin/codesign --verify --deep --strict "$bundle"
    echo "✓ Signature ready: $bundle"
}

if (( INSTALL && ! TEST )) && [[ "${ORBIT_INSTALL_CHILD:-0}" != "1" ]]; then
    ORBIT_INSTALL_CHILD=1 "$0" "$@"
    child_status=$?
    if (( child_status != 0 )); then
        exit "$child_status"
    fi
    finalize_installed_bundle_after_child "/Applications/$APP_NAME.app"
    exit 0
fi

# Prefer the macOS 26 SDK when present: the 27 SDK turns SwiftUI property wrappers
# into macros (SwiftUIMacros plugin) that the Command Line Tools cannot load yet.
PINNED_SDK="/Library/Developer/CommandLineTools/SDKs/MacOSX26.sdk"
if [[ -n "${DEVELOPER_DIR:-}" ]]; then
    SDK="$(xcrun --show-sdk-path)"
elif [[ -d "$PINNED_SDK" ]]; then
    SDK="$PINNED_SDK"
else
    SDK="$(xcrun --show-sdk-path)"
fi
SDK_COMPAT_FLAGS=()
VM_STATISTICS_COMPAT_FLAGS=(-I Sources/VMStatisticsCompat)
HID_EVENT_SYSTEM_FLAGS=(-I Sources/HIDEventSystem)
if [[ "$SDK" == "$PINNED_SDK" ]]; then
    # Swift 6.4 can read the SDK 26 interfaces when given their compiler version.
    SDK_COMPAT_FLAGS=(-Xfrontend -interface-compiler-version -Xfrontend 6.3.2)
fi

# The defaults migrations under test need a real UserDefaults suite, and every
# suite leaves an empty plist in ~/Library/Preferences. The tests already clear
# the domains, but cfprefsd writes the emptied file back out around the time the
# process that owned it exits, so only a caller that outlives the run can remove
# them. `PreferenceNamespaceTests` scans every compiled Swift test file against
# these namespaces, which keeps this sweep complete without a second list.
discard_test_preferences() {
    local preferences="${1:-$HOME/Library/Preferences}" name attempt
    local survivors=0 quiet_passes=0
    # cfprefsd can recreate an emptied domain after the first removal. Require
    # two quiet checks, but keep a hard limit so persistent failures still fail CI.
    for attempt in {1..10}; do
        for name in "vorss.tests." "com.orbit.tests."; do
            rm -f "$preferences"/$name*.plist(N)
        done
        rm -f "$preferences/metrics-tests.plist"
        sleep 0.2
        survivors=$(find "$preferences" -maxdepth 1 \
            \( -name "vorss.tests.*.plist" -o -name "com.orbit.tests.*.plist" \
               -o -name "metrics-tests.plist" \) 2>/dev/null | wc -l | tr -d ' ')
        if [[ "$survivors" == "0" ]]; then
            quiet_passes=$((quiet_passes + 1))
            if (( quiet_passes == 2 )); then return 0; fi
        else
            quiet_passes=0
        fi
    done
    echo "✗ test preferences did not settle in $preferences ($survivors remaining)" >&2
    return 1
}

# Standalone automated tests: pure contracts plus isolated disk, subprocess,
# keyboard-data and media fixtures. No application windows or device capture.
if (( TEST )); then
    python3 Tests/generate_sources.py
    TEST_OBJECT_DIR="build/objects/tests"
    mkdir -p "$TEST_OBJECT_DIR"
    TEST_SOURCES=(
        Sources/Orbit/Services/Media/MediaSupport.swift
        Sources/Orbit/Core/QuitProtectionSupport.swift
        Sources/Orbit/Core/QuitProtectionStrings.swift
        Sources/Orbit/Core/Defaults.swift
        Sources/Orbit/Core/NotchStrings.swift
        Sources/Orbit/Core/NotchTourStrings.swift
        Sources/Orbit/Core/NotchEditorStrings.swift
        Sources/Orbit/UI/Settings/NotchSettingsTabRow.swift
        Sources/Orbit/Core/NotchActivityStrings.swift
        Sources/Orbit/Services/Notch/NotchTimerSupport.swift
        Sources/Orbit/Services/Notch/NotchTimerAlert.swift
        Sources/Orbit/UI/Notch/NotchIslandAlert.swift
        Sources/Orbit/Services/Notch/NotchAccessorySupport.swift
        Sources/Orbit/Services/QuickTools/CameraPreviewSupport.swift
        Sources/Orbit/Core/NotchMusicExtrasStrings.swift
        Sources/Orbit/Core/NotchClipboardSizeStrings.swift
        Sources/Orbit/Services/Notch/NotchLyricsSupport.swift
        Sources/Orbit/Services/Notch/NotchQueueSupport.swift
        Sources/Orbit/Services/Notch/NotchPreferredPlayer.swift
        Sources/Orbit/Core/NotchFilesStrings.swift
        Sources/Orbit/Core/NotchWatchStrings.swift
        Sources/Orbit/Services/Notch/NotchWatchSupport.swift
        Sources/Orbit/Core/NotchMascotStrings.swift
        Sources/Orbit/Services/Notch/NotchMascotSupport.swift
        Sources/Orbit/Services/CommandBar/CommandBarDropletMotion.swift
        Sources/Orbit/Services/Notch/NotchFileToolsSupport.swift
        Sources/Orbit/Services/Notch/NotchDownloadSupport.swift
        Sources/Orbit/Services/Notch/NotchDownloadProgressObserver.swift
        Sources/Orbit/Core/NotchCalendarStrings.swift
        Sources/Orbit/Core/NotchNotificationStrings.swift
        Sources/Orbit/Core/NotchGestureStrings.swift
        Sources/Orbit/Core/NotchAgentStrings.swift
        Sources/Orbit/Core/CodexAccountStrings.swift
        Sources/Orbit/Services/Notch/NotchAgentSupport.swift
        Sources/Orbit/Core/NotchLockScreenStrings.swift
        Sources/Orbit/Services/Notch/NotchLockScreenSupport.swift
        Sources/Orbit/Services/AgentUsage/AgentUsageModels.swift
        Sources/Orbit/Services/AgentUsage/AgentPricing.swift
        Sources/Orbit/Services/AgentUsage/AgentLogObject.swift
        Sources/Orbit/Services/AgentUsage/AgentLogParser.swift
        Sources/Orbit/Services/AgentUsage/Harness/AgentHarnessReader.swift
        Sources/Orbit/Services/AgentUsage/Harness/ClaudeReader.swift
        Sources/Orbit/Services/AgentUsage/Harness/CodexReader.swift
        Sources/Orbit/Services/AgentUsage/Harness/OpenCodeReader.swift
        Sources/Orbit/Services/AgentUsage/Harness/CopilotReader.swift
        Sources/Orbit/Services/AgentUsage/AgentUsageSummary.swift
        Sources/Orbit/Services/AgentUsage/AgentUsageStore.swift
        Sources/Orbit/Services/AgentUsage/AgentUsageArchive.swift
        Sources/Orbit/Services/AgentUsage/AgentClaudeAppUsage.swift
        Sources/Orbit/Services/AgentUsage/AgentCLIConversation.swift
        Sources/Orbit/Services/AgentUsage/AgentClaudeServer.swift
        Sources/Orbit/Services/AgentUsage/AgentCodexServer.swift
        Sources/Orbit/Services/AgentUsage/CodexAccountLimits.swift
        Sources/Orbit/Services/AgentUsage/CodexProfileLimitsService.swift
        Sources/Orbit/Services/AgentUsage/AgentOpenCodeReader.swift
        Sources/Orbit/Services/Notch/NotchGestureSupport.swift
        Sources/Orbit/Services/Notch/NotchSectionPaging.swift
        Sources/Orbit/Services/Notch/NotchSliderEditing.swift
        Sources/Orbit/Services/Notch/NotchNotificationSupport.swift
        Sources/Orbit/Services/Notch/NotchNotificationReaderCore.swift
        Sources/Orbit/Services/Notch/NotchCalendarSupport.swift
        Sources/Orbit/Services/Notch/NotchKeepAwakeSupport.swift
        Sources/Orbit/Services/Notch/NotchSupport.swift
        Sources/Orbit/Services/Notch/NotchAudioLevelSupport.swift
        Sources/Orbit/Services/Notch/NotchVolumeKeyGate.swift
        Sources/Orbit/Services/Notch/NotchMusicSupport.swift
        Sources/Orbit/UI/Notch/NotchDecorativeClock.swift
        Sources/Orbit/Services/Notch/NotchBrowserArtworkSupport.swift
        Sources/Orbit/UI/Notch/NotchEqualizerBars.swift
        Sources/Orbit/UI/Notch/NotchScrollEdgeFade.swift
        Sources/Orbit/UI/Notch/NotchAgentAnimationView.swift
        Sources/Orbit/UI/WindowVisibilityReader.swift
        Sources/Orbit/Services/Notch/NotchMusicAutomationSupport.swift
        Sources/Orbit/Services/Notch/NotchMusicAutomation.swift
        Sources/Orbit/Services/Notch/NotchPlaybackSource.swift
        Sources/Orbit/Services/Notch/NotchPlaybackCommand.swift
        Sources/Orbit/Services/Notch/NotchMusicCommandWriter.swift
        Sources/Orbit/Core/FeatureCatalog.swift
        Sources/Orbit/Core/FeaturePresets.swift
        Sources/Orbit/Core/FeatureHubStrings.swift
        Sources/Orbit/Core/ShortcutSettingsStrings.swift
        Sources/Orbit/Core/SettingsBackupSupport.swift
        Sources/Orbit/Core/BackupStrings.swift
        Sources/Orbit/Core/SnippetStrings.swift
        Sources/Orbit/Core/AlertSoundStrings.swift
        Sources/Orbit/Core/BrightnessStrings.swift
        Sources/Orbit/Core/MediaImageStrings.swift
        Sources/Orbit/Core/QuickToggleStrings.swift
        Sources/Orbit/Core/ScreenshotStrings.swift
        Sources/Orbit/Core/RecentCaptureStrings.swift
        Sources/Orbit/Core/RecorderStrings.swift
        Sources/Orbit/Core/RecorderShareStrings.swift
        Sources/Orbit/Core/CameraPreviewStrings.swift
        Sources/Orbit/Core/WallpaperStrings.swift
        Sources/Orbit/Services/Wallpaper/WallpaperSupport.swift
        Sources/Orbit/Core/ScratchpadStrings.swift
        Sources/Orbit/Core/FinderRenameStrings.swift
        Sources/Orbit/Core/CommandBarStrings.swift
        Sources/Orbit/Core/FeedbackStrings.swift
        Sources/Orbit/Core/RadialMenuStrings.swift
        Sources/Orbit/Core/MenuBarAppearanceStrings.swift
        Sources/Orbit/Core/AppAppearance.swift
        Sources/Orbit/Core/AppearanceStrings.swift
        Sources/Orbit/Core/GeneralSettingsStrings.swift
        Sources/Orbit/Core/SettingsPageStrings.swift
        Sources/Orbit/Core/BatteryTimeStrings.swift
        Sources/Orbit/Core/CPUCoreStrings.swift
        Sources/Orbit/Core/MonitorLayoutStrings.swift
        Sources/Orbit/Core/KeepAwakeStrings.swift
        Sources/Orbit/Core/BluetoothSleepStrings.swift
        Sources/Orbit/Core/PermissionGuideStrings.swift
        Sources/Orbit/Core/FanControlStrings.swift
        Sources/Orbit/Core/ConnectedDevicesStrings.swift
        Sources/Orbit/Services/FanControl/FanControlSupport.swift
        Sources/Orbit/Services/FanControl/FanControlResumeSupport.swift
        Sources/Orbit/Services/Snippets/TextSnippetSupport.swift
        Sources/Orbit/Services/RadialMenu/RadialMenuSupport.swift
        Sources/Orbit/Services/QuickTools/ScratchpadSupport.swift
        Sources/Orbit/Services/QuickTools/ScratchpadStore.swift
        Sources/Orbit/Services/KillProcess/KillProcessSupport.swift
        Sources/Orbit/Services/Recorder/RecorderSupport.swift
        Sources/Orbit/Services/Recorder/RecorderSampleTiming.swift
        Sources/Orbit/Services/Recorder/RecorderWriter.swift
        Sources/Orbit/Services/Recorder/RecorderCaptureEngine.swift
        Sources/Orbit/Core/RecorderExportStrings.swift
        Sources/Orbit/Services/Recorder/RecorderComposer.swift
        Sources/Orbit/Services/Recorder/RecorderComposerPlan.swift
        Sources/Orbit/Services/Recorder/RecorderCursorSprite.swift
        Sources/Orbit/Services/Recorder/RecorderTextRenderer.swift
        Sources/Orbit/Services/Recorder/RecorderImageRenderer.swift
        Sources/Orbit/Services/Recorder/RecorderExporter.swift
        Sources/Orbit/Services/Recorder/RecorderGIFClipboard.swift
        Sources/Orbit/Services/Recorder/RecorderGIFWriter.swift
        Sources/Orbit/Services/Recorder/RecorderGIFWorkspace.swift
        Sources/Orbit/Services/Recorder/RecorderComposition.swift
        Sources/Orbit/Services/Recorder/RecordingSharingSupport.swift
        Sources/Orbit/Services/PrivateFileStore.swift
        Sources/Orbit/Services/Recorder/RecorderTakeStore.swift
        Sources/Orbit/Services/Recorder/RecorderPresetImageStore.swift
        Sources/Orbit/Services/Recorder/RecorderMotion.swift
        Sources/Orbit/Services/Recorder/RecorderPointerTrack.swift
        Sources/Orbit/Services/Recorder/RecorderTypingTrack.swift
        Sources/Orbit/Services/Recorder/RecorderTimeline.swift
        Sources/Orbit/Services/Recorder/RecorderTextOverlay.swift
        Sources/Orbit/Services/Recorder/RecorderImageOverlay.swift
        Sources/Orbit/Services/Recorder/RecorderBlurRegion.swift
        Sources/Orbit/Services/Recorder/RecorderEditDocument.swift
        Sources/Orbit/Core/AppInfo.swift
        Sources/Orbit/Core/GlobalShortcut.swift
        Sources/Orbit/Core/SymbolicHotKeys.swift
        Sources/Orbit/Services/SystemShortcutTakeoverSupport.swift
        Sources/Orbit/Core/Localization.swift
        Sources/Orbit/Core/Localizations/Strings+*.swift
        Sources/Orbit/Core/FeatureStrings.swift
        Sources/Orbit/Core/KillProcessStrings.swift
        Sources/Orbit/Core/PortManagerStrings.swift
        Sources/Orbit/Core/WhatsAppDownloadStrings.swift
        Sources/Orbit/Core/WhatsAppOrganizerStrings.swift
        Sources/Orbit/Core/ReleaseNotes.swift
        Sources/Orbit/Core/ReleaseDigest.swift
        Sources/Orbit/Core/ReleaseChangeAliases.swift
        Sources/Orbit/Core/WhatsNewStrings.swift
        Sources/Orbit/Core/URLCleaning.swift
        Sources/Orbit/Services/GeneralPasteboardAccess.swift
        Sources/Orbit/Services/Clipboard/ClipboardHistoryWrite.swift
        Sources/Orbit/Services/Audio/AirPlayRouteManager.swift
        Sources/Orbit/Services/Audio/MixerRoutingSupport.swift
        Sources/Orbit/Services/Audio/MusicLaunchSupport.swift
        Sources/Orbit/Services/Bluetooth/BluetoothSleepSupport.swift
        Sources/Orbit/UI/MenuPanel/MixerPercentNativeTextField.swift
        Sources/Orbit/UI/MenuPanel/MixerAppDragSource.swift
        Sources/Orbit/Services/Audio/BoostLimiter.swift
        Sources/Orbit/Services/Audio/MixerRender.swift
        Sources/Orbit/Services/Audio/PreciseVolumeRollerSupport.swift
        Sources/Orbit/Services/DockPreview/DockPreviewSupport.swift
        Sources/Orbit/Services/DockPreview/DockAutohideHold.swift
        Sources/Orbit/Services/SpacesOrder/SpacesOrderHold.swift
        Sources/Orbit/Services/Homebrew/HomebrewSupport.swift
        Sources/Orbit/Services/Homebrew/HomebrewEnvironment.swift
        Sources/Orbit/Services/AppUpdates/AppUpdatesSupport.swift
        Sources/Orbit/Services/AppUpdates/AppUpdateFeedSupport.swift
        Sources/Orbit/Core/AppUpdateStrings.swift
        Sources/Orbit/Core/DiskImageInstallerStrings.swift
        Sources/Orbit/Services/DiskImageInstaller/DiskImageInstallerSupport.swift
        Sources/Orbit/UI/NonModalAlert.swift
        Sources/Orbit/Services/Clipboard/ClipboardHistorySupport.swift
        Sources/Orbit/Core/ColorValue.swift
        Sources/Orbit/Services/Clipboard/ClipboardAutoClearSupport.swift
        Sources/Orbit/Services/AutoQuit/AutoQuitSupport.swift
        Sources/Orbit/Services/Shelf/ShelfSupport.swift
        Sources/Orbit/Services/Shelf/ShelfFilePromiseTransfer.swift
        Sources/Orbit/Core/ShelfPromiseDeliveryStrings.swift
        Sources/Orbit/Services/Finder/FinderRenameSupport.swift
        Sources/Orbit/Services/Update/UpdateInstallerSupport.swift
        Sources/Orbit/Core/OrbitSigning.swift
        Sources/Orbit/Services/Update/UpdateServiceSupport.swift
        Sources/Orbit/Services/InstalledApps.swift
        Sources/Orbit/Services/LaunchAtLoginSupport.swift
        Sources/Orbit/UI/Settings/SettingsSearchSupport.swift
        Sources/Orbit/UI/Settings/SettingsSidebarSupport.swift
        Sources/Orbit/UI/Settings/FeatureVisibilitySupport.swift
        Sources/Orbit/UI/Onboarding/WhatsNewSupport.swift
        Sources/Orbit/UI/Settings/SettingsWindow.swift
        Sources/Orbit/Core/SettingsNavigationStrings.swift
        Sources/Orbit/App/MenuBarSpacingSupport.swift
        Sources/Orbit/App/MenuBarAllowanceSupport.swift
        Sources/Orbit/App/ReopenRequestSupport.swift
        Sources/Orbit/App/StatusItemAnchorSupport.swift
        Sources/Orbit/Services/DockClick/DockClickSupport.swift
        Sources/Orbit/Services/Finder/CutPasteProgressSupport.swift
        Sources/Orbit/Services/Finder/CutPastePrivilegeSupport.swift
        Sources/Orbit/Services/Finder/FinderPasteImageSupport.swift
        Sources/Orbit/Services/MiddleClick/MiddleClickSupport.swift
        Sources/Orbit/Services/MouseNavigation/MouseNavigationSupport.swift
        Sources/Orbit/Services/MouseNavigation/MouseNavigationKeys.swift
        Sources/Orbit/Services/MouseButtons/MouseButtonShortcutSupport.swift
        Sources/Orbit/Services/MouseButtons/MouseSpacesGestureSupport.swift
        Sources/Orbit/Services/MouseClickDebounce/MouseClickDebounceSupport.swift
        Sources/Orbit/Services/MouseExceptions/MouseAppExceptionSupport.swift
        Sources/Orbit/Services/MouseExceptions/MouseAppExceptions.swift
        Sources/Orbit/Services/WindowServerSupport.swift
        Sources/Orbit/Services/WindowMaximizerSupport.swift
        Sources/Orbit/Core/MouseButtonStrings.swift
        Sources/Orbit/Core/MouseClickDebounceStrings.swift
        Sources/Orbit/Core/MouseExceptionStrings.swift
        Sources/Orbit/Core/ClipboardIgnoredAppsStrings.swift
        Sources/Orbit/Core/ClipboardRetentionStrings.swift
        Sources/Orbit/Core/WindowLayoutIgnoredAppsStrings.swift
        Sources/Orbit/Services/WindowLayout/WindowLayoutIgnoredApps.swift
        Sources/Orbit/Core/WindowPreviewExclusionStrings.swift
        Sources/Orbit/Core/WindowMaximizerExclusionStrings.swift
        Sources/Orbit/Core/DiskExclusionStrings.swift
        Sources/Orbit/Core/SwitcherAppRulesStrings.swift
        Sources/Orbit/Services/QuickTools/QuickToolsSupport.swift
        Sources/Orbit/Services/CommandBar/CommandBarSupport.swift
        Sources/Orbit/Services/CommandBar/CommandBarPreferences.swift
        Sources/Orbit/Services/CommandBar/CommandBarMath.swift
        Sources/Orbit/Services/CommandBar/CommandBarUnits.swift
        Sources/Orbit/Services/CommandBar/CommandBarColors.swift
        Sources/Orbit/Services/CommandBar/CommandBarEmoji.swift
        Sources/Orbit/Services/CommandBar/CommandBarLinks.swift
        Sources/Orbit/Services/CommandBar/CommandBarDates.swift
        Sources/Orbit/Services/CommandBar/CommandBarRowShortcuts.swift
        Sources/Orbit/Services/CommandBar/CommandBarSystemSettingsSupport.swift
        Sources/Orbit/Services/CommandBar/CommandBarFileSearchSupport.swift
        Sources/Orbit/Services/CommandBar/CommandBarQueryMemory.swift
        Sources/Orbit/Services/SpotlightNamesSupport.swift
        Sources/Orbit/Services/QuickTools/MicMuteSupport.swift
        Sources/Orbit/Services/QuickTools/QuickTogglesSupport.swift
        Sources/Orbit/Services/QuickTools/ScreenshotCapturePolicy.swift
        Sources/Orbit/Services/QuickTools/ScreenshotSupport.swift
        Sources/Orbit/Services/QuickTools/ScreenshotCanvasSupport.swift
        Sources/Orbit/UI/Settings/ScreenCaptureToolPicker.swift
        Sources/Orbit/UI/Settings/MonitorToken.swift
        Sources/Orbit/Services/QuickTools/ScreenshotRenderer.swift
        Sources/Orbit/Services/QuickTools/ScreenshotImageLayerRendering.swift
        Sources/Orbit/Services/QuickTools/RecentCaptureStore.swift
        Sources/Orbit/Services/QuickTools/ScreenshotSharingSupport.swift
        Sources/Orbit/Services/QuickTools/WindowActivationPolicy.swift
        Sources/Orbit/Services/KeyboardDebounce/KeyboardDebounceSupport.swift
        Sources/Orbit/Services/SuperKey/SuperKeySupport.swift
        Sources/Orbit/Services/SuperKey/SuperKeyMappingGuard.swift
        Sources/Orbit/Core/SuperKeyStrings.swift
        Sources/Orbit/Core/InputSourceSelection.swift
        Sources/Orbit/Services/SessionActivity.swift
        Sources/Orbit/Services/SessionActivitySupport.swift
        Sources/Orbit/Services/EventTimestamp.swift
        Sources/Orbit/Services/OwnKeyEvent.swift
        Sources/Orbit/Services/ScrollWheelSupport.swift
        Sources/Orbit/Services/HorizontalWheelScrolling.swift
        Sources/Orbit/Services/SmoothScrollSupport.swift
        Sources/Orbit/Services/MouseAcceleration/MouseAccelerationSupport.swift
        Sources/Orbit/Services/FocusFollowsMouse/FocusFollowsMouseSupport.swift
        Sources/Orbit/Services/AssistiveKeyboard.swift
        Sources/Orbit/Services/Switcher/SwitcherModels.swift
        Sources/Orbit/Services/Switcher/WindowServerCaptureQueue.swift
        Sources/Orbit/Services/Switcher/SwitcherSupport.swift
        Sources/Orbit/Services/Switcher/SpaceHopSupport.swift
        Sources/Orbit/Services/Switcher/WindowUseOrder.swift
        Sources/Orbit/Services/Metrics/MetricFormat.swift
        Sources/Orbit/Services/Metrics/VMStatisticsDecoder.swift
        Sources/Orbit/Services/KeepAwakeAutomationSupport.swift
        Sources/Orbit/Services/SudoersSupport.swift
        Sources/Orbit/Services/Metrics/BatteryTimeSupport.swift
        Sources/Orbit/Services/Metrics/BatteryPowerSupport.swift
        Sources/Orbit/Services/BoundedProcessRunner.swift
        Sources/Orbit/Services/DetachedProcess.swift
        Sources/Orbit/Services/ShellSupport.swift
        Sources/Orbit/Services/PortManager/PortManagerSupport.swift
        Sources/Orbit/Services/Metrics/NetworkProcessSupport.swift
        Sources/Orbit/Services/Metrics/NetworkSampler.swift
        Sources/Orbit/Services/Metrics/NetworkAddressService.swift
        Sources/Orbit/Services/Metrics/SpeedTest.swift
        Sources/Orbit/Services/Metrics/PeripheralBatterySampler.swift
        Sources/Orbit/Services/Metrics/PeripheralBatterySupport.swift
        Sources/Orbit/Services/Metrics/DiskSupport.swift
        Sources/Orbit/Services/Metrics/MonitorSamplingPolicy.swift
        Sources/Orbit/Services/Metrics/USBDeviceSampler.swift
        Sources/Orbit/Services/Metrics/CPUCoreSampler.swift
        Sources/Orbit/Services/Metrics/MaxCapacityProbe.swift
        Sources/Orbit/Services/Metrics/TemperatureSensorSelector.swift
        Sources/Orbit/Services/Metrics/SustainedAlertGate.swift
        Sources/Orbit/Services/WindowLayout/WindowLayoutSupport.swift
        Sources/Orbit/Services/WindowLayout/WindowGestureSupport.swift
        Sources/Orbit/Core/WindowDirectionalStrings.swift
        Sources/Orbit/Core/PointerDisplayStrings.swift
        Sources/Orbit/Core/GraphScaleStrings.swift
        Sources/Orbit/Core/NotchLowBatteryStrings.swift
        Sources/Orbit/Services/CleaningMode/CleaningUnlockCounter.swift
        Sources/Orbit/Services/CleaningMode/CleaningMouseReleaseGate.swift
        Sources/Orbit/Services/Display/ExtraBrightnessSupport.swift
        Sources/Orbit/Services/Display/BrightnessSupport.swift
        Sources/Orbit/Services/Display/LidDimmingSupport.swift
        Sources/Orbit/Services/Cleaner/CleanerSupport.swift
        Sources/Orbit/Services/Cleaner/CleanerPolicy.swift
        Sources/Orbit/Services/Cleaner/CleanerSchedule.swift
        Sources/Orbit/Services/Uninstall/UninstallerSupport.swift
        Sources/Orbit/Services/ManagedDownloads/WhatsAppDownloadSupport.swift
        Sources/Orbit/Core/SecureInputSupport.swift
        Tests/*.swift
        build/generated-tests/*.swift
    )
    TEST_OUTPUT_FILE_MAP="$TEST_OBJECT_DIR/output-file-map.json"
    write_swift_output_file_map "$TEST_OUTPUT_FILE_MAP" "$TEST_OBJECT_DIR" "${TEST_SOURCES[@]}"
    echo "▸ Building & running tests against $(basename "$SDK")…"
    swiftc -Onone -incremental -enable-batch-mode -j "$(sysctl -n hw.logicalcpu)" \
        -module-name OrbitTests -output-file-map "$TEST_OUTPUT_FILE_MAP" \
        -target "$TARGET" -sdk "$SDK" "${SDK_COMPAT_FLAGS[@]}" \
        "${VM_STATISTICS_COMPAT_FLAGS[@]}" "${TEST_SOURCES[@]}" -o build/metrics-tests
    test_status=0
    ./build/metrics-tests "${TEST_ARGS[@]}" || test_status=$?
    if (( ${#TEST_ARGS} == 0 )); then
        ./Tests/PreferenceCleanupTests.sh || test_status=1
        ./Tests/UninstallSpacesTests.sh || test_status=1
        ./Tests/DeveloperInstallIsolationTests.sh || test_status=1
    fi
    discard_test_preferences || test_status=1
    exit $test_status
fi

echo "▸ Compiling ($BUILD_CONFIGURATION) against $(basename "$SDK")…"
APP_SOURCES=(Sources/Orbit/**/*.swift)
if (( ! DEV )); then
    # A release starts from an empty build directory, so nothing an earlier
    # build left behind (an old icon catalog, a staged bundle) can reach it.
    # Only the compiler's incremental records stay: they rebuild whatever
    # changed since, and a fresh checkout has none.
    find build -mindepth 1 -maxdepth 1 ! -name objects -exec rm -rf {} + 2>/dev/null || true
fi
# Orbit's maintenance window (Dashboard, Energy, Cleanup, Disk Analyzer, …) is
# two separate modules, OrbitCore and OrbitMaintenance, so their types never
# collide with the menu bar app's. Built as static libraries and linked in.
echo "▸ Compiling Orbit maintenance modules…"
ORBIT_MODULE_DIR="build/modules"
mkdir -p "$ORBIT_MODULE_DIR"
swiftc "${APP_OPTIMIZATION_FLAGS[@]}" -parse-as-library -static -emit-library -emit-module \
    -module-name OrbitCore -emit-module-path "$ORBIT_MODULE_DIR/OrbitCore.swiftmodule" \
    -target "$TARGET" -sdk "$SDK" "${SDK_COMPAT_FLAGS[@]}" \
    Sources/OrbitCore/*.swift -o "build/libOrbitCore.a"
swiftc "${APP_OPTIMIZATION_FLAGS[@]}" -parse-as-library -static -emit-library -emit-module \
    -module-name OrbitMaintenance -emit-module-path "$ORBIT_MODULE_DIR/OrbitMaintenance.swiftmodule" \
    -I "$ORBIT_MODULE_DIR" -target "$TARGET" -sdk "$SDK" "${SDK_COMPAT_FLAGS[@]}" \
    Sources/OrbitMaintenance/*.swift -o "build/libOrbitMaintenance.a"
ORBIT_MODULE_FLAGS=(-I "$ORBIT_MODULE_DIR" build/libOrbitMaintenance.a build/libOrbitCore.a)

APP_OBJECT_DIR="build/objects/$EXECUTABLE"
mkdir -p build "$APP_OBJECT_DIR"
APP_OUTPUT_FILE_MAP="$APP_OBJECT_DIR/output-file-map.json"
write_swift_output_file_map "$APP_OUTPUT_FILE_MAP" "$APP_OBJECT_DIR" "${APP_SOURCES[@]}"
# Without -j the driver compiles one file at a time, and without batch mode
# each file's compiler parses the whole module again: a clean release took a
# quarter of an hour. Batches share that work and run on every core, and the
# optimization stays per file, as before.
swiftc "${APP_OPTIMIZATION_FLAGS[@]}" -incremental -enable-batch-mode -j "$(sysctl -n hw.logicalcpu)" \
    -output-file-map "$APP_OUTPUT_FILE_MAP" \
    -target "$TARGET" -sdk "$SDK" "${SDK_COMPAT_FLAGS[@]}" "${VM_STATISTICS_COMPAT_FLAGS[@]}" "${HID_EVENT_SYSTEM_FLAGS[@]}" \
    "${BUILD_VARIANT_FLAGS[@]}" "${ORBIT_MODULE_FLAGS[@]}" \
    "${APP_SOURCES[@]}" -o "build/$EXECUTABLE"

echo "▸ Compiling protected fan helper…"
swiftc -O -target "$TARGET" -sdk "$SDK" "${SDK_COMPAT_FLAGS[@]}" "${BUILD_VARIANT_FLAGS[@]}" \
    Sources/Orbit/Services/FanControl/FanControlSupport.swift \
    Sources/Orbit/Services/FanControl/FanControlXPC.swift \
    Sources/Orbit/Core/OrbitSigning.swift \
    Sources/Orbit/Services/SystemMonitor/SMCClient.swift \
    Sources/Orbit/Services/Metrics/TemperatureSensorSelector.swift \
    Sources/Orbit/Services/FanControl/FanControlHardware.swift \
    Sources/FanControlHelper/main.swift \
    -o "build/$FAN_HELPER_ID"
"build/$FAN_HELPER_ID" --selftest

echo "▸ Compiling Now Playing adapter…"
swiftc -O -target "$TARGET" -sdk "$SDK" "${SDK_COMPAT_FLAGS[@]}" -emit-library \
    -module-name OrbitNowPlaying \
    Sources/NowPlayingAdapter/NowPlayingAdapter.swift \
    Sources/NowPlayingAdapter/NowPlayingQueue.swift \
    Sources/NowPlayingAdapter/NowPlayingSelection.swift \
    Sources/Orbit/Services/Notch/NotchPlaybackSource.swift \
    Sources/Orbit/Services/Notch/NotchPlaybackCommand.swift \
    -o "build/$NOW_PLAYING_ADAPTER"

echo "▸ Generating app icon…"
swift Tools/MakeIcon.swift build/AppIcon.iconset
xattr -c -r build/AppIcon.iconset build/AppIcon.icns build/MenuBarIcon.png build/MenuBarIcon@2x.png build/BrandMark.png 2>/dev/null || true
ACTOOL_BIN="$(xcrun --find actool 2>/dev/null || true)"
ICON_TMP="$(mktemp -d)"
ADAPTIVE_SKIP=""
if [[ ! -d Resources/Brand/AppIcon.icon ]]; then
    ADAPTIVE_SKIP="no Icon Composer source (Orbit ships AppIcon-Default.png only)"
elif [[ -z "$ACTOOL_BIN" ]]; then
    ADAPTIVE_SKIP="actool not found (adaptive icons need Xcode 26+)"
else
    echo "▸ Compiling adaptive icon catalog…"
    # actool crashes on File Provider-synced paths, so compile a local copy.
    ditto "Resources/Brand/AppIcon.icon" "$ICON_TMP/AppIcon.icon"
    # Xcode 27 beta actool requires the --compile target directory to already exist.
    mkdir -p "$ICON_TMP/catalog"
    if "$ACTOOL_BIN" "$ICON_TMP/AppIcon.icon" \
            --compile "$ICON_TMP/catalog" \
            --app-icon AppIcon \
            --platform macosx \
            --target-device mac \
            --minimum-deployment-target 14.0 \
            --enable-on-demand-resources NO \
            --output-partial-info-plist "$ICON_TMP/partial-info.plist" \
            >"$ICON_TMP/actool.log" 2>&1 && [[ -s "$ICON_TMP/catalog/Assets.car" ]]; then
        mv "$ICON_TMP/catalog/Assets.car" build/Assets.car
    else
        ADAPTIVE_SKIP="actool could not compile the catalog"
    fi
fi
if [[ -n "$ADAPTIVE_SKIP" ]]; then
    cp "$ICON_TMP/actool.log" build/actool-failure.log 2>/dev/null || true
    echo "  adaptive icon skipped: $ADAPTIVE_SKIP (Dock falls back to AppIcon.icns)"
fi
echo "▸ Assembling and signing bundle…"
STAGE_TMP="$(mktemp -d)"
STAGE="$STAGE_TMP/$APP_NAME.app"
mkdir -p "$STAGE/Contents/MacOS" "$STAGE/Contents/Resources" \
    "$STAGE/Contents/Library/LaunchDaemons" "$STAGE/Contents/Library/LaunchServices"
cp "build/$EXECUTABLE" "$STAGE/Contents/MacOS/$EXECUTABLE"
cp "build/$FAN_HELPER_ID" "$STAGE/Contents/Library/LaunchServices/$FAN_HELPER_ID"
mkdir -p "$STAGE/Contents/Frameworks"
cp "build/$NOW_PLAYING_ADAPTER" "$STAGE/Contents/Frameworks/$NOW_PLAYING_ADAPTER"
cp Resources/now-playing.pl "$STAGE/Contents/Resources/now-playing.pl"
cp Resources/agent-prices.json "$STAGE/Contents/Resources/agent-prices.json"
cp Resources/com.orbit.Orbit.fan-control.plist \
    "$STAGE/Contents/Library/LaunchDaemons/$FAN_HELPER_ID.plist"
cp Resources/Info.plist "$STAGE/Contents/Info.plist"
cp CHANGELOG.md "$STAGE/Contents/Resources/CHANGELOG.md"
for lproj in Resources/*.lproj(N); do
    cp -R "$lproj" "$STAGE/Contents/Resources/"
done
if (( DEV )); then
    # A distinct identity so the Developer build installs and runs next to the
    # official app, with its own permissions, preferences and login item.
    /usr/libexec/PlistBuddy -c "Set :CFBundleIdentifier $APP_BUNDLE_ID" "$STAGE/Contents/Info.plist"
    /usr/libexec/PlistBuddy -c "Set :CFBundleName $APP_NAME" "$STAGE/Contents/Info.plist"
    /usr/libexec/PlistBuddy -c "Set :CFBundleDisplayName $APP_NAME" "$STAGE/Contents/Info.plist"
    /usr/libexec/PlistBuddy -c "Set :CFBundleExecutable $EXECUTABLE" "$STAGE/Contents/Info.plist"
    FAN_PLIST="$STAGE/Contents/Library/LaunchDaemons/$FAN_HELPER_ID.plist"
    /usr/libexec/PlistBuddy -c "Set :Label $FAN_HELPER_ID" "$FAN_PLIST"
    /usr/libexec/PlistBuddy -c "Set :BundleProgram Contents/Library/LaunchServices/$FAN_HELPER_ID" "$FAN_PLIST"
    /usr/libexec/PlistBuddy -c "Delete :MachServices:com.orbit.Orbit.fan-control" "$FAN_PLIST"
    /usr/libexec/PlistBuddy -c "Add :MachServices:$FAN_HELPER_ID bool true" "$FAN_PLIST"
    # Stamp the source commit + build time so the running dev app shows (in About)
    # exactly which code it was compiled from. Lets you verify it matches HEAD before
    # testing, instead of unknowingly running a stale build. Dev-only; never shipped.
    SHA="$(git rev-parse --short HEAD 2>/dev/null || echo unknown)"
    [[ -n "$(git status --porcelain 2>/dev/null)" ]] && SHA="$SHA-dirty"
    /usr/libexec/PlistBuddy -c "Add :OrbitBuildCommit string '$SHA · $(date '+%Y-%m-%d %H:%M')'" "$STAGE/Contents/Info.plist"
    echo "  stamped dev build: $SHA"
fi
FAN_HELPER_VERSION="$(
    export LC_ALL=C
    /usr/bin/shasum -a 256 \
        "$STAGE/Contents/Library/LaunchServices/$FAN_HELPER_ID" \
        "$STAGE/Contents/Library/LaunchDaemons/$FAN_HELPER_ID.plist" \
        | /usr/bin/awk '{print $1}' | /usr/bin/shasum -a 256 \
        | /usr/bin/awk '{print $1}'
)"
/usr/libexec/PlistBuddy -c "Add :OrbitFanControlHelperVersion string '$FAN_HELPER_VERSION'" \
    "$STAGE/Contents/Info.plist"
printf 'APPL????' > "$STAGE/Contents/PkgInfo"
cp build/AppIcon.icns "$STAGE/Contents/Resources/AppIcon.icns"
cp build/MenuBarIcon.png build/MenuBarIcon@2x.png build/BrandMark.png "$STAGE/Contents/Resources/"
if [[ -f build/Assets.car ]]; then
    cp build/Assets.car "$STAGE/Contents/Resources/Assets.car"
fi
if [[ -d Resources/Gifs ]]; then
    mkdir -p "$STAGE/Contents/Resources/Gifs"
    cp Resources/Gifs/*.gif "$STAGE/Contents/Resources/Gifs/"
fi
if ! cmp -s Resources/Gifs/highlights-notch.gif "$STAGE/Contents/Resources/Gifs/highlights-notch.gif"; then
    echo "Dynamic Island tour GIF is missing or differs from the bundled copy" >&2
    exit 1
fi
if [[ -d Resources/Images ]]; then
    mkdir -p "$STAGE/Contents/Resources/Images"
    cp Resources/Images/* "$STAGE/Contents/Resources/Images/"
fi
xattr -c -r "$STAGE" 2>/dev/null || true

# Signing, in order of preference:
#   1. Developer ID Application — the real, Apple-issued identity used for
#      notarized releases. Signed with the hardened runtime (required for
#      notarization), the app's entitlements and a secure timestamp. Gives a
#      stable, team-based designated requirement, so permissions persist across
#      updates AND Gatekeeper shows no "unverified developer" warning.
#   2. "Orbit Utils Signing" — the legacy stable self-signed identity, kept
#      as a fallback so contributors without a Developer ID still get a constant
#      designated requirement across their local builds.
#   3. Ad-hoc — fresh clone with no identity at all.
DEVID="$(developer_id_identity)"
codesign_app() {
    local target="$1"
    if [[ -n "$DEVID" ]]; then
        codesign_with_timestamp_retry --force --strip-disallowed-xattrs --options runtime --timestamp \
            --entitlements "$ENTITLEMENTS" --sign "$DEVID" "$target"
    elif legacy_identity_installed; then
        codesign --force --strip-disallowed-xattrs --sign "$LEGACY_IDENTITY" "$target"
    else
        codesign --force --strip-disallowed-xattrs --sign - "$target"
    fi
}

codesign_fan_helper() {
    local target="$1"
    if [[ -n "$DEVID" ]]; then
        codesign_with_timestamp_retry --force --strip-disallowed-xattrs --options runtime --timestamp \
            --identifier "$FAN_HELPER_ID" --sign "$DEVID" "$target"
    elif legacy_identity_installed; then
        codesign --force --strip-disallowed-xattrs --identifier "$FAN_HELPER_ID" \
            --sign "$LEGACY_IDENTITY" "$target"
    else
        codesign --force --strip-disallowed-xattrs --identifier "$FAN_HELPER_ID" --sign - "$target"
    fi
}

codesign_now_playing_adapter() {
    local target="$1"
    if [[ -n "$DEVID" ]]; then
        codesign_with_timestamp_retry --force --strip-disallowed-xattrs --options runtime --timestamp \
            --identifier "$NOW_PLAYING_ADAPTER_ID" --sign "$DEVID" "$target"
    elif legacy_identity_installed; then
        codesign --force --strip-disallowed-xattrs --identifier "$NOW_PLAYING_ADAPTER_ID" \
            --sign "$LEGACY_IDENTITY" "$target"
    else
        codesign --force --strip-disallowed-xattrs --identifier "$NOW_PLAYING_ADAPTER_ID" --sign - "$target"
    fi
}

sign_bundle() {
    local bundle="$1"
    local executable="$bundle/Contents/MacOS/$EXECUTABLE"
    local helper="$bundle/Contents/Library/LaunchServices/$FAN_HELPER_ID"
    local adapter="$bundle/Contents/Frameworks/$NOW_PLAYING_ADAPTER"

    if [[ -n "$DEVID" ]]; then
        echo "  signing with Developer ID (hardened runtime): $DEVID"
    elif legacy_identity_installed; then
        echo "  signing with legacy self-signed identity: $LEGACY_IDENTITY"
    else
        echo "  signing ad-hoc (no identity installed — run Tools/setup-signing.sh)"
    fi
    [[ -f "$helper" ]] && codesign_fan_helper "$helper"
    [[ -f "$adapter" ]] && codesign_now_playing_adapter "$adapter"
    codesign_app "$bundle"

    # If local filesystem metadata invalidates the first signature, sign once
    # more. The installed Developer bundle is signed again after the final copy.
    if ! codesign --verify --deep --strict "$bundle" >/dev/null 2>&1; then
        echo "  re-signing after filesystem metadata settled"
        xattr -c -r "$bundle" 2>/dev/null || true
        [[ -f "$helper" ]] && codesign_fan_helper "$helper"
        [[ -f "$adapter" ]] && codesign_now_playing_adapter "$adapter"
        codesign_app "$bundle"
    fi
    [[ -f "$executable" ]] && codesign --verify --strict "$executable"
    [[ -f "$helper" ]] && codesign --verify --strict "$helper"
    [[ -f "$adapter" ]] && codesign --verify --strict "$adapter"
    codesign --verify --deep --strict "$bundle"
}

sign_installed_bundle() {
    local bundle="$1"
    wait_for_install_metadata "$bundle"
    sign_bundle "$bundle"
}

sign_bundle "$STAGE"

process_is_running() {
    local proc="$1"
    if (( ${#proc} > 15 )); then
        pgrep -f "/Contents/MacOS/$proc" >/dev/null 2>&1
    else
        pgrep -x "$proc" >/dev/null 2>&1
    fi
}

stop_process() {
    local proc="$1"
    if (( ${#proc} > 15 )); then
        pkill -f "/Contents/MacOS/$proc" 2>/dev/null || true
    else
        pkill -x "$proc" 2>/dev/null || true
    fi
    for _ in {1..50}; do
        if ! process_is_running "$proc"; then
            return 0
        fi
        sleep 0.1
    done
    echo "✗ $proc is still running — quit it and retry" >&2
    return 1
}

wait_for_install_metadata() {
    local bundle="$1"
    local missing
    for _ in {1..50}; do
        missing=0
        while IFS= read -r file; do
            if ! xattr -p com.apple.provenance "$file" >/dev/null 2>&1; then
                missing=1
                break
            fi
        done < <(find "$bundle/Contents" -type f ! -path "*/_CodeSignature/*")
        if (( missing == 0 )); then
            return 0
        fi
        sleep 0.1
    done
}

# Installed development builds only need the copy in /Applications. Retaining
# another app in each checkout pollutes application search with stale builds.
if (( DEV )); then
    for old_bundle in "build/stage/$APP_NAME.app" "build/stage.noindex/$APP_NAME.app"; do
        if [[ -d "$old_bundle" ]]; then
            /System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister \
                -u "$PWD/$old_bundle" >/dev/null 2>&1 || true
            rm -rf "$old_bundle"
        fi
    done
fi

if (( !DEV || !INSTALL )); then
    STAGE_DIRECTORY="build/stage"
    (( DEV )) && STAGE_DIRECTORY="build/stage.noindex"
    mkdir -p "$STAGE_DIRECTORY"
    BUILD_STAGE="$STAGE_DIRECTORY/$APP_NAME.app"
    rm -rf "$BUILD_STAGE"
    ditto --noextattr --noqtn "$STAGE" "$BUILD_STAGE"
    xattr -c -r "$BUILD_STAGE" 2>/dev/null || true
    if ! codesign --verify --deep --strict "$BUILD_STAGE" >/dev/null 2>&1; then
        if xattr -lr "$BUILD_STAGE" 2>/dev/null | grep -Eq 'com\.apple\.(FinderInfo|ResourceFork|provenance|fileprovider)'; then
            echo "  staging copy has local filesystem metadata; temp bundle was verified"
        else
            codesign --verify --deep --strict "$BUILD_STAGE"
        fi
    fi
    echo "✓ Bundle ready: $BUILD_STAGE"
fi

if (( INSTALL )); then
    echo "▸ Installing into /Applications…"
    stop_process "$EXECUTABLE"
    # Only an official install replaces the pre-rename official apps. The
    # Developer variant must coexist with them just as it does with Orbit.
    if (( ! DEV )); then
        for legacy in "Vorss:Vorss" "Orbit Utils:OrbitUtils"; do
            name="${legacy%%:*}"; proc="${legacy##*:}"
            if [[ -d "/Applications/$name.app" ]]; then
                stop_process "$proc"
                rm -rf "/Applications/$name.app"
                echo "  (legacy $name.app removed)"
            fi
        done
    fi
    INSTALL_DEST="/Applications/$APP_NAME.app"
    rm -rf "$INSTALL_DEST"
    ditto --noextattr --noqtn "$STAGE" "$INSTALL_DEST"
    sign_installed_bundle "$INSTALL_DEST"
    echo "✓ Installed: $INSTALL_DEST"
fi
