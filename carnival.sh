# carnival.sh — chaos-mode shell
# Flashing star locked at top of terminal + per-character rainbow blink prompt
# Targets:  Debian 9 (bash 4.4) and Debian 12 (bash 5.2)
#
# Usage:
#   . carnival.sh             # sourced — transforms CURRENT interactive shell (recommended)
#   bash carnival.sh          # spawns a configured interactive subshell that sources this file
#
# Inside carnival mode:
#   rb <cmd> [args...]        # run <cmd> and rainbow-blink every character of its output
#   <cmd> | rb                # rainbow-blink any pipeline output
#   exit  /  Ctrl-D  /  Ctrl-C   restores the terminal (scroll region, PS1, cursor)
#
# How it works:
#   * DECSTBM (CSI top;bottom r) carves a scroll region BELOW the top __CV_TOP rows.
#     Bash readline + all command output stays inside that region; the top rows are
#     untouched real estate that we keep redrawing the star into from a background
#     subshell.
#   * The spinner uses DECSC/DECRC (\e7 / \e8) to save and restore the user's
#     cursor around each frame, plus DECTCEM hide/show, so typing is not disturbed.
#   * Per-character color in PS1 is built by wrapping each char in
#     \[<csi>38;5;Nm\e[5m\] ... \[\e[0m\]. The \[ \] markers are critical so
#     readline knows the bytes are zero-width and computes line wrap correctly.
#   * `rb` reads its stdin one character at a time with `read -N1` (bash 4.1+),
#     emitting an SGR sequence per char with a random 256-color index.

# ---------- direct-exec bootstrap ----------
# If executed (not sourced), respawn as an interactive bash that sources us.
# This is what makes `bash carnival.sh` Just Work without the user knowing they
# need to source it.
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    __cv_self="$(readlink -f "${BASH_SOURCE[0]}")"
    exec bash --rcfile <(
        [[ -f "$HOME/.bashrc" ]] && cat "$HOME/.bashrc"
        printf '\nsource %q\n' "$__cv_self"
    ) -i
fi

# ---------- safety guards ----------
# Make this script safe to source unconditionally from ~/.bashrc.
# Bail out cleanly in any non-interactive or hostile context, and prevent
# nested re-entry when a carnival shell spawns child bash processes.
if [[ $- != *i* ]] \
   || [[ -z "${PS1:-}" ]] \
   || [[ ! -t 1 ]] \
   || [[ "${TERM:-dumb}" == "dumb" ]] \
   || [[ -n "${CARNIVAL_ACTIVE:-}" ]] \
   || [[ -n "${NO_CARNIVAL:-}" ]]; then
    return 0 2>/dev/null || exit 0
fi
# Sentinel: exported so child bash processes (e.g. `bash` from prompt) skip us.
export CARNIVAL_ACTIVE=1

# ---------- terminal control sequences ----------
__CV_ESC=$'\e'
__CV_CSI="${__CV_ESC}["
__CV_RESET="${__CV_CSI}0m"
__CV_BLINK="${__CV_CSI}5m"
__CV_BOLD="${__CV_CSI}1m"
__CV_HIDE="${__CV_CSI}?25l"
__CV_SHOW="${__CV_CSI}?25h"
__CV_DECSC="${__CV_ESC}7"   # save cursor (incl. attrs and scroll origin)
__CV_DECRC="${__CV_ESC}8"   # restore cursor

# ---------- palettes ----------
# Full rainbow loop in xterm-256 for the prompt and `rb`.
__CV_PALETTE=(196 202 208 214 220 226 190 154 118 82 47 49 51 45 39 33 27 21 57 93 129 165 201 199 197)

# Soviet-red shades cycled across spinner frames to fake a "pulse" / spin glow.
__CV_REDS=(124 160 196 197 198 197 196 160)

# Rows reserved at top of screen for the star.
__CV_TOP=15

# ---------- image frames ----------
# Four frames. Body changes are minimal (a center symbol toggles, sparkles drift)
# but the color shift across frames sells the spin. Each frame is exactly 14 lines
# starting from a leading blank line, so the star draws starting at row 2.
read -r -d '' __CV_FRAME_A <<'EOF' || true

⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⢀⣆⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀
⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⣼⢻⡀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀
⠀⠀⠀⠀⠀⠀⠀⠀⢤⣄⣀⣀⣀⣰⡇⠈⣧⣀⣀⣀⣀⣀⠀⠀⠀⠀⠀⠀⠀⠀
⠀⠀⠀⠀⠀⠀⠀⠀⠀⠈⠻⢦⡀⠀⠀⠀⠀⢀⣠⠾⠋⠀⠀⠀⠀⠀⠀⠀⠀⠀
⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⣹⠃⠀⡀⠀⢿⠁⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀
⠀⠀⠀⠀⠀⣠⠔⠂⠀⠀⠀⢠⣏⣴⠞⠛⢦⣜⣧⠀⠀⠀⠀⠢⣄⡀⠀⠀⠀⠀
⠀⠀⢠⣖⡿⡋⠀⠀⠀⠀⠀⠾⠋⠀⠀⠀⠀⠉⠻⡄⠀⠀⠀⠀⢝⢿⣱⣄⠀⠀
⠀⡜⣿⣨⡾⠁⠀⠀⠀⠀⠀⠀⠀⠀⠀⠉⠲⣤⡀⠀⠀⠀⠀⠀⠈⢳⣇⣿⢡⠀
⢰⣇⣟⣵⠃⠀⠀⠀⠀⠀⠀⢀⣴⣦⡤⠀⠀⠈⠻⣷⡀⠀⠀⠀⠀⠈⣯⡻⢸⡆
⡆⣿⡾⡅⠀⠀⠀⠀⠀⢀⣴⣿⣿⣏⠀⠀⠀⠀⠀⠹⣿⡆⠀⠀⠀⠀⢨⢻⣾⢱
⣷⡘⣱⠇⠀⠀⠀⠀⠀⠀⠹⠋⠈⠻⣷⣄⠀⠀⠀⠀⣿⣿⠀⠀⠀⠀⠘⣧⢋⣾
⡼⣷⡿⣀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠈⠻⣷⣄⠀⢀⣿⣿⠀⠀⠀⠀⢰⢻⣾⢇
⢳⣌⠇⣿⠀⠀⠀⠀⠀⠀⣴⢶⣤⣀⡀⠀⠈⢻⣷⣾⣿⠏⠀⠀⠀⠀⣿⠸⣡⡞
⠀⡿⢷⣿⡸⣄⠀⢀⣴⡾⠉⠀⠈⠛⠿⢿⣿⣿⡿⠿⣷⣄⠀⠀⢠⡇⣿⡾⢛⠀
⠀⠘⢦⣝⡣⢿⡦⡈⠋⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠙⠋⢀⣴⡿⣘⣭⡶⠃⠀
⠀⠀⠀⠹⣛⠿⠷⡹⣦⡀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⢀⣴⢟⠾⠟⣛⠝⠀⠀⠀
⠀⠀⠀⠀⠈⠛⡿⠿⠶⢛⣫⣤⡶⣒⡶⠶⣖⠶⣶⣍⣛⠚⠿⣟⠛⠁⠀⠀⠀⠀
⠀⠀⠀⠀⠀⠀⠈⠙⠛⠛⠋⢡⠞⠁⠀⠀⠈⠻⣮⠙⠛⠛⠋⠁⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀
 EOF

read -r -d '' __CV_FRAME_B <<'EOF' || true

