#!/bin/bash
input=$(cat)

MODEL=$(echo "$input" | jq -r '.model.display_name // "?"')
CTX=$(echo "$input" | jq -r '.context_window.used_percentage // empty')
FIVE_H=$(echo "$input" | jq -r '.rate_limits.five_hour.used_percentage // empty')
FIVE_H_RESET=$(echo "$input" | jq -r '.rate_limits.five_hour.resets_at // empty')
WEEK=$(echo "$input" | jq -r '.rate_limits.seven_day.used_percentage // empty')
WEEK_RESET=$(echo "$input" | jq -r '.rate_limits.seven_day.resets_at // empty')

GREEN='\033[0;32m'
YELLOW='\033[0;33m'
ORANGE='\033[0;38;5;208m'
RED='\033[0;31m'
RESET='\033[0m'
ITALIC='\033[3m'
NOITALIC='\033[23m'

# Git branch and summary from workspace dir
DIR=$(echo "$input" | jq -r '.workspace.current_dir // empty')
BRANCH=""
GIT_STATUS=""
if [ -n "$DIR" ] && git -C "$DIR" rev-parse --git-dir >/dev/null 2>&1; then
  BRANCH=$(git -C "$DIR" branch --show-current 2>/dev/null)

  ADDED=0
  REMOVED=0

  # Sum added/removed lines across staged + unstaged tracked changes.
  while IFS=$'\t' read -r a d _; do
    # Binary files show "-" instead of numeric counts.
    [ "$a" = "-" ] && continue
    [ "$d" = "-" ] && continue
    ADDED=$((ADDED + a))
    REMOVED=$((REMOVED + d))
  done < <(git -C "$DIR" diff --numstat HEAD 2>/dev/null)

  # Count changed files for a compact breadth indicator.
  FILES=$(git -C "$DIR" diff --name-only HEAD 2>/dev/null | wc -l | tr -d ' ')

  TOTAL=$((ADDED + REMOVED))
  WARN=""

  # Add a warning marker when churn gets large.
  if [ "$TOTAL" -gt 400 ]; then
    WARN="${RED}⛔${RESET} "
  elif [ "$TOTAL" -ge 200 ]; then
    WARN="${YELLOW}⚠${RESET} "
  fi

  if [ "$ADDED" -gt 0 ] || [ "$REMOVED" -gt 0 ] || [ "$FILES" -gt 0 ]; then
    GIT_STATUS="${WARN}${GREEN}+${ADDED}${RESET}${RED} -${REMOVED}${RESET}${YELLOW} ~${FILES}${RESET}"
  fi
fi

