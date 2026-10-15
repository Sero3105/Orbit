# Project Audit (2026-10-15)
- Repo: empty directory, not a git repo. No existing code to preserve.
- Toolchain: no Xcode; Command Line Tools Swift 6.4, MacOSX27 SDK, arm64, macOS 27.0.1.
- Reference: /Applications/Mole.app v1.13.0 (com.tw93.MoleApp) present, inspected Info.plist only; not modified/copied.
- Mole CLI: github.com/tw93/Mole README read; GPL-3.0 CLI separate from proprietary native app. Orbit is an independent clean-room implementation; no Mole code/assets copied.
- Skills: ponytail+caveman active per ~/.claude/CLAUDE.md. REA/Loop Engineer not installed as skills — not claimed as used; investigation done via plist/README directly.
- Decision: SwiftPM + SwiftUI executable, hand-assembled .app bundle, ad-hoc codesign (no Xcode available).
