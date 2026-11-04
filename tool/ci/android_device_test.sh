#!/usr/bin/env bash
# Teste no emulador Android (CI): instala o APK de release, abre, confere que
# nao fechou, reabre (persistencia) e roda o teste de integracao no aparelho.
set -euo pipefail
PKG=br.com.gmnbook.gmn_book
APK=$(ls releases/android/*.apk | head -1)

echo "=== Instalando $APK ==="
adb install -r "$APK"
adb logcat -c

echo "=== Abrindo o aplicativo ==="
adb shell monkey -p "$PKG" -c android.intent.category.LAUNCHER 1
sleep 30
PID=$(adb shell pidof "$PKG" | tr -d '\r' || true)
if [ -z "$PID" ]; then
  echo "O aplicativo não está em execução."
  adb logcat -d | tail -300
  exit 1
fi
echo "Em execução (PID $PID)"
if adb logcat -d | grep -E "FATAL EXCEPTION|E/flutter" ; then
  echo "Erro detectado no log:"
  adb logcat -d | tail -300
  exit 1
fi

echo "=== Reabrindo (persistência) ==="
adb shell am force-stop "$PKG"
sleep 3
adb shell monkey -p "$PKG" -c android.intent.category.LAUNCHER 1
sleep 20
PID=$(adb shell pidof "$PKG" | tr -d '\r' || true)
if [ -z "$PID" ]; then
  echo "O aplicativo não reabriu."
  adb logcat -d | tail -300
  exit 1
fi
adb shell am force-stop "$PKG"

echo "=== Teste de integração no aparelho ==="
adb uninstall "$PKG" || true
flutter test integration_test -d emulator-5554 --reporter expanded
echo "TESTES NO ANDROID PASSARAM"
