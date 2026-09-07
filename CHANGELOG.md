# Changelog

## Unreleased — open-source packaging

- Remove the separate microphone mute companion and its menu-bar icon.
- Add Chinese/English documentation, MIT license, contribution guidelines,
  an automated test entry point and macOS CI.
- Keep the main app at 0.6.2; packaging does not change its installed binary.

## 0.6.2

- Locate the chat column using the actual composer accessibility element.
- Refresh geometry after sidebar, panel and window layout changes.
- Treat sidebar lists as content rather than popup menus.

## 0.6.1

- Deliver scroll events through WindowServer hit testing.
- Distinguish focused text areas from menu navigation and display stick status.

## 0.6.0

- Add R2 light-release queueing and deep-press immediate submission.
- Add left-stick scrolling and menu selection, with dead zones and cancellation.

## 0.5.0

- Open the command menu with Options; use arrows and Return to choose a chat.

## 0.4.0

- Add Control-release handling for the original recent-chat switcher mapping.
  Superseded by the Options menu flow in 0.5.0.

## 0.3.0

- Hold dictation shortcut until the square button is released.

## 0.2.0

- Add optional local turn-end haptic notifications.

## 0.1.0

- Initial native controller-to-keyboard menu bar bridge.
