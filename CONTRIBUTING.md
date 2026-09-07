# Contributing

Bug reports and pull requests are welcome. Please describe the macOS version,
controller model and connection type, target app version and bundle ID, and
whether the problem occurs with a sidebar, panel, menu or focused input.
Do not include private conversations, credentials or unredacted system logs.

## Development

- Install Xcode Command Line Tools or Xcode on macOS.
- Run `bash test.sh` and `bash build.sh` before submitting a pull request.
- Keep UI-free state/geometry logic separate from AppKit, GameController and
  accessibility integration so it can be tested without a controller.
- Keep event delivery gated to the intended foreground app. Test cancellation
  on focus loss, pause, disconnect and reconnect when changing input behavior.
- Describe what you verified on hardware separately from automated tests.
- Avoid re-signing/reinstalling a working local app unnecessarily: ad hoc builds
  may require renewed Accessibility authorization.

## Source map

- `Sources/main.swift`: menu bar, controller mapping, event delivery and haptics.
- `Sources/HoldState.swift`: held dictation ownership and cleanup.
- `Sources/TriggerGesture.swift`: R2 analog gesture state machine.
- `Sources/StickNavigation.swift`: menu/content routing.
- `Sources/ConversationGeometry.swift`: pure scroll-target geometry.
- `Sources/ConversationLocator.swift`: accessibility element discovery.
- `Sources/notify-hook.swift`: local notification helper and input validation.
- `Sources/probe-haptics.swift`: optional standalone capability probe.
- `Tests/`: state, geometry and hook installer checks.

Contributions are provided under the repository's MIT license.
