# carnival

A single-file Bash script that turns your terminal into a chaos zone. A spinning Soviet star is locked to the top of the screen, every character of the prompt blinks in a different color, and any command's output can be rainbow-blinked on demand.

Pure Bash. Zero runtime dependencies beyond what ships in `coreutils` and `ncurses-bin`. Tested on Debian 9 (bash 4.4) and Debian 12 (bash 5.2).

## Demo

```
                *
               ***
              *****
             *******
*****************************
  ***************************
    ***********************
      ********☭********
        *****   *****
       *****     *****
      *****       *****
     ****           ****
    ***               ***

[ scroll region begins below — your prompt and command output live here ]
COMRADE@host:~$ rb ls /etc | head
```

Star color cycles through Soviet-red shades, the center symbol and corner sparkles toggle between frames, prompt characters rainbow-blink. Record an asciicast and embed it here once you have one — `asciinema rec` works well.

## Features

- Star pinned to the top of the terminal, never disturbed by command output
- Prompt is rainbow + blink, per-character coloring
- `rb` helper: rainbow-blinks the output of any command or pipeline
- Single file, ~280 lines of Bash, no external runtime deps
- Safe to source from `.bashrc` — built-in guards skip non-interactive shells, scp/rsync sessions, dumb terminals, and nested invocations
- Clean exit trap restores scroll region, PS1, and cursor visibility

## Requirements

- Bash 4.1 or newer (for `read -N1`)
- A terminal that honors DECSTBM (CSI top;bottom r) and DECSC/DECRC (`\e7` / `\e8`). Modern xterm, gnome-terminal, alacritty, kitty, foot, and iTerm2 all qualify.
- 256-color support (`TERM` containing `256color`, or any terminal that ignores unsupported SGR codes gracefully)
- Terminal at least 20 rows tall

## Install

```bash
mkdir -p ~/.local/share/carnival
curl -fsSL https://raw.githubusercontent.com/<you>/carnival/main/carnival.sh \
    -o ~/.local/share/carnival/carnival.sh
chmod 644 ~/.local/share/carnival/carnival.sh
```

Or clone:

```bash
git clone https://github.com/<you>/carnival.git ~/.local/share/carnival
```

## Wire it into ~/.bashrc

Append:

```bash
# --- carnival mode ---
# Self-guards handle non-interactive / scp / dumb-term / re-entry cases,
# so this can be sourced unconditionally. Set NO_CARNIVAL=1 to skip for one shell.
if [[ -r "$HOME/.local/share/carnival/carnival.sh" ]]; then
    source "$HOME/.local/share/carnival/carnival.sh"
fi
# --- end carnival ---
```

Open a new terminal. The script also runs as a one-off without modifying `.bashrc`:

```bash
source ~/.local/share/carnival/carnival.sh    # transform current shell
bash ~/.local/share/carnival/carnival.sh      # spawn a configured subshell
```

## Usage

Inside a carnival shell, use the prompt normally. Two extras are available:

```bash
rb ls -la                     # rainbow-blink the output of `ls -la`
dmesg | tail | rb             # rainbow-blink anything piped in
rb cat /etc/os-release
```

Exit restores the terminal:

```bash
exit         # or Ctrl-D, or Ctrl-C
```

## Environment variables

| Variable | Effect |
| --- | --- |
| `NO_CARNIVAL=1` | Skip carnival init for this shell. Useful as `NO_CARNIVAL=1 bash` to drop into a plain shell. |
| `CARNIVAL_ACTIVE` | Set automatically once carnival initializes. Exported, so child bash processes skip re-init. |
| `CARNIVAL_VERBOSE=1` | Print `carnival mode terminated. terminal restored.` on exit. Off by default to keep terminal-close silent. |

To re-enable carnival after a `NO_CARNIVAL=1` opt-out in the same shell:

```bash
unset CARNIVAL_ACTIVE
source ~/.local/share/carnival/carnival.sh
```

## How it works

A few specific tricks are doing the heavy lifting:

**Scroll region (DECSTBM).** The script reserves the top 15 rows by setting the terminal's scroll region to `rows 16..bottom` with `CSI 16;<lines>r`. Bash readline and all command output stay inside that region. The top rows are off-limits to scrolling — only the spinner draws there.

