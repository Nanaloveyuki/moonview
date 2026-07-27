#!/usr/bin/env sh
set -eu

cd "$(dirname "$0")/.."

if command -v moon >/dev/null 2>&1; then
  moon_command=moon
elif [ -x "$HOME/.moon/bin/moon" ]; then
  moon_command="$HOME/.moon/bin/moon"
else
  echo "moonview: MoonBit CLI not found in PATH or ~/.moon/bin" >&2
  exit 127
fi

"$moon_command" test --target native --frozen
"$moon_command" run src/examples/linux_smoke --target native --frozen