# Wrap a value in colour based on percentage thresholds
colorize() {
  local val="$1"
  local pct="$2"
  if [ "$(printf '%.0f' "$pct")" -ge 90 ] 2>/dev/null; then
    printf "${RED}%s${RESET}" "$val"
  elif [ "$(printf '%.0f' "$pct")" -ge 80 ] 2>/dev/null; then
    printf "${ORANGE}%s${RESET}" "$val"
  elif [ "$(printf '%.0f' "$pct")" -ge 70 ] 2>/dev/null; then
    printf "${YELLOW}%s${RESET}" "$val"
  else
    printf "%s" "$val"
  fi
}
# Format a non-negative duration in seconds as the two coarsest non-zero units:
# weekly windows show "Xd Yh", multi-hour windows show "Xh Ym", and anything
# under an hour collapses to just "Ym". Shared by the rate-limit reset labels
# and the peak/off-peak indicator so both read consistently.
format_remaining() {
  local remaining="$1"
  local days hours mins
  days=$((remaining / 86400))
  hours=$(((remaining % 86400) / 3600))
  mins=$(((remaining % 3600) / 60))
  if [ "$days" -gt 0 ]; then
    printf '%dd %dh' "$days" "$hours"
  elif [ "$hours" -gt 0 ]; then
    printf '%dh %dm' "$hours" "$mins"
  else
    printf '%dm' "$mins"
  fi
}
# Format a rate-limit field as "<prefix> <pct>% <bar>".
#
# The 10-cell bar visualises usage relative to time elapsed within the window.
# Three shading levels create a visual hierarchy from background to foreground:
#
#   - Empty cells render as "░" (light shade) in the default colour, forming
#     a continuous neutral rail so the bar always reads as 10 cells wide.
#   - The *gap* between the usage cell and the elapsed-time cell — inclusive
#     of the elapsed-time end, exclusive of the marker — renders as "▒"
#     (medium shade) in a single colour determined by direction and magnitude:
#       * Under pace (usage% < elapsed%): green; the gap sits to the *right*
#         of the marker, extending toward the further-along time position.
#       * Over pace (usage% > elapsed%): yellow (1 cell over), orange (2),
#         red (3 or more) — uniform across the whole gap.  The gap sits to
#         the *left* of the marker, extending back toward where time actually
#         is.  Direction-of-gap is encoded by colour, not position.
#       * On pace (same cell): no gap renders.
#   - The marker cell — the *usage* fraction — renders as "█" (full block) in
#     the default colour.  It aligns with the "<pct>%" readout to the left of
#     the bar and serves as the glanceable "how much have I used" indicator.
#
# Cell N covers the range [N*10%, (N+1)*10), so 50% lands at cell 5 and 100%
# clamps to cell 9.  The "<prefix> <pct>%" head retains its existing pct-
# threshold colour.
limit_label() {
  local prefix="$1"
  local pct="$2"
  local reset="$3"
  local window_secs="$4"
  local head
  head=$(colorize "$prefix $(printf '%.0f' "$pct")%" "$pct")
  local bar=""
  # `resets_at` arrives as a Unix epoch integer.  Guard with a numeric regex
  # (and a positive-window check) so a malformed value just hides the bar
  # rather than blowing up the arithmetic below.
  if [[ "$reset" =~ ^[0-9]+$ ]] && [ "$window_secs" -gt 0 ]; then
    local now_epoch remaining
    now_epoch=$(date +%s)
    remaining=$((reset - now_epoch))
    # Clamp elapsed into [0, window_secs].  `remaining > window_secs` would
    # mean clock skew or a bogus reset epoch; `remaining < 0` would mean the
    # window is already past its reset.  Either way we keep the bar in range.
    local elapsed=$((window_secs - remaining))
    if [ "$elapsed" -lt 0 ]; then elapsed=0; fi
    if [ "$elapsed" -gt "$window_secs" ]; then elapsed="$window_secs"; fi
    local elapsed_pct usage_cell elapsed_cell
    elapsed_pct=$(awk -v e="$elapsed" -v w="$window_secs" 'BEGIN { print (e/w)*100 }')
    usage_cell=$(awk -v p="$pct"         'BEGIN { c=int(p/10); if (c>9) c=9; if (c<0) c=0; print c }')
    elapsed_cell=$(awk -v p="$elapsed_pct" 'BEGIN { c=int(p/10); if (c>9) c=9; if (c<0) c=0; print c }')
    # Pick a single colour for the over-pace gap based on its width, so all
    # over-pace cells share one colour rather than fading per-cell.  Under-pace
    # gaps are always green; on-pace shows no gap at all.
    local gap_color=""
    if [ "$usage_cell" -gt "$elapsed_cell" ]; then
      local over_dist=$((usage_cell - elapsed_cell))
      case "$over_dist" in
        1) gap_color="$YELLOW" ;;
        2) gap_color="$ORANGE" ;;
        *) gap_color="$RED" ;;
      esac
    elif [ "$usage_cell" -lt "$elapsed_cell" ]; then
      gap_color="$GREEN"
    fi
    local cells="" i
    for i in 0 1 2 3 4 5 6 7 8 9; do
      if [ "$i" -eq "$usage_cell" ]; then
        # Marker: full block, no colour, anchors the bar at current usage so
        # its position lines up with the "<pct>%" readout.
        cells+="█"
      elif [ "$usage_cell" -gt "$elapsed_cell" ] && [ "$i" -ge "$elapsed_cell" ] && [ "$i" -lt "$usage_cell" ]; then
        # Over-pace gap, sitting to the left of the marker.
        cells+="${gap_color}▒${RESET}"
      elif [ "$usage_cell" -lt "$elapsed_cell" ] && [ "$i" -gt "$usage_cell" ] && [ "$i" -le "$elapsed_cell" ]; then
        # Under-pace gap, sitting to the right of the marker.
        cells+="${gap_color}▒${RESET}"
      else
        # Empty cells use the lightest shade in the default colour so the bar
        # has a continuous visual rail; the marker and gap blocks rise out of it.
        cells+="░"
      fi
    done
    bar=" ${cells}"
  fi
  printf '%s%s' "$head" "$bar"
}
# Peak hours: 8 AM–2 PM ET (13:00–19:00 UTC), weekdays only.
# Resolve the next peak boundary as an epoch so the remaining time can be
# rendered through the same format_remaining helper the reset labels use.
HOUR_UTC=$(date -u +%H)
DOW=$(date -u +%u)  # 1=Mon … 7=Sun
NOW_EPOCH=$(date +%s)
if [ "$DOW" -le 5 ] && [ "$HOUR_UTC" -ge 13 ] && [ "$HOUR_UTC" -lt 19 ]; then
  # Currently in peak — the next boundary is today's 19:00 UTC end.
  TARGET_EPOCH=$(date -d '19:00 UTC' +%s 2>/dev/null \
              || date -jf "%H:%M %Z" "19:00 UTC" +%s 2>/dev/null)
  PEAK_LABEL="${RED}peak${RESET}"
