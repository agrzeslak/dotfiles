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
BLUE='\033[0;94m'
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
# Format a rate-limit field as "<prefix> <pct>% (<time remaining>)".
# Only the "<prefix> <pct>%" head is colour-graded; the parenthesised
# remainder is italicised but deliberately left uncoloured so the
# percentage's severity stays the dominant visual signal.
limit_label() {
  local prefix="$1"
  local pct="$2"
  local reset="$3"
  local window_secs="$4"
  local head
  head=$(colorize "$prefix $(printf '%.0f' "$pct")%" "$pct")
  local suffix=""
  # `resets_at` arrives as a Unix epoch integer, so we can use it directly.
  # Guard with a numeric regex so a malformed value just hides the suffix
  # rather than blowing up the arithmetic below.
  if [[ "$reset" =~ ^[0-9]+$ ]]; then
    local now_epoch remaining
    now_epoch=$(date +%s)
    remaining=$((reset - now_epoch))
    if [ "$remaining" -gt 0 ]; then
      local formatted
      formatted=$(format_remaining "$remaining")
      # Color the time-remaining label by pace: the ratio of usage consumed
      # to time elapsed within the window.  A pace of 1.0 means on-track;
      # higher means burning faster than the window can sustain.
      local pace_col
      pace_col=$(awk -v pct="$pct" -v rem="$remaining" -v win="$window_secs" 'BEGIN {
        elapsed = win - rem
        if (elapsed <= 0 || win <= 0) { print "none"; exit }
        pace = (pct / 100) / (elapsed / win)
        if (pace >= 2.0) print "red"
        else if (pace >= 1.5) print "orange"
        else if (pace >= 1.2) print "yellow"
        else if (pace >= 0.8) print "green"
        else print "blue"
      }')
      case "$pace_col" in
        red)    suffix=" ${RED}${ITALIC}(${formatted})${RESET}" ;;
        orange) suffix=" ${ORANGE}${ITALIC}(${formatted})${RESET}" ;;
        yellow) suffix=" ${YELLOW}${ITALIC}(${formatted})${RESET}" ;;
        green)  suffix=" ${GREEN}${ITALIC}(${formatted})${RESET}" ;;
        blue)   suffix=" ${BLUE}${ITALIC}(${formatted})${RESET}" ;;
        *)      suffix=" ${ITALIC}(${formatted})${NOITALIC}" ;;
      esac
    fi
  fi
  printf '%s%s' "$head" "$suffix"
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

