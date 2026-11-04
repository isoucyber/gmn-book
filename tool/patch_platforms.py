"""Ajusta os projetos nativos gerados por `flutter create` (Android e Windows).

Idempotente: pode rodar varias vezes. Executado pelo CI logo apos o
`flutter create`, e tambem pode ser usado localmente.
"""
import os
import re
import shutil
import sys

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), '..'))
APP_NAME = 'GMN BOOK'
COMPANY = 'GMN BOOK'


def read(p):
    with open(p, encoding='utf-8') as f:
        return f.read()


def write(p, s):
    with open(p, 'w', encoding='utf-8', newline='\n') as f:
        f.write(s)


def patch_android():
    man = os.path.join(ROOT, 'android', 'app', 'src', 'main', 'AndroidManifest.xml')
    if not os.path.exists(man):
        print('android: projeto nao encontrado, pulando')
        return
    s = read(man)
    perms = [
        '<uses-permission android:name="android.permission.INTERNET"/>',
        '<uses-permission android:name="android.permission.CAMERA"/>',
        '<uses-feature android:name="android.hardware.camera" android:required="false"/>',
    ]
    for p in perms:
        if p not in s:
            s = s.replace('<application', p + '\n    <application', 1)
    s = re.sub(r'android:label="[^"]*"', f'android:label="{APP_NAME}"', s, count=1)
    # Dados ficam so no aparelho: sem backup automatico do Android (a chave do
    # banco fica no Keystore e nao seria restaurada junto).
    if 'android:allowBackup' not in s:
        s = s.replace('<application', '<application\n        android:allowBackup="false"\n        android:fullBackupContent="false"', 1)
    write(man, s)

    gradle_kts = os.path.join(ROOT, 'android', 'app', 'build.gradle.kts')
    gradle = os.path.join(ROOT, 'android', 'app', 'build.gradle')
    if os.path.exists(gradle_kts):
        s = read(gradle_kts)
        if 'keystoreProperties' not in s:
            header = (
                'import java.io.FileInputStream\n'
                'import java.util.Properties\n\n'
            )
            props = (
                '\nval keystoreProperties = Properties()\n'
                'val keystorePropertiesFile = rootProject.file("key.properties")\n'
                'if (keystorePropertiesFile.exists()) {\n'
                '    keystoreProperties.load(FileInputStream(keystorePropertiesFile))\n'
                '}\n'
            )
            s = header + s
            # Propriedades logo apos o bloco plugins { ... }
            m = re.search(r'plugins\s*\{[^}]*\}\n', s)
            s = s[:m.end()] + props + s[m.end():] if m else s + props
            signing = (
                '    signingConfigs {\n'
                '        create("release") {\n'
                '            if (keystorePropertiesFile.exists()) {\n'
                '                keyAlias = keystoreProperties["keyAlias"] as String\n'
                '                keyPassword = keystoreProperties["keyPassword"] as String\n'
                '                storeFile = file(keystoreProperties["storeFile"] as String)\n'
                '                storePassword = keystoreProperties["storePassword"] as String\n'
                '            }\n'
                '        }\n'
                '    }\n\n'
                '    buildTypes {'
            )
            s = s.replace('    buildTypes {', signing, 1)
            s = s.replace(
                'signingConfig = signingConfigs.getByName("debug")',
                'signingConfig = if (keystorePropertiesFile.exists()) signingConfigs.getByName("release") '
                'else signingConfigs.getByName("debug")',
            )
        write(gradle_kts, s)
    elif os.path.exists(gradle):
        print('aviso: build.gradle (Groovy) encontrado; assinatura nao configurada automaticamente')
    print('android: ok')


def patch_windows():
    runner = os.path.join(ROOT, 'windows', 'runner')
    if not os.path.isdir(runner):
        print('windows: projeto nao encontrado, pulando')
        return
    main = os.path.join(runner, 'main.cpp')
    s = read(main)
    s = re.sub(r'window\.Create\(L"[^"]*"', f'window.Create(L"{APP_NAME}"', s)
    s = re.sub(r'Win32Window::Size size\(\d+, \d+\)', 'Win32Window::Size size(1280, 800)', s)
    write(main, s)

    rc = os.path.join(runner, 'Runner.rc')
    s = read(rc)
    s = re.sub(r'VALUE "CompanyName", "[^"]*"', f'VALUE "CompanyName", "{COMPANY}"', s)
    s = re.sub(r'VALUE "FileDescription", "[^"]*"', f'VALUE "FileDescription", "{APP_NAME}"', s)
    s = re.sub(r'VALUE "ProductName", "[^"]*"', f'VALUE "ProductName", "{APP_NAME}"', s)
    s = re.sub(r'VALUE "LegalCopyright", "[^"]*"', 'VALUE "LegalCopyright", "GMN BOOK"', s)
    write(rc, s)

    ico = os.path.join(ROOT, 'assets', 'brand', 'app_icon.ico')
    if os.path.exists(ico):
        shutil.copyfile(ico, os.path.join(runner, 'resources', 'app_icon.ico'))
    print('windows: ok')


if __name__ == '__main__':
    targets = sys.argv[1:] or ['android', 'windows']
    if 'android' in targets:
        patch_android()
    if 'windows' in targets:
        patch_windows()
