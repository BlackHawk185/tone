# Flutter Diagnostics — 2026-06-29

## Flutter Version
```
PS C:\Users\Tim Michaud\Desktop\tone> flutter --version
Flutter 3.41.6 • channel stable • https://github.com/flutter/flutter.git
Framework • revision db50e20168 (3 months ago) • 2026-03-25 16:21:00 -0700
Engine • hash 5cdd32777948fa7a648fac915f8da7120ac7e97a (revision 425cfb54d0) (3 months ago) • 2026-03-25 20:14:42.000Z
Tools • Dart 3.11.4 • DevTools 2.54.2
```

## Dart Version
```
PS C:\Users\Tim Michaud\Desktop\tone> dart --version
Dart SDK version: 3.11.4 (stable) (Tue Mar 24 01:02:20 2026 -0700) on "windows_x64"
```

## Flutter Doctor (Verbose)
```
PS C:\Users\Tim Michaud\Desktop\tone> flutter doctor -v
[√] Flutter (Channel stable, 3.41.6, on Microsoft Windows [Version 10.0.26200.8655], locale en-US) [388ms]
    • Flutter version 3.41.6 on channel stable at C:\Users\Tim Michaud\OneDrive\Documents\flutter
    • Upstream repository https://github.com/flutter/flutter.git
    • Framework revision db50e20168 (3 months ago), 2026-03-25 16:21:00 -0700
    • Engine revision 425cfb54d0
    • Dart version 3.11.4
    • DevTools version 2.54.2
    • Feature flags: enable-web, enable-linux-desktop, enable-macos-desktop, enable-windows-desktop, enable-android,
      enable-ios, cli-animations, enable-native-assets, omit-legacy-version-file, enable-lldb-debugging,
      enable-uiscene-migration

[√] Windows Version (11 Pro 64-bit, 25H2, 2009) [925ms]

[X] Android toolchain - develop for Android devices [1,178ms]
    • Android SDK at C:\Users\Tim Michaud\AppData\Local\Android\sdk
    • Emulator version 36.5.10.0 (build_id 15081367) (CL:N/A)
    X cmdline-tools component is missing.
      Try installing or updating Android Studio.
      Alternatively, download the tools from https://developer.android.com/studio#command-line-tools-only and make sure to
      set the ANDROID_HOME environment variable.
      See https://developer.android.com/studio/command-line for more details.

[√] Chrome - develop for the web [194ms]
    • Chrome at C:\Program Files\Google\Chrome\Application\chrome.exe

[!] Visual Studio - develop Windows apps (Visual Studio Build Tools 2019 16.11.44) [193ms]
    • Visual Studio at C:\Program Files (x86)\Microsoft Visual Studio\2019\BuildTools
    • Visual Studio Build Tools 2019 version 16.11.35731.53
    • Windows 10 SDK version 10.0.19041.0
    X The current Visual Studio installation is incomplete.
      Please use Visual Studio Installer to complete the installation or reinstall Visual Studio.

[√] Connected device (3 available) [149ms]
    • Windows (desktop) • windows • windows-x64    • Microsoft Windows [Version 10.0.26200.8655]
    • Chrome (web)      • chrome  • web-javascript • Google Chrome 149.0.7827.197
    • Edge (web)        • edge    • web-javascript • Microsoft Edge 149.0.4022.62

[√] Network resources [554ms]
    • All expected network resources are available.

! Doctor found issues in 2 categories.
```

## Issues Summary

### ⚠️ Android Toolchain
- **Status**: Missing cmdline-tools component
- **Impact**: Cannot develop/deploy for Android devices
- **Resolution**: Install/update Android Studio or download command-line tools manually

### ⚠️ Visual Studio (Windows Build Tools)
- **Status**: Incomplete installation
- **Impact**: Cannot develop Windows desktop apps
- **Resolution**: Use Visual Studio Installer to complete the installation

## Environment Info
- **OS**: Windows 11 Pro (Build 25H2)
- **Flutter Location**: `C:\Users\Tim Michaud\OneDrive\Documents\flutter`
- **Android SDK**: `C:\Users\Tim Michaud\AppData\Local\Android\sdk`