else
  if [ "$DOW" -le 5 ] && [ "$HOUR_UTC" -lt 13 ]; then
    # Weekday before peak — next boundary is today's 13:00 UTC start.
    TARGET_EPOCH=$(date -d '13:00 UTC' +%s 2>/dev/null \
                || date -jf "%H:%M %Z" "13:00 UTC" +%s 2>/dev/null)
  elif [ "$DOW" -le 4 ]; then
    # Mon–Thu after peak — next boundary is tomorrow's 13:00 UTC start.
    TARGET_EPOCH=$(date -d 'tomorrow 13:00 UTC' +%s 2>/dev/null \
                || date -v+1d -jf "%H:%M %Z" "13:00 UTC" +%s 2>/dev/null)
  else
    # Fri (post-peak), Sat, or Sun — skip ahead to Monday's 13:00 UTC start.
    DAYS_UNTIL_MON=$(( (8 - DOW) % 7 ))
    [ "$DAYS_UNTIL_MON" -eq 0 ] && DAYS_UNTIL_MON=7
    TARGET_EPOCH=$(date -d "+${DAYS_UNTIL_MON} days 13:00 UTC" +%s 2>/dev/null \
                || date -v+${DAYS_UNTIL_MON}d -jf "%H:%M %Z" "13:00 UTC" +%s 2>/dev/null)
  fi
  PEAK_LABEL="${GREEN}off peak${RESET}"
fi
# If both date invocations failed we drop the parenthesised remainder rather
# than emitting a broken "()" so the label still renders cleanly.
PEAK_INDICATOR=" · ${PEAK_LABEL}"
if [[ "$TARGET_EPOCH" =~ ^[0-9]+$ ]]; then
  REMAINING=$((TARGET_EPOCH - NOW_EPOCH))
  if [ "$REMAINING" -gt 0 ]; then
    PEAK_INDICATOR="${PEAK_INDICATOR} ${ITALIC}($(format_remaining "$REMAINING"))${NOITALIC}"
  fi
fi
# Format each field
OUT="$MODEL"
[ -n "$BRANCH"     ] && OUT="$OUT · $BRANCH"
[ -n "$GIT_STATUS" ] && OUT="$OUT · $GIT_STATUS"
[ -n "$FIVE_H"     ] && OUT="$OUT · $(limit_label "5h" "$FIVE_H" "$FIVE_H_RESET" 18000)"
[ -n "$WEEK"       ] && OUT="$OUT · $(limit_label "7d" "$WEEK"  "$WEEK_RESET" 604800)"
[ -n "$CTX"        ] && OUT="$OUT · $(colorize "ctx $(printf '%.0f' "$CTX")%" "$CTX")"
OUT="$OUT$PEAK_INDICATOR"
echo -e "$OUT"

