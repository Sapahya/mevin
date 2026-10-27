# Mevin

**Switch between your kinds of work in one click.** *(Public beta)*

Mevin is a small menu bar app for macOS. You make a **profile** for each kind of work you do, for example "Day job", "Startup" or "Side project". Each profile remembers its apps and where they open: the right Chrome profile with its tabs, a Claude chat, a Figma file, a Slack workspace, folders, and Terminal tabs with their startup commands.

- **Start** a profile and everything it needs opens, in the right place.
- **Switch** to another profile and Mevin asks which of the apps on screen you still want. The rest quit politely, so any app with unsaved work shows its own Save dialog. Nothing is force quit.
- **End** a profile and choose whether to keep everything running or tidy up.
- A session clock, an optional timer and gentle check-ins help you notice when you have drifted.

## Requirements

- macOS 14 (Sonoma) or later
- Apple silicon or Intel Mac
- Google Chrome, if you want Chrome profiles in your roles

## Install

1. Go to the [Releases](../../releases) page and download `Mevin-<version>.zip` from the latest release.
2. Double-click the zip to unpack it, then drag **Mevin.app** into your **Applications** folder.
3. Open Mevin. Its icon appears in the menu bar at the top of the screen, not in the Dock.

### "Mevin can't be opened" (Open Anyway)

Mevin is a beta. It isn't notarized by Apple yet, so macOS blocks it the first time you open it. To allow it:

1. Open Mevin once. macOS says it can't verify the app. Click **Done** (or **OK**).
2. Open **System Settings > Privacy & Security**.
3. Scroll down to the **Security** section. Next to "Mevin was blocked to protect your Mac", click **Open Anyway**.
4. Confirm with your password or Touch ID, then click **Open Anyway** again.

You only need to do this once per version.

## Permissions

macOS asks for these the first time Mevin needs them. You can change them any time in **System Settings > Privacy & Security**.

| Permission | Why Mevin needs it |
|---|---|
| **Accessibility** | To see and move windows: bring a profile's apps forward, tell Chrome windows of different profiles apart, and minimize or close the right ones when you switch. Without it, Mevin shows a banner and can't tell Chrome profiles apart. |
| **Automation** (Chrome, Terminal, System Events) | To open a Chrome profile's tabs, open Terminal tabs and run a profile's startup commands, and close a Terminal window through Terminal's own confirmation. |
| **Screen Recording** (optional) | Only for **Detect profile**, as a backup way to read the Chrome profile folder from `chrome://version`. The screenshot is read on your Mac and never saved. |
| **Notifications** (optional) | For timer and check-in reminders. |

**Tip for testers:** after you update to a new Mevin version, macOS may forget the Accessibility permission. If windows stop moving, go to Privacy & Security > Accessibility, remove Mevin with "−" and add it again with "+".

## Your data stays on your Mac

- Profiles, history and settings are saved in `~/Library/Application Support/Mevin/profiles.json`. Nothing is uploaded.
- Mevin has no account, no sign in and no tracking. It never stores your passwords.
- Text recognition (Detect profile) runs on your Mac.
- The only optional online feature is **AI settings**: if you add your own OpenAI or DeepSeek key, Mevin can suggest a profile from a screenshot. It always asks before sending anything, and your key is kept in the macOS Keychain.

## Known limits (beta)

- Chrome doesn't share its list of profiles, so you link each one once by pasting its Profile Path (Mevin shows the steps) or with **Detect profile**.
- Mevin can't put windows back on a specific desktop (Space) or in full screen.
- Running tasks can't be restored, only started again.

## Feedback

This is a beta. Please report bugs and ideas in [Issues](../../issues).

## Build from source

Requires Xcode 16 or later.

```bash
make build    # Debug build
make run      # Build and open the app
make smoke    # Logic tests
make release  # Release build
```

## License

[MIT](LICENSE)