⠁⠀⠈⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⢠⡄⠀⢀⣼⣿⡄⠀⠀⠀⠀
⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠈⢠⣾⣿⣿⣅⢀⠀⠀⠀⠀
⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠠⣄⣤⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⢰⣿⣿⣿⣿⣿⣿⠁⠀⠀⠀
⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⢺⣷⡄⠀⠀⠀⠀⠀⢠⣶⠾⠃⢀⠀⣠⣦⣿⣿⣿⣿⣿⣿⣿⣇⠀⠀⠀
⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⢀⣰⣤⠀⠀⠀⠀⠀⠀⢀⣤⣤⡦⠀⠀⠀⠀⠉⣻⣤⣄⠀⠀⠀⠀⠛⠛⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⡟⣿⡀⠀⠀⠀
⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⣰⣾⣿⣿⡆⠀⠀⠀⢠⡿⠛⠁⠀⡀⠀⢀⢠⣴⣾⣿⣿⣟⣄⣄⣸⣷⣀⣶⣿⣿⣿⣿⣿⣿⣿⣿⣿⡏⠁⢻⣿⣤⠀⠂
⠀⠀⠀⢤⣴⣾⣽⣶⣠⣦⣴⣿⣟⣌⣿⣥⣿⣴⣢⠉⢷⠀⢠⣼⣷⣴⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⠂⠘⣿⣿⣯⠀
⠀⠀⣠⣴⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣷⣼⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⡿⠋⠀⠀⠀⠈⠙⠻⠦
⢾⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣟⢿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣵⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⡧⠀⠀⠀⠀⠀⠀⠀⠙
⢀⣿⣿⣿⣿⣿⣿⣿⠋⣔⢾⣿⣷⠹⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⢇⢠⣼⣄⠀⠀⠀⠀⠀
⠙⠛⣿⣿⣿⣿⣿⣿⣿⣿⣦⡙⣿⢐⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣾⣾⣿⣏⠻⣆⠀⠀⠀
⠀⠐⠻⣍⣿⣿⣿⠟⣡⣶⣭⣹⣤⡛⢿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣧⠈⢷⠀⠀
⠀⠀⠀⢹⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣏⠀⠀⠙⠿⠿⣿⠋⣿⣿⠀⠀⠀⠀
⠀⠀⠀⢸⣿⣿⣿⠛⠛⡛⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⡿⠷⠀⠀⠀⠀⠀⠀⢀⣽⣿⠀⠀⠀⠀
⠀⠀⠀⢸⣿⣿⣏⠀⢸⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⠿⢿⣿⡉⠉⠛⠛⠛⠿⠋⠁⠀⠀⠀⠀⠀⠀⠀⠀⠀⠿⠁⠀⠀⠀⠀
⠀⠀⠀⠀⠉⡿⠛⢀⣞⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⡟⠉⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀
⠀⠀⠀⠀⠀⠀⠀⢘⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⠟⠧⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀
⠀⠀⠀⠀⠀⠀⠀⠈⠀⠈⢻⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⠿⠃⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀
⠄⠀⠀⡀⠀⠀⠀⠀⠀⢀⠀⡿⠿⠟⠛⠿⠿⢻⣿⣁⢉⡀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀
EOF

read -r -d '' __CV_FRAME_C <<'EOF' || true

