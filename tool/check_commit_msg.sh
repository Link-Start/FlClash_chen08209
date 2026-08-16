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

# Changelog trailers. `tool/changelog.dart` reads these to build the user facing
# changelog; the subject is only a fallback.
body="$(grep -v '^#' "$message_file" | tail -n +2 || true)"
locales='zh-CN|ja|ru'
groups='breaking|feat|fix|perf|revert'

while IFS= read -r line; do
  if [[ "$line" =~ ^Changelog-([A-Za-z0-9-]+): ]]; then
    key="${BASH_REMATCH[1]}"
    if [[ "$key" != 'Type' && ! "$key" =~ ^($locales)$ ]]; then
      echo "Unknown changelog trailer: Changelog-$key" >&2
      echo "Expected Changelog-Type or one of: ${locales//|/, }" >&2
      exit 1
    fi
    if [[ "$key" == 'Type' ]]; then
      value="${line#*: }"
      if [[ ! "$value" =~ ^($groups)$ ]]; then
        echo "Unknown Changelog-Type: $value" >&2
        echo "Expected one of: ${groups//|/, }" >&2
        exit 1
      fi
    fi
  fi
  if [[ "$line" =~ ^Breaking-([A-Za-z0-9-]+): ]]; then
    key="${BASH_REMATCH[1]}"
    if [[ ! "$key" =~ ^($locales)$ ]]; then
      echo "Unknown breaking trailer: Breaking-$key" >&2
      echo "Expected one of: ${locales//|/, }" >&2
      exit 1
    fi
  fi
done <<<"$body"

if [[ "$subject" =~ ^($types)(\([a-z0-9,./_-]+\))?!: ]] &&
  ! grep -qE '^BREAKING[ -]CHANGE:' <<<"$body"; then
  cat >&2 <<'EOF'
A breaking commit needs a BREAKING CHANGE footer describing what breaks:

  feat(backup)!: new archive layout

  BREAKING CHANGE: Archives from 0.8.95 and earlier need re-import
EOF
  exit 1
fi

type="${subject%%[(:!]*}"

if [[ "$type" =~ ^(feat|fix|perf)$ ]] && ! grep -qE '^Changelog:' <<<"$body"; then
  cat >&2 <<EOF
Note: no "Changelog:" trailer, so the changelog will reuse this subject.

  Changelog: $description
  Changelog-zh-CN: ...
EOF
fi