**Cursor save/restore (DECSC / DECRC).** The spinner runs in a backgrounded subshell. Each frame: hide cursor, save current cursor position with `\e7`, jump to row 1 col 1, paint the frame, restore with `\e8`, show cursor. The user's typing position is preserved across every redraw.

**Readline-aware PS1.** Each prompt character is wrapped in `\[\e[38;5;Nm\e[5m\]…\[\e[0m\]`. The `\[ \]` markers tell readline the bytes inside have zero display width. Without them, readline miscounts prompt width and line wrapping breaks at column boundaries.

**Streaming colorizer.** `rb` reads stdin one character at a time with `read -N1` (Bash 4.1+), emitting a fresh SGR sequence per char with a random index from a 25-color rainbow palette. When called with arguments (`rb ls`), the function recurses into itself via a pipe so both `rb cmd` and `cmd | rb` work; `PIPESTATUS[0]` is propagated.

**Cleanup trap.** `EXIT INT TERM HUP` triggers a handler that kills the spinner subshell, resets the scroll region with `CSI r`, restores the saved `PS1`, shows the cursor, and clears the screen.

## Customization

Everything is in `carnival.sh`. The variables you'll most likely want to touch:

| Variable | Default | What it controls |
| --- | --- | --- |
| `__CV_TOP` | `15` | Rows reserved at the top for the star. Increase for a bigger logo, decrease to give more room to your prompt. |
| `__CV_PALETTE` | 25 colors | xterm-256 indices used by both the prompt and `rb`. Reorder or replace freely. |
| `__CV_REDS` | 8 reds | Color cycle the star body pulses through. |
| `__CV_FRAME_A..D` | star + sparkles + ☭ | The four animation frames. Edit ASCII art directly. |
| `sleep 0.18` (in `__cv_spinner`) | 180 ms | Frame interval. Lower = faster spin. |
| Prompt prefix text | `'COMRADE'` | Argument to `__cv_build_ps1` inside `__cv_init`. |

Adding a fifth frame is as simple as defining `__CV_FRAME_E` and appending it to `__CV_FRAMES`.

## Terminal compatibility

| Terminal | Status |
| --- | --- |
| xterm | Works |
| gnome-terminal / VTE | Works |
| Konsole | Works |
| alacritty | Works |
| kitty | Works |
| foot (Wayland) | Works |
| iTerm2 (macOS) | Works; SGR 5 (blink) may be disabled by default — toggle in profile prefs |
| Apple Terminal.app | Works, but no blink (SGR 5 ignored) |
| tmux | DECSTBM is honored only inside the active pane. The star will sit at the top of the pane, not the tmux window. Acceptable. |
| screen (older) | DECSTBM handling is inconsistent — star area may get scrolled over |
| Web-based shells (Cloud Shell, etc.) | Mixed; test before committing to `.bashrc` |
| Linux framebuffer console | DECSTBM not implemented — do not use here |

If your terminal misbehaves, add a guard near the top of the script. Example, skip carnival inside `screen`:

```bash
[[ "$TERM" == screen* ]] && return 0
```

## Troubleshooting

**The star area gets scrolled into when output is large.** Your terminal isn't honoring DECSTBM. Check the table above. If you're in `tmux`, this should not happen inside a single pane — confirm the issue isn't actually the prompt being above the reserved area (the script logs a size warning if `LINES < 20`).

**Prompt wrapping is broken on long lines.** Almost always means the `\[ \]` non-print markers got stripped. If you've edited `__cv_build_ps1`, re-check that every escape sequence is wrapped in `\[ ... \]`.

**Terminal stays in carnival state after a crash.** The cleanup trap only fires on `EXIT INT TERM HUP`. If Bash dies hard (`kill -9`), the scroll region and PS1 won't be restored. Recover with:

```bash
printf '\e[r\e[0m\e[?25h'; clear; PS1='\u@\h:\w\$ '
```

**Blink doesn't blink.** Many terminals and macOS in particular suppress SGR 5. Re-enable in terminal preferences, or replace `${__CV_BLINK}` with `''` in `carnival.sh` and rely on the rainbow alone.

**`bash: rb: command not found` after entering carnival mode.** `rb` is a function, not an executable, defined only in the shell that sourced the script. Subprocesses (`xargs sh -c '... | rb'`) won't see it. Use `export -f rb` if you need it visible to subshells.

## License

MIT. See [LICENSE](LICENSE).
