# DMG Installer Proposal

## Project
macOS Power Consumption Prometheus Exporter

## Proposal Title
DMG Installer for macOS Power Consumption Exporter

## Date
2026-03-16

---

## 1. Executive Summary

This proposal outlines the approach for creating a DMG (Disk Image) installer for the macOS Power Consumption Prometheus Exporter. The DMG installer will provide a user-friendly installation experience, including drag-and-drop application installation, proper app signing, and optional notarization for distribution outside the Mac App Store.

---

## 2. Problem Statement

Currently, the application is distributed as:
- A compiled binary (`macos-power-consumption-exporter`)
- Requires manual command-line execution with sudo
- No native macOS installation experience

Users must:
1. Download the binary
2. Manually copy to `/usr/local/bin` or another location
3. Create launch agents for auto-start
4. Configure sudo permissions for `powermetrics`

A DMG installer would provide:
- Native macOS installation experience
- Proper application bundle structure
- Easier distribution
- Potential for code signing and notarization

---

## 3. Proposed Solution

### 3.1 Application Bundle Structure

Create a proper macOS application bundle (.app) with the following structure:

```
MacOSPowerConsumptionExporter.app/
├── Contents/
│   ├── Info.plist
│   ├── MacOS/
│   │   └── macos-power-consumption-exporter
│   ├── Resources/
│   │   └── icon.icns
│   └── Scripts/
│       └── postinstall
```

### 3.2 Key Components

#### 3.2.1 Application Launcher Script
Create a wrapper script that:
- Requests sudo privileges for `powermetrics` on first launch
- Handles the actual binary execution
- Provides user feedback via dialogs

#### 3.2.2 Privileged Helper Tool
Implement a privileged helper tool (SMJobBless) to:
- Install a launch daemon for background operation
- Handle sudo-less `powermetrics` execution after initial setup
- Manage the exporter process lifecycle

#### 3.2.3 LaunchDaemon Configuration
Create a plist-based launch daemon:
```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>com.combust.macos-power-consumption-exporter</string>
    <key>ProgramArguments</key>
    <array>
        <string>/Library/PrivilegedHelperTools/com.combust.macos-power-consumption-exporter</string>
    </array>
    <key>RunAtLoad</key>
    <true/>
    <key>KeepAlive</key>
    <true/>
</dict>
</plist>
```

### 3.3 DMG Structure

The DMG will contain:
```
macos-power-consumption-exporter.dmg
├── Applications/            # Symlink to /Applications
├── MacOS Power Consumption Exporter.app/
└── README.txt              # Installation instructions
```

---

## 4. Implementation Approach

### 4.1 Phase 1: Application Bundle Creation

**Objective**: Create a proper .app bundle

**Steps**:
1. Create Xcode project or Makefile-based build
2. Define Info.plist with appropriate keys:
   - `LSUIElement` = true (menu bar app, no dock icon)
   - `NSPrincipalClass`
   - Bundle identifier
3. Add application icon (1024x1024 base)
4. Copy binary to `MacOS/` directory

### 4.2 Phase 2: Privileged Helper Installation

**Objective**: Enable sudo-less operation after installation

**Steps**:
1. Design helper tool architecture
2. Implement SMJobBless-based installation
3. Create XPC communication between app and helper
4. Handle installation prompts gracefully

### 4.3 Phase 3: DMG Creation

**Objective**: Produce distributable DMG file

**Tools**:
- **create-dmg**: Node.js tool for DMG creation
- **appdmg**: Alternative Go-based tool
- **DMG Canvas**: macOS app for manual creation

**Steps**:
1. Build the .app bundle
2. Create DMG with create-dmg or similar
3. Add Applications folder symlink
4. Set DMG window properties (size, position)
5. Apply code signing (if certificates available)

### 4.4 Phase 4: Code Signing & Notarization (Optional)

**Objective**: Enable Gatekeeper acceptance

