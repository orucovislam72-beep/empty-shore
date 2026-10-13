#!/usr/bin/env bash
# Импорт ресурсов без окна (нужен перед тестами и экспортом на чистой копии репозитория).
source "$(dirname "$0")/common.sh"
cd "${ROOT_DIR}"
log="$(mktemp)"
"${GODOT}" --headless --path . --import 2>&1 | tee "${log}"
if grep -qE "SCRIPT ERROR|Parse Error|Failed to load script" "${log}"; then
	echo "Импорт: найдены ошибки скриптов" >&2
	exit 1
fi
echo "Импорт завершён без ошибок скриптов."
