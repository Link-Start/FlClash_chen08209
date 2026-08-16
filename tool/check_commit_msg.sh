#!/usr/bin/env bash

set -euo pipefail

message_file="${1:?commit message file is required}"

subject="$(grep -v '^#' "$message_file" | sed '/^[[:space:]]*$/d' | head -n 1 || true)"

if [[ -z "$subject" ]]; then
  echo 'Commit message is empty.' >&2
  exit 1
fi

if [[ "$subject" =~ ^(Merge|Revert)[[:space:]] ]]; then
  exit 0
fi

if [[ "$subject" =~ ^(fixup|squash)! ]]; then
  exit 0
fi

types='feat|fix|docs|style|refactor|perf|test|build|ci|chore|revert'

if [[ ! "$subject" =~ ^($types)(\([a-z0-9,./_-]+\))?!?:[[:space:]].+ ]]; then
  cat >&2 <<EOF
Commit subject does not follow Conventional Commits:

  $subject

Expected: <type>[(scope)][!]: <description>
Types:    ${types//|/, }
Examples:
  perf(views): stop redoing per-frame work in build
  refactor(tray): replace the tray_manager fork with a first-party plugin
  fix(core,android)!: keep failures visible and lifecycle results honest
EOF
  exit 1
fi

if [[ ${#subject} -gt 100 ]]; then
  echo "Commit subject is ${#subject} characters; keep it within 100." >&2
  exit 1
fi

description="${subject#*: }"

if [[ "$description" =~ ^[A-Z][a-z] ]]; then
  echo "Commit description should start in lower case: $description" >&2
  exit 1
fi

if [[ "$description" =~ \.$ ]]; then
  echo "Commit description should not end with a period: $description" >&2
  exit 1
fi