**Steps**:
1. Obtain Apple Developer certificate
2. Sign the application bundle:
   ```bash
   codesign --deep --force --sign "Developer ID Application: Your Name" \
     --entitlements entitlements.plist "MacOS Power Consumption Exporter.app"
   ```
3. Create entitlements file for App Sandbox exceptions
4. Submit for notarization:
   ```bash
   xcrun notarytool submit "MacOS Power Consumption Exporter.app" \
     --apple-id "your@email.com" --password "app-specific-password" \
     --team-id "YOUR_TEAM_ID"
   ```
5. Staple the notarization ticket:
   ```bash
   xcrun stapler staple "MacOS Power Consumption Exporter.app"
   ```

---

## 5. Technical Specifications

### 5.1 Dependencies

| Tool | Purpose | Installation |
|------|---------|--------------|
| `create-dmg` | DMG creation | `npm install -g create-dmg` |
| `codesign` | Code signing | Built-in (Xcode) |
| `xcrun` | Notarization | Built-in (Xcode) |

### 5.2 Build Variables

```makefile
# DMG build variables
APP_NAME = MacOS Power Consumption Exporter
APP_BUNDLE_ID = com.combust.macos-power-consumption-exporter
DMG_NAME = macos-power-consumption-exporter-$(VERSION)-universal.dmg
```

### 5.3 Entitlements

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>com.apple.security.cs.allow-unsigned-executable-memory</key>
    <true/>
    <key>com.apple.security.temporary-exception.mach-lookup.global-name</key>
    <array>
        <string>com.combust.macos-power-consumption-exporter.helper</string>
    </array>
