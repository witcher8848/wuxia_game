#!/usr/bin/env bash
set -euo pipefail
task_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
task_version="$(tr -d '\r\n' < "$task_root/.godot-version")"
case "$(uname -s)" in
  Darwin) task_slug="macos.universal.zip"; task_templates="$HOME/Library/Application Support/Godot/export_templates/$task_version.stable" ;;
  Linux) task_slug="linux.x86_64.zip"; task_templates="${XDG_DATA_HOME:-$HOME/.local/share}/godot/export_templates/$task_version.stable" ;;
  MINGW*|MSYS*|CYGWIN*) task_slug="win64.exe.zip"; task_templates="${APPDATA:?APPDATA required}/Godot/export_templates/$task_version.stable" ;;
  *) echo "Unsupported host; install official Standard build and set GODOT_BIN." >&2; exit 1 ;;
esac
task_cache="$task_root/.tools/downloads"
task_base="https://github.com/godotengine/godot-builds/releases/download/$task_version-stable"
mkdir -p "$task_cache" "$task_root/.tools/godot" "$task_templates"
fetch() {
  local name="$1"
  if [[ ! -s "$task_cache/$name" ]]; then
    curl --http1.1 -fLsS --retry 2 --connect-timeout 20 --max-time 1200 "$task_base/$name" -o "$task_cache/$name.part"
    mv "$task_cache/$name.part" "$task_cache/$name"
  fi
}
fetch SHA512-SUMS.txt
task_editor="Godot_v$task_version-stable_$task_slug"
task_tpz="Godot_v$task_version-stable_export_templates.tpz"
fetch "$task_editor"
fetch "$task_tpz"
python3 "$task_root/tools/verify_downloads.py" "$task_cache" "$task_editor" "$task_tpz"
unzip -oq "$task_cache/$task_editor" -d "$task_root/.tools/godot"
case "$(uname -s)" in
  Linux) mv "$task_root/.tools/godot/Godot_v$task_version-stable_linux.x86_64" "$task_root/.tools/godot/godot"; chmod +x "$task_root/.tools/godot/godot" ;;
  MINGW*|MSYS*|CYGWIN*) mv "$task_root/.tools/godot/Godot_v$task_version-stable_win64.exe" "$task_root/.tools/godot/godot.exe" ;;
esac
# Only required Windows templates are installed; the downloaded archive remains intact.
unzip -oj "$task_cache/$task_tpz" 'templates/windows_debug_x86_64.exe' 'templates/windows_release_x86_64.exe' 'templates/version.txt' -d "$task_templates"
"$task_root/tools/godot.sh" --version
