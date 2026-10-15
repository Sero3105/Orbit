# UI Testing

UI checks are visual. Render every section offscreen with fictional data (no Screen Recording permission needed, nothing read from or written to the real system):

```bash
swift build
.build/debug/Orbit --demo --screenshots /tmp/orbit-shots -orbit.lang en \
  -orbit.access.cleanup YES -orbit.access.apps YES -AppleLocale en_IE
```

This writes one PNG per section plus `tour.gif`. Use `-orbit.lang it` to review the Italian interface.

## Checklist
- Dashboard, Energy, Processes, Cleanup, Applications and Maintenance render with no blank or clipped panels.
- Loading and empty states appear while data is missing (Disk, Applications, Processes).
- No untranslated strings when the language is switched to Italian.
- Layout uses flexible frames and minimum sizes; the only fixed widths are the sidebar (212 pt) and the application list.

Interactive flows (selection, confirmation dialogs, Move to Trash, uninstall, terminate) are verified by code review and by the `OrbitCheck` suite, not by driving the UI on real data.
