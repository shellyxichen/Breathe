# Just Breathe

Take a calm pause anytime. **Just Breathe** is a calm, beautifully crafted breathing companion designed to help you slow down, reset, and reconnect with your body.

Inspired by yoga pranayama practices and James Nestor's book *Breath*, Just Breathe guides you through simple, timed breathing exercises with gentle visuals, soothing audio cues, and subtle motion. Whether you want to calm anxiety, improve focus, wind down before sleep, or take a mindful pause during the day, Just Breathe makes it easy to start with just one tap.

Choose from multiple guided breathing modes, including Box Breathing, Deep Box Breathing, Coherent Breathing, 4-7-8 Relax Breathing, and Physiological Sigh. Each session uses a soft animated halo, phase-based guidance, and optional sound cues to help you inhale, hold, and exhale at the right rhythm.

Designed for simplicity, Just Breathe removes distractions and keeps the experience centered on one thing: the breath.

## Platforms

A cross-platform breathing experience for **web**, **iOS**, and **Ray-Ban Meta smart glasses** (display).

- **Web:** [just-breathe.html](https://shellyxichen.com/just-breathe.html) — try it in the browser at [shellyxichen.com/just-breathe.html](https://shellyxichen.com/just-breathe.html)
- **iOS:** this repository (Xcode project `Breathe.xcodeproj`, scheme **Breathe**)

## Key features

### Guided breathing exercises

Practice multiple breathing patterns for relaxation, focus, recovery, and emotional regulation.

### Beautiful visual guidance

Follow a calming animated halo that expands and contracts with each breath.

### Soothing audio cues

Gentle sound feedback helps you stay in rhythm without needing to look at the screen.

### Simple session flow

Start quickly with a clean welcome screen, countdown, guided session, and calming completion moment.

### Multiple breathing modes

Includes Box, Deep Box, Coherent, Relax 4-7-8, and Physiological Sigh breathing.

### Minimal, distraction-free design

No clutter, no gamification, no pressure — just a quiet space to breathe.

## Breathing modes (iOS)

| Mode | Pattern |
|------|---------|
| Box Breathing | 4-4-4-4 |
| Deep Box Breathing | 8-8-8-8 |
| Coherent Breathing | 5-5 |
| 4-7-8 Relax Breathing | 4-7-8 |
| Physiological Sigh | 3-1-2-6 |

Sessions run as guided 2-minute flows with haptic feedback and optional ambient nature audio. Live Activities show phase and countdown on the Lock Screen and Dynamic Island.

## Requirements (iOS)

- Xcode 15 or later
- iOS 16.2+ (Live Activities)
- Apple Developer account for device testing and TestFlight

Open `Breathe.xcodeproj`, select the **Breathe** scheme, and run on a device or simulator.

## Project structure

- `Breathe/` — SwiftUI app (views, session orchestration, assets)
- `BreatheActivity/` — Live Activity widget extension
- `BreathingSessionEngine/` — Swift package for breathing mode specs and timing

## License

See source file headers for license terms (Meta Platforms, Inc. and affiliates).
