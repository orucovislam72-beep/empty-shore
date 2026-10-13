#!/usr/bin/env bash
# Общие переменные для скриптов tools/. Подключается через `source`.
set -euo pipefail

GODOT_VERSION="4.7.2"
GODOT_TAG="${GODOT_VERSION}-stable"
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

# Путь к редактору Godot: переменная GODOT или `godot` в PATH.
GODOT="${GODOT:-$(command -v godot || true)}"
if [[ -z "${GODOT}" || ! -x "${GODOT}" ]]; then
	echo "Не найден Godot ${GODOT_VERSION}. Укажите путь: GODOT=/path/to/Godot_v${GODOT_TAG}_linux.x86_64" >&2
	exit 2
fi

ver="$("${GODOT}" --version | head -n1)"
if [[ "${ver}" != ${GODOT_VERSION}.stable* ]]; then
	echo "Внимание: ожидался Godot ${GODOT_VERSION}, найден ${ver}" >&2
fi
