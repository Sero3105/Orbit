# Orbit Design System
Direction: premium futuristic macOS utility — precision, restraint. Idea: the orbit ring (brand mark) becomes the CPU gauge; live samples become the one moving element.
Palette (dark only): bg #0B0E11, surface #13181F, raised #1A212B, ink #EDF2F5, muted #8A97A5, accent lime #A8E04A (actions/selection/gauge), cyan #56C8DC only for disk/info, amber #E8B34B warning, red #E5605C danger. Flat colour only: no gradients, no shadows at rest; surfaces separated by tone step.
Type: system font; display 28 semibold (titles), metric 34 semibold tabular, body 13, secondary 11 muted. Two sizes dominate per screen.
Spacing: 4/8/12/16/24/32. Radii: panels 10, controls 7 (decided once). Motion: 150-250ms easeOut, respects Reduce Motion via accessibilityReduceMotion.
Health (derived, documented): disk free <10% -> Low disk; mem used >90% -> High memory pressure; CPU >85% sustained sample -> Elevated CPU; else Normal. Battery/temp unavailable states muted, never dominant.
Components: Panel, SectionTitle, NavItem, RingGauge, MeterBar, Sparkline, StatusChip, TreemapStrip, EmptyState, DangerButton.