⠃⠉⠈⠁⠉⠈⠁⠉⠈⠁⠉⠈⠁⠉⠈⠁⠉⠈⠁⠉⠈⠁⠉⠈⠁⠉⠈⠁⠉⠈⠁⠉⠈⠁⠉⠈⠁⠉⠈⠁⠉⠈⠁⠉⠈⠁⠉⠈⠁⠉⠈⠁⠉⠈⠁⠉⠈⠁⠉⠈⠁⠉⠈⠁⠩
⠃⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀           ⠀⢘
⡃⠀⠀⠀⠀⣦⣴⣶⣦⣶⣴⣦⣴⣤⣦⣶⣴⣦⣶⣴⣦⣶⣤⣦⣴⣴⣦⣶⣴⣦⣶⣴⣦⣴⣦⣴⣴⣦⣶⣴⣦⣶⣴⣦⣴⣤⣦⣴⣦⣶⣴⣦⣶⣴⣦⣴⣦⣶⣴⣴⠀⠀⠀⠀ ⢨
⡅⠀⠀⠀⠀⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⠀⠀⠀⠀ ⠰
⠆⠀⠀⠀⠀⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⡿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⠀⠀⠀⠀ ⢘
⠃⠀⠀⠀⠀⣿⣿⣿⣿⣿⡟⣿⣿⣿⢻⣿⣿⣿⣽⣿⣿⣿⢻⣿⣿⣿⡟⣿⣿⣿⣿⠛⠁⠛⢻⣿⣿⣿⢻⣿⣿⣯⣿⣿⣿⡟⣿⣿⣿⡟⣿⣯⣿⣿⣿⡟⣿⣿⣿⣿⠀⠀⠀⠀ ⢨
⡃⠀⠀⠀⠀⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣛⠃⠘⣻⣿⣿⣇⣤⡸⣿⣿⣟⠛⠈⢛⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⠀⠀⠀⠀ ⢨
⡅⠀⠀⠀⠀⣿⣿⣿⣿⣿⢿⣿⣿⣿⣿⣿⡿⣿⣿⣿⢿⣻⣿⣿⣿⣟⣴⣦⣿⣿⣿⣿⣿⣿⣿⣿⣿⣥⣦⣽⣿⣿⢿⣿⣿⣿⣿⣿⢿⣿⣿⣿⣿⣿⢿⣿⣿⣿⣿⣿⠀⠀⠀⠀ ⠰
⠆⠀⠀⠀⠀⣿⣿⣿⣿⣿⣿⣿⣿⣿⣾⣿⣿⣿⣿⣿⣿⡛⠃⠙⣻⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣟⠛⠈⢛⣿⣿⣷⣿⣿⣿⣿⣿⣽⣾⣿⣿⣿⣿⣾⣿⠀⠀⠀⠀ ⢘
⡃⠀⠀⠀⠀⣿⣿⣿⣿⣿⣿⣿⡿⣿⣿⣿⣿⣿⣿⣿⣿⣏⣴⣌⣿⣿⣿⣿⣿⣿⡿⠿⠿⣷⣌⠻⣿⣿⣿⣿⣿⣣⣦⣹⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⠀⠀⠀⠀ ⢨
⡅⠀⠀⠀⠀⣿⣿⣿⣿⣿⣾⣿⣿⣿⣿⣿⣟⣯⣷⣿⣿⢿⣿⣿⣿⣿⣿⣿⡿⠋⠀⠠⣶⣿⣿⣆⠘⣿⣿⣿⣿⣿⣿⡿⣿⣿⣿⣿⣿⣿⣽⣿⣿⣿⣿⢿⣿⣽⣿⣿⠀⠀⠀⠀ ⠰
⠆⠀⠀⠀⠀⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣯⡉⠈⣩⣿⣿⣿⣿⣿⣦⣠⣾⣦⡈⠻⣿⣿⠀⢻⣿⣿⣿⣿⣍⠁⠈⣽⣿⣿⣿⣿⣿⣿⣿⣿⣾⣿⣿⣿⣿⣿⠀⠀⠀⠀ ⢘
⡃⠀⠀⠀⠀⣿⣿⣿⣿⣿⣽⣿⣿⣯⣷⣿⣿⣿⣿⣿⣴⣶⣼⣿⣿⣿⣿⣿⣿⠿⠛⢿⣷⣦⡈⠃⢀⣿⣿⣿⣿⣿⣯⣴⣦⣿⣿⣿⣿⣿⣻⣿⣿⣿⣿⣿⣿⣿⣿⣿⠀⠀⠀⠀ ⢨
⡅⠀⠀⠀⠀⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⡟⣿⣿⣿⣿⠟⠉⣴⣷⣤⣀⣀⣠⣤⠈⠻⣿⣿⣿⣿⢻⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣽⣿⣿⣿⣻⣿⠀⠀⠀⠀ ⠰
⠆⠀⠀⠀⠀⣿⣿⣿⣿⣿⣻⣿⣿⡿⣿⣿⣿⣿⣷⣿⣿⣬⠁⠨⣽⣿⣿⣤⣾⣿⣿⣿⣿⣿⣿⣿⣷⣦⣿⣿⣧⡍⠀⢩⣿⣿⣿⣿⣿⢿⣿⣿⡿⣿⣿⣿⣿⣿⣿⣿⠀⠀⠀⠀ ⢘
⡃⠀⠀⠀⠀⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣾⣿⣿⣿⣷⣾⣷⣿⣿⡿⢿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⢻⣿⣿⣶⣿⣾⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣻⣿⣿⠀⠀⠀⠀ ⢨
⡅⠀⠀⠀⠀⣿⣿⣿⣿⣿⢿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣭⠁⠈⣽⣿⣿⣿⠛⣿⣿⣿⣯⡉⠈⣩⣿⣿⣿⣿⣿⣿⣿⣿⢿⣿⣿⣿⣿⣿⣿⢿⣿⣿⣿⣿⠀⠀⠀⠀ ⠰
⡄⠀⠀⠀⠀⣿⣿⣿⣿⣿⣿⣿⣿⣿⣼⣿⣿⣿⢿⣻⣿⣿⣿⣿⣿⣟⣼⣤⣿⣿⣧⡄⠀⢠⣼⣿⣿⣠⣧⣼⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣼⣿⣿⣿⣿⣿⣿⣿⠀⠀⠀⠀ ⠸
⠆⠀⠀⠀⠀⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣟⣿⣿⣿⣿⣿⣿⣿⣷⣾⣮⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⡿⣿⣽⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⠀⠀⠀⠀ ⢘
⡃⠀⠀⠀⠀⣿⣿⣿⣿⣿⣯⣿⣷⣿⣿⣿⣟⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⢿⣿⣿⣿⣿⣿⣿⣯⣿⣿⣿⣟⣿⣯⣿⣾⣿⠀⠀⠀⠀ ⢨
⡅⠀⠀⠀⠀⠿⠿⠿⠿⠿⠿⠿⠿⠿⠿⠿⠿⠿⠿⠿⠿⠿⠾⠿⠿⠿⠿⠿⠿⠿⠿⠿⠿⠿⠿⠿⠿⠿⠿⠿⠿⠯⠿⠿⠿⠿⠿⠿⠿⠿⠿⠿⠿⠿⠿⠿⠿⠿⠿⠿ ⠀⠀⠀ ⠰
⠆⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀          ⠀ ⠀⠀⠀⢘
⠃⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀           ⢨
EOF

