# claude-cleanup

If you work with many Claude Code sessions at once, idle ones pile up in old terminal tabs and worktrees. Each one holds roughly 300–500 MB, and after a week it's easy to have 20 or 30 of them sitting around doing nothing.

`claude-cleanup` finds the sessions that have been idle for a while and asks you which ones to close. The macOS window shows each session's title and its latest recap, so you can tell what each one was about. When a session is closed, its recap is written to the terminal it was running in. Every conversation stays on disk, so `claude --resume` brings any of them back.

## Requirements

- macOS 13 or later (tested on macOS 26 with Claude Code 2.1.3xx)
- [`jq`](https://jqlang.github.io/jq/)
- Xcode or the Command Line Tools, to compile the native picker. Without it, the tool falls back to a plain AppleScript list.

## Install

```bash
git clone https://github.com/loBofill/claude-cleanup.git ~/claude-cleanup
ln -s ~/claude-cleanup/claude-cleanup ~/bin/claude-cleanup   # any directory on your PATH works
claude-cleanup --build-ui
```

Then check what it would do, without changing anything:

```bash
claude-cleanup           # list the idle sessions it would offer to close
claude-cleanup --test    # open the picker; nothing is closed or snoozed
```

When you're happy with it, schedule it:

```bash
claude-cleanup --install   # runs every 10 minutes via launchd
```

## Usage

| Command | What it does |
|---|---|
| `claude-cleanup` | Lists sessions idle past the threshold, and why the others were skipped. Changes nothing. |
| `claude-cleanup --test` | Opens the picker and prints what it would close or snooze. Changes nothing. |
| `claude-cleanup --run` | Opens the picker and closes what you select. This is what launchd runs. |
| `claude-cleanup --close <PID>` | Closes one idle session right away and writes its recap to its terminal. |
| `claude-cleanup --build-ui` | Compiles the native picker next to the script. |
| `claude-cleanup --install` / `--uninstall` | Adds or removes the launchd job. |

In the picker, every session starts checked. Uncheck the ones you want to keep and press **Tanca** (close). **Refresca** (⌘R) reloads the list. The picker's text is in Catalan.

Sessions you leave open are snoozed for an hour, so the scheduled run doesn't ask about them again every 10 minutes. **Ara no** (not now), or closing the window, closes nothing and snoozes every listed session. If the picker itself fails, nothing is closed or snoozed.

## Settings

| Variable | Default | Meaning |
|---|---|---|
| `CLAUDE_CLEANUP_IDLE_HOURS` | `4` | How long a session must be idle, counting only time the Mac was awake, before it's offered. |
| `CLAUDE_CLEANUP_SNOOZE_HOURS` | `1` | How long a session you chose to keep is left alone. |

Set them when you run `--install` and they're saved into the launchd job:

```bash
CLAUDE_CLEANUP_IDLE_HOURS=6 claude-cleanup --install
```

## How it works

Every running Claude Code session keeps a small status file in `~/.claude/sessions/<pid>.json`. It holds the session ID, its folder, its status (`idle`, `busy`, …) and when that status last changed. A session counts as idle when its status is `idle` and hasn't changed for the threshold.

The threshold only counts time the Mac was awake, so a night the Mac spent asleep doesn't count toward it. If something kept the Mac awake overnight, such as a running `caffeinate`, those hours do count. Sleep periods come from the power log (`pmset -g log`), which keeps about a week of history. Time before that isn't counted. If the power log can't be read, plain clock time is used instead.

The title and recap come from the session's transcript in `~/.claude/projects/`. The title is the one you set with `/rename`, or else Claude's own title. The recap is the summary Claude writes when you step away from a session. If there's no recap, the picker shows your last message instead.

The app column (Orca, Terminal, VS Code, tmux, …) comes from walking up the session's parent processes to the first macOS app.

Before closing anything, the tool checks that:

- the PID is still a Claude process, and it started at the time recorded in the session file, so a reused PID is never touched. A session file without a start time is skipped;
- the session is still idle at the moment you press close, and again right before it's signalled. A session you went back to after opening the picker is left alone.

Closing sends `SIGTERM`, so Claude shuts down cleanly and saves the conversation. Once the process has exited, the recap is written to its terminal.

Logs and snooze state live in `~/.local/state/claude-cleanup/`. The `log` file records every session closed or snoozed, with its title and session ID.

## Caveats

This reads Claude Code's internal files: the session status files, and the `ai-title`, `custom-title` and `away_summary` entries in transcripts. They aren't a public API, so a Claude Code update can change them. When that happens, the dry run (`claude-cleanup` with no arguments) shows which sessions were skipped and why.
