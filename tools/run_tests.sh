#!/usr/bin/env bash
# Импорт + юнит-тесты GUT без окна. Код выхода != 0, если есть упавшие тесты.
source "$(dirname "$0")/common.sh"
cd "${ROOT_DIR}"
"$(dirname "$0")/import.sh" > /dev/null
"${GODOT}" --headless --path . -s res://addons/gut/gut_cmdln.gd -gconfig=res://.gutconfig.json "$@"
