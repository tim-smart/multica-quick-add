# Multica Quick Add: Plan

A macOS menu bar app for capturing Multica issues from anywhere. A global
hotkey summons a floating Spotlight-style panel. The text you type is sent
as a prompt to Multica's agent quick-create flow, where the selected agent
turns it into a well-formed issue.

A style example from the chatgpt app is here: ./screenshot.png

## Decisions made

- Menu bar app with a global hotkey, no Dock icon. Esc dismisses the panel.
- Single text area. The full text is the quick-create prompt; the agent
  derives title and description from it.
- Bottom row pickers: workspace, project, and "created by" (agent or
  squad, in one grouped picker).
- The app remembers the last used workspace, and the last used project and
  created-by selection per workspace.
- On submit the panel dismisses immediately and a system notification
  reports the result.
- A settings window lets you change the global hotkey (default
  Cmd+Shift+Space).
- Reads (workspaces, projects, agents) go through the multica CLI.
  Submission calls the server API directly because CLI v0.4.17 has no
  quick-create command. Swap to the CLI once it gains one.

## Quick-create API (verified against api.multica.ai)

```
POST {server_url}/api/issues/quick-create?workspace_id=<uuid>
Authorization: Bearer <token>
Content-Type: application/json

{ "prompt": "...", "agent_id": "<uuid>" }
```

- `prompt` is required.
- Exactly one of `agent_id` or `squad_id` is required, driven by the
  created-by selection.
- Optional fields seen in the daemon task payload: `project_id`,
  `quick_create_priority`, `quick_create_due_date`, attachment ids. We only
  send `project_id`.
- `server_url` and `token` come from `~/.multica/config.json`.
- Success means the task was enqueued. Failures after that surface in the
  Multica inbox as `quick_create_failed`, so our notification says "sent to
  <agent>" rather than "issue created".

## CLI commands used

```
multica workspace list --output json
multica project list --workspace-id <id> --output json
multica agent list --workspace-id <id> --output json
multica squad list --workspace-id <id> --output json
```

The CLI is resolved from `/usr/local/bin/multica`, falling back to PATH.

## Architecture

```
MulticaQuickAdd/
  MulticaQuickAddApp.swift   App entry, LSUIElement, menu bar item
  Panel/
    QuickAddPanel.swift      Nonactivating floating NSPanel host
    QuickAddView.swift       SwiftUI: text area, pickers, submit button
  Services/
    MulticaCLI.swift         Process wrapper, JSON decoding
    MulticaAPI.swift         Config loading + quick-create POST
    Models.swift             Workspace, Project, CreatedBy (agent | squad)
  Settings/
    SettingsView.swift       Settings window: hotkey recorder, launch at login
    HotKeyRecorder.swift     Control that captures a key combo
  Support/
    HotKey.swift             Carbon RegisterEventHotKey wrapper
    Notifier.swift           UserNotifications wrapper
    Settings.swift           Last-used selections and hotkey (UserDefaults)
```

Key implementation notes:

- Menu bar: `NSStatusItem` with a menu (Open, Settings, Quit).
  `LSUIElement = true` in project.yml Info.plist keys.
- Hotkey: Carbon `RegisterEventHotKey`, default Cmd+Shift+Space. No
  third-party dependencies. The stored key combo (key code + modifiers) is
  re-registered whenever it changes in settings.
- Hotkey recorder: focused control that captures the next key combo via
  `NSEvent` monitoring, with a reset-to-default button.
- Panel: `NSPanel` with `.nonactivatingPanel`, borderless, rounded corners,
  floating level, centered near the top of the active screen. Shown via the
  hotkey or menu bar click. Closes on Esc and on losing key status.
- Text area grows with content. Enter submits, Shift+Enter inserts a
  newline.
- The created-by picker lists agents and squads in two sections; the
  selection determines whether `agent_id` or `squad_id` is sent.
- Pickers cache their lists so the panel opens instantly and refresh in the
  background. Last used workspace is global; last used project and
  created-by are stored per workspace.
- Submit: close panel, fire the POST, notify on completion. Errors (CLI
  missing, not logged in, network) also arrive as notifications.
- App is unsandboxed (required to run the CLI and read
  `~/.multica/config.json`).

## Milestones

1. **Panel shell**: menu bar item, hotkey, floating panel with static UI
   matching the screenshot.
2. **Data**: CLI wrapper, load workspaces/projects/agents/squads into the
   pickers, persist selections.
3. **Submit**: config loading, quick-create POST, notifications.
4. **Polish**: settings window with hotkey recorder, launch at login,
   empty states (not logged in, no agents), `make format` and tests.

## Testing

- Unit tests for CLI JSON decoding, config.json parsing, and request
  building (`MulticaQuickAddTests`).
- CLI and API calls go behind protocols so tests inject fixtures.
- Manual: end-to-end quick-create against the Tim Smart workspace.

## Open questions

None.