</dict>
</plist>
```

---

## 6. User Experience

### 6.1 Installation Flow

1. **Download**: User downloads DMG from releases
2. **Mount**: Double-click DMG to mount
3. **View**: DMG window shows app and Applications folder
4. **Install**: Drag app to Applications (or double-click installer)
5. **Authorize**: System prompts for admin credentials
6. **First Launch**: App requests permission to install helper
7. **Running**: Exporter starts, shows menu bar icon

### 6.2 Menu Bar Interface

Implement a menu bar application (LSUIElement) with:
- Status icon showing exporter state
- Menu items:
  - "Start Exporter"
  - "Stop Exporter"
  - "Open Metrics Page" (opens browser to localhost:8080)
  - "Preferences..."
  - "Quit"

---

## 7. Testing Plan

### 7.1 Unit Tests
- Bundle creation scripts
- Helper tool installation logic
- DMG structure validation

### 7.2 Integration Tests
- Full installation on clean macOS VM
- Privileged helper installation
- DMG mounting and installation
- Application launch and metrics endpoint

### 7.3 Manual Testing
- Code signing verification
- Notarization validation
- Gatekeeper acceptance
- Various macOS versions (12.x, 13.x, 14.x, 15.x)

---

## 8. Timeline Estimate

| Phase | Duration | Effort |
|-------|----------|--------|
| Phase 1: App Bundle | 2-3 days | Medium |
| Phase 2: Helper Tool | 3-5 days | High |
| Phase 3: DMG Creation | 1-2 days | Low |
| Phase 4: Signing/Notarization | 1-2 days | Medium |
| **Total** | **7-12 days** | - |

---

## 9. Risks and Mitigations

| Risk | Impact | Mitigation |
|------|--------|------------|
| SMJobBless complexity | High | Use simpler launch agent approach initially |
| Code signing requirements | Medium | Document certificate requirements |
| Notarization rejection | Medium | Follow Apple's guidelines closely |
| Helper tool security | High | Thorough security review, minimal permissions |
| macOS version compatibility | Medium | Test on multiple versions |

---

## 10. Alternative Approaches

### 10.1 Homebrew Distribution
- Simpler than DMG
- Popular among developers
- Requires maintaining a Homebrew tap

**Pros**: Easier updates, familiar to developers
**Cons**: Requires Homebrew installation

### 10.2 Simple ZIP Archive
- Minimal packaging
- No installation experience
- User manually extracts and runs

**Pros**: Simplest to implement
**Cons**: Poor user experience

### 10.3 PKG Installer
- Traditional macOS installer
- More complex than DMG
- Allows fine-grained installation options

**Pros**: Professional, allows pre/post install scripts
**Cons**: More complex to create

---

## 11. Recommendation

**Recommended Approach**: Phase 1 + Phase 3 (App Bundle + DMG)

Start with a simpler implementation that:
1. Creates a proper .app bundle
2. Uses a launch agent (simpler than privileged helper)
3. Packages as DMG with drag-and-drop installation

This provides a good user experience while avoiding the complexity of SMJobBless. The privileged helper can be added in a future iteration if needed.

---

## 12. Implementation Checklist

- [ ] Create Makefile targets for .app bundle creation
- [ ] Design menu bar interface
- [ ] Implement launch agent installation
- [ ] Create DMG build script
- [ ] Add code signing to build pipeline
- [ ] Test on multiple macOS versions
- [ ] Document release process

---

## 13. References

- [Apple Developer: Code Signing Guide](https://developer.apple.com/library/archive/documentation/Security/Conceptual/CodeSigningGuide/)
- [Apple Developer: Notarizing macOS Software](https://developer.apple.com/documentation/security/notarizing_macos_software_before_distribution)
- [SMJobBless Documentation](https://developer.apple.com/library/archive/documentation/Security/Conceptual/AuthorizationConcepts/authorization_services.html)
- [create-dmg GitHub](https://github.com/sindresorhus/create-dmg)

---

## 14. Implementation Status

### ✅ Completed (2026-03-16)

The following components have been implemented:

#### Phase 1: Application Bundle Creation
- [x] Created `installer/scripts/build-app-bundle.sh` script
- [x] Created `installer/templates/Info.plist` with LSUIElement (menu bar app)
- [x] Created `installer/templates/entitlements.plist` for code signing
- [x] Created `installer/app/launcher.sh` with launch agent management

#### Phase 2: Launch Agent (Simplified)
- [x] Implemented launch agent installation in launcher.sh
- [x] Auto-start functionality via `~/Library/LaunchAgents/`
- [x] Start/Stop/Status commands

#### Phase 3: DMG Creation
- [x] Created `installer/scripts/create-dmg.sh` using hdiutil
- [x] DMG includes Applications folder symlink
- [x] README.txt included in DMG

#### Phase 4: Build Automation
- [x] Added Makefile targets: `app-bundle`, `dmg`, `dmg-unsigned`, `sign`, `notarize`, `dist`
- [x] Clean build targets for build/ and dist/ directories

### Files Created

```
installer/
├── app/
│   └── launcher.sh              # App launcher with menu bar support
├── scripts/
│   ├── build-app-bundle.sh      # Builds .app bundle
│   └── create-dmg.sh            # Creates DMG installer
└── templates/
    ├── Info.plist               # App bundle configuration
    └── entitlements.plist       # Code signing entitlements
```

### Usage

```bash
# Build app bundle
make app-bundle

# Build unsigned DMG (development)
make dmg-unsigned

# Build signed DMG (requires certificates)
export CERTIFICATE="Developer ID Application: Your Name"
make dmg

# Full distribution build with signing and notarization
export CERTIFICATE="Developer ID Application: Your Name"
export APPLE_ID="your@email.com"
export APP_PASSWORD="app-specific-password"
export TEAM_ID="YOUR_TEAM_ID"
make dist
```

### Output

- **App Bundle**: `build/MacOS Power Consumption Exporter.app`
- **DMG**: `dist/MacOS Power Consumption Exporter.dmg` (~8MB)

---

## 15. Conclusion

A DMG installer will significantly improve the user experience for this macOS application. The recommended approach provides a balance between implementation complexity and user experience, making the application more accessible to users who prefer graphical installers over command-line tools.

---

*Proposal created for macOS Power Consumption Prometheus Exporter*
*Implementation completed 2026-03-16*