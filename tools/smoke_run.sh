#!/usr/bin/env bash
# Дымовой запуск: главное меню и игровая сцена по нескольку сотен кадров без окна.
# Падает, если в логе есть ошибки скриптов.
source "$(dirname "$0")/common.sh"
cd "${ROOT_DIR}"
fail=0
for scene in "" "res://scenes/main/game.tscn"; do
	log="$(mktemp)"
	# shellcheck disable=SC2086
	"${GODOT}" --headless --path . ${scene} --quit-after 300 2>&1 | tee "${log}"
	if grep -qE "SCRIPT ERROR|ERROR:" "${log}"; then
		echo "Ошибки при запуске ${scene:-главного меню}" >&2
		fail=1
	fi
done
exit "${fail}"