read -r -d '' __CV_FRAME_D <<'EOF' || true

⣿⣟⡿⣟⣿⣻⢿⣻⣟⡿⣟⣿⣻⢿⣻⣟⡿⣟⣿⣻⢿⣻⣟⡿⣟⣿⣻⢿⣻⣟⡿⣟⣿⣻⢿⣻⣟⡿⣟⣿⣻⢿⣻⣟⡿⣟⣿⣻⢿⣻⣟⡿⣟⡿⣿
⣿⣞⡿⣯⣷⢿⣻⣽⡾⣟⣯⣷⢿⣻⣽⡾⣟⣯⣷⢿⣻⠽⣞⣻⣯⢭⣭⢩⣭⡭⣽⣟⡳⠿⣻⣽⡾⣟⣯⣷⢿⣻⣽⡾⣟⣯⣷⢿⣻⣽⡾⣟⣿⡽⣿
⣿⣞⣿⣽⢾⣟⣯⡷⣿⣻⣽⢾⣟⣯⡷⣿⣻⡽⢞⣭⣷⣿⣻⢷⣯⡿⠾⡹⠮⢿⣿⣽⣻⢿⣷⣭⡻⢿⣽⢾⣻⣯⢷⣟⡿⣽⣾⣻⢯⣷⣟⡿⣞⣿⣽
⣿⡼⣿⡼⣟⣿⡼⣿⢧⣿⣻⢿⣼⣟⡿⣧⠟⣼⣿⢿⡼⡧⣟⣻⣤⣼⣿⢻⣿⣧⣤⣟⣻⠿⠜⣿⣻⣧⠻⣿⢿⣼⣿⣻⢿⡿⣼⣻⡿⣧⣟⣿⢿⣧⢿
⣿⡽⣷⢿⣻⢷⣟⣯⣿⣳⡿⣯⣷⢛⡟⢁⣴⣯⡟⣫⣵⡿⣯⢿⠽⣯⣻⠀⣟⣿⠻⣽⡟⣦⠀⠈⢛⣵⣦⠈⢿⡺⣷⣻⣯⣟⣿⣳⡿⣽⣻⡾⣟⣾⢿
⣿⣽⣻⣯⢿⣻⣾⣻⢾⣽⣻⢷⠃⡜⠔⣫⣾⢏⣾⡽⣯⢟⣭⣾⢿⣽⠇⣶⠸⣟⣿⣳⣼⡋⢿⡀⠀⠙⢷⡝⠦⣣⠘⡷⣿⢾⣳⡿⣽⣟⡷⣿⣻⡽⣿
⣿⣞⣷⣟⡿⣽⣾⣻⢯⣿⡍⢸⠀⣠⢶⣿⢣⣿⢯⢟⣽⣞⣯⡟⣟⡭⢰⡿⡆⢹⣳⢿⣝⣽⣮⡻⣶⣄⠈⣿⡦⣀⠀⡇⢹⡿⣽⣻⣽⡾⣟⣷⢿⣽⢿
⣿⣞⡿⣞⣿⣻⢾⣽⢿⢳⡇⢸⠚⢡⣿⢧⡿⣯⣏⣾⣟⣾⠫⣞⣿⠀⣿⣟⣿⠈⠿⠥⡝⠿⣼⣧⣩⣿⢿⡹⣷⡌⠳⡇⢸⡿⣿⣽⣳⡿⣯⣟⡿⣾⣻
⣿⣞⡿⣯⣷⢿⣯⣟⣿⠈⢳⠈⡴⢹⣿⣸⣦⣄⠀⠶⣴⣦⢶⣤⣶⣼⡿⣽⡾⣷⢶⡶⣴⡶⣴⠖⠂⣠⣴⣇⣿⡏⢦⠁⡞⠀⣿⡾⣽⣻⢷⣻⣟⣷⢿
⣿⡾⣿⣹⣾⡿⣾⣹⣾⣇⠀⣾⠁⣎⣉⣉⣉⣁⢷⢆⠈⠹⣿⣹⣾⢷⣿⣏⣿⣹⣏⡿⣏⠏⠁⣰⡇⣉⣉⣉⣉⣱⠈⣷⠁⣸⣿⣹⣿⣹⢿⡿⣾⣏⣿
⣿⣽⣻⣽⣾⣻⣽⢯⣷⡟⢦⡑⣰⠉⣿⢹⣿⠋⠘⢻⣷⡆⡌⠙⣯⣿⣳⢿⣞⣯⣿⠋⠁⠐⣀⣹⣇⣿⣻⡏⣿⠉⣆⠉⡴⢻⣯⣷⢯⣟⣯⣿⣻⣞⣿
⣿⣞⣯⣷⢯⣷⣟⣯⣷⢿⡀⠱⢼⠀⡟⠚⠛⠀⠀⠈⣿⣿⡌⣸⣟⡷⣿⣯⣟⣷⣻⣆⢡⢺⣿⠿⣩⣷⢿⣱⣿⠀⣯⠞⢁⣿⢷⣯⡿⣯⣟⣾⢷⣻⣽
⣿⣞⡿⣞⣿⣳⣯⣟⣾⣟⣏⢦⣄⠄⣧⠑⡀⠀⠀⠀⠸⣻⢀⣿⢯⠟⠁⡀⠈⠻⢷⣻⡄⡊⢟⣾⢿⣽⢣⡟⢸⠠⣁⡴⣻⣟⡿⣾⣽⢷⣻⣽⣟⣯⢿
⣿⣞⣿⣻⢷⣻⢷⣯⡷⣟⡿⣆⠉⠢⢿⡀⢸⠢⢤⡀⢀⠂⠼⠉⣠⣆⠉⠀⠈⠐⢀⠉⠣⠐⢿⡋⡿⠑⡟⢀⡿⠜⠉⣰⡿⣽⣻⢷⣯⡿⣯⣷⢯⣟⣿
⣿⢾⣽⢯⡿⣯⣿⣞⣿⣻⣽⢿⣳⡤⣄⡑⠄⣧⠀⠻⡋⣠⣴⣿⣶⣾⣿⢩⣿⣤⠀⠈⠠⢀⢙⡍⠁⣼⠁⢊⣀⣤⣾⢿⣻⣽⢯⣿⢾⣽⣷⣻⣯⢿⣾
⣿⢻⣾⡟⣿⢳⡟⣾⣷⢻⣽⡟⣯⣷⣦⠈⠉⠉⠑⠀⠘⣷⣯⣼⠓⡏⣿⣼⣯⠛⢢⡄⣤⣾⠋⠀⠚⠋⠁⠉⣴⣾⣯⣿⣯⡟⣯⡟⣯⣷⣯⣷⡟⣿⣾
⣿⢯⣷⣟⣯⣿⣻⣽⡾⣟⣯⣟⡿⣽⢯⣿⣶⠶⠦⠒⠚⠊⠉⢁⣉⡭⣄⢲⣂⠍⣉⠉⠉⠓⠒⠒⠴⠴⢶⣿⣟⡷⣯⣷⣻⣽⢿⣽⢿⣽⡾⣯⣟⣷⢿
⣿⢯⣷⣻⣽⣞⣯⣷⢿⣻⣽⡾⣟⣯⣿⣳⣯⢿⣶⣶⣶⢷⣮⢉⣵⣚⣛⣘⣛⣛⣮⣉⣵⣶⣶⣶⣶⣾⢿⣳⣯⢿⣻⣾⡽⣯⣿⢾⣻⢷⣻⣽⡾⣯⣿
⣿⢯⡿⣽⡾⣯⣷⣻⣯⢿⡾⣽⡿⣽⣞⣯⣟⣯⣷⣟⡾⣿⡽⣟⣯⡿⣽⣻⢯⣟⣾⢿⣽⣳⡿⣞⣷⣯⢿⣯⣟⣿⣳⣯⢿⡷⣯⡿⣯⡿⣯⣷⣟⡿⣾
EOF

