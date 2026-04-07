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
# Format a rate-limit field as "<prefix> <pct>% (<time remaining>)".
# Only the "<prefix> <pct>%" head is colour-graded; the parenthesised
# remainder is italicised but deliberately left uncoloured so the
# percentage's severity stays the dominant visual signal.
limit_label() {
  local prefix="$1"
  local pct="$2"
  local reset="$3"
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
      # Pick the two coarsest non-zero units so the label stays compact:
      # weekly windows show "Xd Yh", multi-hour windows show "Xh Ym",
      # and anything under an hour collapses to just "Ym".
      local days hours mins remaining_str
      days=$((remaining / 86400))
      hours=$(((remaining % 86400) / 3600))
      mins=$(((remaining % 3600) / 60))
      if [ "$days" -gt 0 ]; then
        remaining_str="${days}d ${hours}h"
      elif [ "$hours" -gt 0 ]; then
        remaining_str="${hours}h ${mins}m"
      else
        remaining_str="${mins}m"
      fi
      suffix=" ${ITALIC}(${remaining_str})${NOITALIC}"
    fi
  fi
  printf '%s%s' "$head" "$suffix"
}
# Peak hours: 8 AM–2 PM ET (13:00–19:00 UTC), weekdays only
HOUR_UTC=$(date -u +%H)
DOW=$(date -u +%u)  # 1=Mon … 7=Sun
if [ "$DOW" -le 5 ] && [ "$HOUR_UTC" -ge 13 ] && [ "$HOUR_UTC" -lt 19 ]; then
  END_TIME=$(date -d '19:00 UTC' +%H:%M 2>/dev/null || date -jf "%H:%M %Z" "19:00 UTC" +%H:%M 2>/dev/null)
  PEAK_INDICATOR=" · ${RED}peak${RESET} ${ITALIC}(until ${END_TIME})${NOITALIC}"
else
  if [ "$DOW" -le 5 ] && [ "$HOUR_UTC" -lt 13 ]; then
    END_TIME=$(date -d '13:00 UTC' +%H:%M 2>/dev/null || date -jf "%H:%M %Z" "13:00 UTC" +%H:%M 2>/dev/null)
  elif [ "$DOW" -le 4 ]; then
    END_TIME=$(date -d 'tomorrow 13:00 UTC' +"%a %H:%M" 2>/dev/null \
            || date -v+1d -jf "%H:%M %Z" "13:00 UTC" +"%a %H:%M" 2>/dev/null)
  else
    DAYS_UNTIL_MON=$(( (8 - DOW) % 7 ))
    [ "$DAYS_UNTIL_MON" -eq 0 ] && DAYS_UNTIL_MON=7
    END_TIME=$(date -d "+${DAYS_UNTIL_MON} days 13:00 UTC" +"%a %H:%M" 2>/dev/null \
            || date -v+${DAYS_UNTIL_MON}d -jf "%H:%M %Z" "13:00 UTC" +"%a %H:%M" 2>/dev/null)
  fi
  PEAK_INDICATOR=" · ${GREEN}off peak${RESET} ${ITALIC}(until ${END_TIME})${NOITALIC}"
fi
# Format each field
OUT="$MODEL"
[ -n "$BRANCH"     ] && OUT="$OUT · $BRANCH"
[ -n "$GIT_STATUS" ] && OUT="$OUT · $GIT_STATUS"
[ -n "$FIVE_H"     ] && OUT="$OUT · $(limit_label "5h" "$FIVE_H" "$FIVE_H_RESET")"
[ -n "$WEEK"       ] && OUT="$OUT · $(limit_label "7d" "$WEEK"  "$WEEK_RESET")"
[ -n "$CTX"        ] && OUT="$OUT · $(colorize "ctx $(printf '%.0f' "$CTX")%" "$CTX")"
OUT="$OUT$PEAK_INDICATOR"
echo -e "$OUT"

