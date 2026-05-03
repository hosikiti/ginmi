# Ginmi

## Jump to the right Mac window in a few keystrokes

Ginmi is a lightweight macOS window switcher for people who keep a lot of windows open and do not want to cycle through them one by one. Open Ginmi, type a few letters from an app name or window title, and jump directly to the exact window you meant.

Built for fast, focused switching, Ginmi brings the beloved Contexts-style fuzzy search workflow back to modern macOS.

**Primary CTA:** Download Ginmi  
**Secondary CTA:** View on GitHub

---

## Stop Switching Apps. Switch to the Window.

Traditional app switchers stop at the app. That is not enough when you have three browser windows, four editor projects, two terminals, and a meeting note buried somewhere behind everything else.

Ginmi searches individual windows, not just apps. Type `gh is`, `arc mail`, `term api`, or any short fuzzy fragment, then press Return. Ginmi finds the matching window and brings it forward.

---

## Why Ginmi

### Finds the exact thing

Ginmi searches both app names and window titles, so you can jump to a specific browser tab window, editor project, terminal session, document, or conversation without remembering where it lives.

### Built for 2-4 keystrokes

The search flow is tuned for short queries. Non-consecutive letters, word starts, acronym-like matches, recent usage, and learned choices help the result you expect rise to the top.

### Learns what you mean

When you pick a window for a query, Ginmi remembers it. The next time you type the same shortcut, that window gets boosted, turning repeated switches into fast muscle memory.

### Works across your Mac

Ginmi uses macOS Accessibility APIs to enumerate and focus windows across apps, spaces, displays, hidden windows, minimized windows, and fullscreen work.

### Stays out of the way

Ginmi is a small native Mac utility with a floating search panel, menu bar access, configurable settings, dark mode support, and no heavy workspace metaphor to manage.

---

## Designed for People Who Live in Windows

Ginmi is made for developers, researchers, writers, operators, and anyone who keeps real work spread across many open windows.

Use it when you need to:

- Jump from an editor project to the matching terminal.
- Find the right browser window without cycling through every browser window.
- Return to a specific document or note by title.
- Switch between communication, planning, and build tools without losing flow.
- Replace repeated `Cmd + Tab` and window hunting with direct intent.

---

## How It Works

1. Open Ginmi with your shortcut or menu bar icon.
2. Type a few letters from the app name or window title.
3. Use the top result or move with the arrow keys.
4. Press Return to jump directly to that window.

Ginmi can also include installed apps in search results, so the same launcher can open apps when no running window is the right match.

---

## Feature Highlights

- Fuzzy search over running app names and window titles.
- Per-window activation, not just app activation.
- Learned query shortcuts stored locally.
- Optional installed-app search results.
- Recency weighting for common switching paths.
- Configurable behavior from the settings window.
- Menu bar access for quick control.
- Native Swift app for macOS 15 and later.
- Open-source, MIT licensed.

---

## Privacy

Ginmi runs locally on your Mac. It uses Accessibility permission so it can read window metadata and focus the window you select. Learned shortcuts are stored locally with `UserDefaults`.

Ginmi does not need an account, cloud sync, or a background web service to switch your windows.

---

## Short Version

Ginmi is the fast fuzzy window switcher for macOS.

Type what you mean. Jump to the exact window. Get back to work.

---

## FAQ

### Is Ginmi an app launcher?

Ginmi can include installed apps, but its main job is faster window switching. It is designed around getting to the exact open window you want.

### Why does Ginmi need Accessibility permission?

macOS requires Accessibility permission for apps that inspect and focus windows across other apps. Ginmi uses it to list windows, read titles, and bring the selected window forward.

### Does Ginmi replace `Cmd + Tab`?

It can complement or replace parts of that workflow. Instead of moving through apps one at a time, Ginmi lets you search directly for the window you want.

### Who is Ginmi for?

Ginmi is for Mac users who keep many windows open and value direct keyboard-driven navigation.

### Is Ginmi open source?

Yes. Ginmi is MIT licensed.
