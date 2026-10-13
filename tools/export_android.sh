#!/usr/bin/env bash
# Экспорт Android из командной строки.
#   tools/export_android.sh apk debug     -> build/android/empty-shore-debug.apk
#   tools/export_android.sh apk release   -> build/android/empty-shore-release.apk
#   tools/export_android.sh aab release   -> build/android/empty-shore-release.aab (Gradle-сборка)
#
# Требуется: шаблоны экспорта Godot ${GODOT_VERSION}, JDK 17 (JAVA_HOME), Android SDK (ANDROID_HOME).
# Подпись: ключи берутся только из переменных окружения (в CI — из секретов):
#   GODOT_ANDROID_KEYSTORE_DEBUG_PATH / _USER / _PASSWORD    — для debug
#   GODOT_ANDROID_KEYSTORE_RELEASE_PATH / _USER / _PASSWORD  — для release
source "$(dirname "$0")/common.sh"
cd "${ROOT_DIR}"

format="${1:-apk}"
mode="${2:-debug}"
case "${format}" in
	apk) preset="Android APK" ;;
	aab) preset="Android AAB" ;;
	*) echo "Формат: apk или aab" >&2; exit 2 ;;
esac
case "${mode}" in
	debug|release) ;;
	*) echo "Режим: debug или release" >&2; exit 2 ;;
esac

templates="${HOME}/.local/share/godot/export_templates/${GODOT_VERSION}.stable"
if [[ ! -f "${templates}/android_release.apk" ]]; then
	echo "Нет шаблонов экспорта в ${templates}. Скачайте Godot_v${GODOT_TAG}_export_templates.tpz и распакуйте templates/ туда." >&2
	exit 2
fi
: "${JAVA_HOME:?Укажите JAVA_HOME (JDK 17)}"
: "${ANDROID_HOME:?Укажите ANDROID_HOME (Android SDK)}"
if [[ "${mode}" == "release" ]]; then
	: "${GODOT_ANDROID_KEYSTORE_RELEASE_PATH:?Нет GODOT_ANDROID_KEYSTORE_RELEASE_PATH}"
	: "${GODOT_ANDROID_KEYSTORE_RELEASE_USER:?Нет GODOT_ANDROID_KEYSTORE_RELEASE_USER}"
	: "${GODOT_ANDROID_KEYSTORE_RELEASE_PASSWORD:?Нет GODOT_ANDROID_KEYSTORE_RELEASE_PASSWORD}"
fi

mkdir -p build/android
out="build/android/empty-shore-${mode}.${format}"
"$(dirname "$0")/import.sh" > /dev/null

extra=()
if [[ "${format}" == "aab" && ! -d android/build ]]; then
	# Gradle-шаблон ставится в android/ (в .gitignore).
	extra+=(--install-android-build-template)
fi
"${GODOT}" --headless --path . "${extra[@]}" "--export-${mode}" "${preset}" "${out}"
ls -lh "${out}"
