#!/usr/bin/env bash
# Claude Code status line: model | context used | subscription limits left.
# Claude Code pipes session JSON to stdin (https://code.claude.com/docs/ru/statusline).
# No jq on this machine, so the JSON is parsed by Python; without Python only the model is shown.
input=$(cat)

PY=$(command -v python3 || command -v python || command -v py)
if [ -z "$PY" ]; then
  model=$(printf '%s' "$input" | grep -o '"display_name"[[:space:]]*:[[:space:]]*"[^"]*"' | head -1 | sed 's/.*"\([^"]*\)"$/\1/')
  echo "[${model:-?}]"
  exit 0
fi

printf '%s' "$input" | PYTHONIOENCODING=utf-8 "$PY" -X utf8 -c '
import json, sys, time
sys.stdout.reconfigure(newline=chr(10))  # no CRLF from Windows text mode

try:
    d = json.load(sys.stdin)
except Exception:
    print("[statusline: bad JSON]")
    sys.exit(0)

def get(*path, default=None):
    cur = d
    for key in path:
        if not isinstance(cur, dict) or cur.get(key) is None:
            return default
        cur = cur[key]
    return cur

GREEN, YELLOW, RED, CYAN, DIM, RESET = "\033[32m", "\033[33m", "\033[31m", "\033[36m", "\033[2m", "\033[0m"

def color_used(pct):
    return RED if pct >= 90 else YELLOW if pct >= 70 else GREEN

def tokens(n):
    return f"{n / 1_000_000:.1f}M" if n >= 1_000_000 else f"{round(n / 1000)}k"

parts = []

# Model (+ effort level when the model supports it)
model = get("model", "display_name", default="?")
effort = get("effort", "level")
parts.append(f"{CYAN}{model}{RESET}" + (f" {DIM}{effort}{RESET}" if effort else ""))

# Context window: bar + percent + used/size tokens
used = get("context_window", "used_percentage")
if used is not None:
    used = float(used)
    size = get("context_window", "context_window_size", default=0)
    filled = min(10, int(used // 10))
    bar = "█" * filled + "░" * (10 - filled)
    detail = f" {tokens(size * used / 100)}/{tokens(size)}" if size else ""
    parts.append(f"ctx {color_used(used)}{bar} {used:.0f}%{RESET}{DIM}{detail}{RESET}")
else:
    parts.append(f"ctx {DIM}—{RESET}")

# Subscription limits: how much is LEFT in the 5h and 7d windows, and when they reset
def window(label, key, fmt):
    pct = get("rate_limits", key, "used_percentage")
    if pct is None:
        return None
    pct = float(pct)
    left = max(0.0, 100.0 - pct)
    resets = get("rate_limits", key, "resets_at")
    when = f" {DIM}↻{time.strftime(fmt, time.localtime(resets))}{RESET}" if resets else ""
    return f"{label} {color_used(pct)}{left:.0f}% left{RESET}{when}"

limits = [w for w in (window("5h", "five_hour", "%H:%M"), window("7d", "seven_day", "%a %H:%M")) if w]
spend = get("rate_limits", "spend_limit", "used_percentage")
if spend is not None:
    limits.append(f"spend {color_used(float(spend))}{max(0.0, 100 - float(spend)):.0f}% left{RESET}")
parts.append(" ".join(limits) if limits else f"limits {DIM}—{RESET}")

print(" | ".join(parts))
'
exit 0