__CV_FRAMES=("$__CV_FRAME_A" "$__CV_FRAME_B" "$__CV_FRAME_C" "$__CV_FRAME_D")

# ---------- reapply scroll region ----------
# TUI apps (vim, less, htop, man, top) reset DECSTBM on exit, which would let
# subsequent output scroll into the star area. Re-establish the region after
# every prompt and on terminal resize. \e7 / \e8 preserve the user's cursor
# across the DECSTBM call (which would otherwise home the cursor to 1,1).
__cv_reapply_region() {
    local lines
    lines=$(tput lines 2>/dev/null || echo 24)
    (( lines > __CV_TOP + 3 )) || return 0
    printf '%s%s%d;%dr%s' "$__CV_DECSC" "$__CV_CSI" \
        $((__CV_TOP + 1)) "$lines" "$__CV_DECRC"
}

# ---------- spinner ----------
# Background loop. Saves the user's cursor with DECSC, jumps to the home position
# (which is row 1 col 1 — OUTSIDE the scroll region), paints a frame, restores.
__cv_spinner() {
    local frame_idx=0 color_idx=0 frame red
    # Make sure we don't leave a hidden cursor if killed mid-frame.
    trap 'printf "%s%s" "$__CV_SHOW" "$__CV_RESET"; exit 0' TERM INT
    while :; do
        frame="${__CV_FRAMES[frame_idx]}"
        red="${__CV_REDS[color_idx]}"

        printf '%s%s%s1;1H%s%s38;5;%dm%s%s%s%s' \
            "$__CV_HIDE" \
            "$__CV_DECSC" \
            "$__CV_CSI" \
            "$__CV_BOLD" \
            "$__CV_CSI" "$red" \
            "$frame" \
            "$__CV_RESET" \
            "$__CV_DECRC" \
            "$__CV_SHOW"

        frame_idx=$(( (frame_idx + 1) % ${#__CV_FRAMES[@]} ))
        color_idx=$(( (color_idx + 1) % ${#__CV_REDS[@]} ))
        sleep 0.18
    done
}

# ---------- rb: rainbow + blink any output ----------
# rb COMMAND [args...]   runs the command and pipes its output through rb
# COMMAND | rb           streams stdin one char at a time, recoloring each char
rb() {
    local IFS= ch color esc=$'\e' palette_size=${#__CV_PALETTE[@]}

    if (( $# > 0 )); then
        "$@" 2>&1 | rb
        return "${PIPESTATUS[0]}"
    fi

    # Stream chars. -N1 reads exactly 1 char, no delimiter handling.
    while IFS= read -r -N1 ch; do
        if [[ $ch == $'\n' ]]; then
            printf '%s[0m\n' "$esc"
            continue
        fi
        color="${__CV_PALETTE[RANDOM % palette_size]}"
        printf '%s[38;5;%dm%s[5m%s' "$esc" "$color" "$esc" "$ch"
    done
    printf '%s[0m' "$esc"
}

# ---------- rainbow PS1 builder ----------
__cv_build_ps1() {
    local text="${1:-COMRADE}"
    local out="" i ch color
    for (( i = 0; i < ${#text}; i++ )); do
        ch="${text:i:1}"
        color="${__CV_PALETTE[i % ${#__CV_PALETTE[@]}]}"
        # \[ ... \] are non-printing markers for readline width calculation.
        out+="\[${__CV_CSI}38;5;${color}m${__CV_BLINK}\]${ch}"
    done
    # Tail: dim white path, blinking red $/# in their own color.
    out+="\[${__CV_RESET}${__CV_CSI}38;5;245m\]@\[${__CV_CSI}38;5;220m\]\h\[${__CV_RESET}\]"
    out+=":\[${__CV_CSI}38;5;51m\]\w\[${__CV_RESET}\]"
    out+=" \[${__CV_CSI}1;31m${__CV_BLINK}\]\$\[${__CV_RESET}\] "
    printf '%s' "$out"
}

# ---------- exit command ----------
# The ONLY way to leave carnival mode (besides killing the terminal). Aliased
# under a couple of more obvious names. Triggers EXIT trap → __cv_cleanup → exit.
defect() {
    exit 0
}
quit-carnival() { exit 0; }
carnival-exit() { exit 0; }

# ---------- cleanup ----------
__cv_cleanup() {
    # Kill spinner cleanly.
    if [[ -n "${__CV_SPINNER_PID:-}" ]] && kill -0 "$__CV_SPINNER_PID" 2>/dev/null; then
        kill "$__CV_SPINNER_PID" 2>/dev/null
        wait "$__CV_SPINNER_PID" 2>/dev/null
    fi
    # Reset scroll region to full screen (DECSTBM with no params).
    printf '%sr' "$__CV_CSI"
    # Reset SGR, show cursor, clear.
    printf '%s%s' "$__CV_RESET" "$__CV_SHOW"
    clear 2>/dev/null || printf '%s2J%s1;1H' "$__CV_CSI" "$__CV_CSI"
    # Restore PS1 if we saved one.
    if [[ -n "${__CV_SAVED_PS1+x}" ]]; then
        PS1="$__CV_SAVED_PS1"
    fi
    trap - EXIT INT TSTP TTIN TTOU TERM HUP WINCH
    unset IGNOREEOF
    [[ -n "${CARNIVAL_VERBOSE:-}" ]] && echo "carnival mode terminated. terminal restored."
    unset CARNIVAL_ACTIVE
}

# ---------- init ----------
__cv_init() {
    # Save current PS1 before we trash it.
    __CV_SAVED_PS1="${PS1:-}"

    # Refuse to run on a tiny terminal.
    local lines
    lines=$(tput lines 2>/dev/null || echo 24)
    if (( lines < __CV_TOP + 5 )); then
        echo "carnival.sh: terminal too small (${lines} rows). need >= $((__CV_TOP + 5))." >&2
        return 1
    fi

    # Hard reset and clear.
    printf '%s2J%s1;1H' "$__CV_CSI" "$__CV_CSI"

    # Carve the scroll region: rows __CV_TOP+1 .. last. The star area above is
    # never scrolled into.
    printf '%s%d;%dr' "$__CV_CSI" $((__CV_TOP + 1)) "$lines"

    # Park the cursor at the top of the writable area.
    printf '%s%d;1H' "$__CV_CSI" $((__CV_TOP + 1))

    # New rainbow PS1.
    PS1="$(__cv_build_ps1 'COMRADE')"

    # Spinner in background. Redirect stderr to /dev/null so any tput noise
    # doesn't pollute the prompt area.
    __cv_spinner 2>/dev/null &
    __CV_SPINNER_PID=$!
    disown "$__CV_SPINNER_PID" 2>/dev/null || disown %% 2>/dev/null

    # Restore on shell exit OR signals. INT is intentionally NOT here — see lockdown below.
    trap __cv_cleanup EXIT TERM HUP

    # ---- accidental-exit lockdown ----
    # `trap : SIG` installs a real (no-op) handler in bash, which means bash
    # itself ignores the signal — but bash resets traps to SIG_DFL when
    # forking children, so commands you launch (sleep, curl, vim, ...) still
    # respond to Ctrl-C / Ctrl-Z normally. Only the bash prompt is hardened.
    trap ':' INT             # Ctrl-C at prompt: line cleared by readline, no exit
    trap ':' TSTP TTIN TTOU  # Ctrl-Z at prompt: ignored
    IGNOREEOF=999            # Ctrl-D at empty prompt: requires 1000 presses

    # Re-establish the scroll region after every command (TUI apps reset it)
    # and on terminal resize. Prepended so user's existing PROMPT_COMMAND still runs.
    PROMPT_COMMAND="__cv_reapply_region${PROMPT_COMMAND:+; $PROMPT_COMMAND}"
    trap '__cv_reapply_region' WINCH

    # Welcome banner.
    printf '%s%s ☭ welcome, comrade %s\n' \
        "${__CV_CSI}1;33m" "${__CV_BLINK}" "${__CV_RESET}"
    printf '%scommands:%s  %srb <cmd>%s = rainbow output    %sdefect%s = leave (Ctrl-C / Ctrl-Z / Ctrl-D disabled)\n' \
        "${__CV_CSI}38;5;245m" "${__CV_RESET}" \
        "${__CV_CSI}1;36m" "${__CV_RESET}" \
        "${__CV_CSI}1;31m${__CV_BLINK}" "${__CV_RESET}"
    printf '%stry:%s  %srb ls -la%s    %srb dmesg | head%s    %srb cat /etc/os-release%s\n\n' \
        "${__CV_CSI}38;5;245m" "${__CV_RESET}" \
        "${__CV_CSI}1;32m" "${__CV_RESET}" \
        "${__CV_CSI}1;32m" "${__CV_RESET}" \
        "${__CV_CSI}1;32m" "${__CV_RESET}"
}

__cv_init
