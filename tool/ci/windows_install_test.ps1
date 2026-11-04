# Teste de instalacao do GMN BOOK no Windows (CI).
# Instala silenciosamente, confere os arquivos, abre o app SEM Flutter/Dart no
# PATH e fora da pasta do projeto, confere a criacao do banco no diretorio
# persistente, reabre (persistencia), desinstala e confirma que os dados ficaram.
param([Parameter(Mandatory = $true)][string]$Installer)
$ErrorActionPreference = "Stop"

function Step($m) { Write-Host "`n=== $m ===" -ForegroundColor Cyan }

Step "Instalando $Installer"
$log = Join-Path $env:RUNNER_TEMP "gmn_install.log"
$p = Start-Process $Installer -ArgumentList "/VERYSILENT", "/SUPPRESSMSGBOXES", "/NORESTART", "/CURRENTUSER", "/LOG=`"$log`"" -Wait -PassThru
if ($p.ExitCode -ne 0) { Get-Content $log -Tail 60; throw "Instalador retornou $($p.ExitCode)" }

$appDir = Join-Path $env:LOCALAPPDATA "Programs\GMN BOOK"
$exe = Join-Path $appDir "gmn_book.exe"
if (-not (Test-Path $exe)) { Get-Content $log -Tail 60; throw "Executável não encontrado em $appDir" }

Step "Arquivos instalados"
Get-ChildItem $appDir -Recurse -File | Select-Object @{n = 'Arquivo'; e = { $_.FullName.Replace($appDir, '') } }, Length | Format-Table -AutoSize
foreach ($f in @("gmn_book.exe", "flutter_windows.dll", "data\icudtl.dat", "data\app.so", "msvcp140.dll", "vcruntime140.dll", "vcruntime140_1.dll")) {
  if (-not (Test-Path (Join-Path $appDir $f))) { throw "Arquivo obrigatório ausente: $f" }
}
$sqlite = Get-ChildItem $appDir -Recurse -File | Where-Object { $_.Name -match 'sqlite' }
if (-not $sqlite) { throw "Biblioteca SQLite nativa não foi incluída no pacote" }
Write-Host "SQLite nativo: $($sqlite.Name -join ', ')"

$shortcut = Get-ChildItem "$env:APPDATA\Microsoft\Windows\Start Menu\Programs" -Recurse -Filter "GMN BOOK.lnk" -ErrorAction SilentlyContinue
if (-not $shortcut) { throw "Atalho do Menu Iniciar não foi criado" }

Step "Abrindo o aplicativo instalado (PATH mínimo, fora do projeto)"
$env:PATH = "C:\Windows\System32;C:\Windows;C:\Windows\System32\Wbem"
$proc = Start-Process $exe -WorkingDirectory $env:TEMP -PassThru
Start-Sleep -Seconds 25
if ($proc.HasExited) { throw "O aplicativo fechou sozinho (código $($proc.ExitCode))" }
Write-Host "Aplicativo em execução (PID $($proc.Id))."

$db = Get-ChildItem $env:APPDATA -Recurse -Filter "gmn_book.db" -ErrorAction SilentlyContinue | Select-Object -First 1
if (-not $db) { throw "Banco de dados local não foi criado em %APPDATA%" }
Write-Host "Banco criado em: $($db.FullName) ($($db.Length) bytes)"
$fs = [System.IO.File]::Open($db.FullName, [System.IO.FileMode]::Open, [System.IO.FileAccess]::Read, [System.IO.FileShare]::ReadWrite)
$buf = New-Object byte[] 15
[void]$fs.Read($buf, 0, 15)
$fs.Close()
$head = [System.Text.Encoding]::ASCII.GetString($buf)
if ($head -eq "SQLite format 3") { throw "O banco NÃO está criptografado" }
Write-Host "Banco criptografado: ok"
Stop-Process -Id $proc.Id -Force
Start-Sleep -Seconds 3

Step "Reabrindo (persistência)"
$proc2 = Start-Process $exe -WorkingDirectory $env:TEMP -PassThru
Start-Sleep -Seconds 15
if ($proc2.HasExited) { throw "O aplicativo não reabriu (código $($proc2.ExitCode))" }
Stop-Process -Id $proc2.Id -Force
Start-Sleep -Seconds 3

Step "Desinstalando"
$unins = Join-Path $appDir "unins000.exe"
$u = Start-Process $unins -ArgumentList "/VERYSILENT", "/SUPPRESSMSGBOXES", "/NORESTART" -Wait -PassThru
Start-Sleep -Seconds 5
if (Test-Path $exe) { throw "Desinstalação não removeu o executável" }
if (-not (Test-Path $db.FullName)) { throw "Os dados do usuário foram apagados na desinstalação" }
Write-Host "Desinstalado; dados preservados em $($db.DirectoryName)."

Step "Reinstalando sobre dados existentes (atualização)"
$p = Start-Process $Installer -ArgumentList "/VERYSILENT", "/SUPPRESSMSGBOXES", "/NORESTART", "/CURRENTUSER" -Wait -PassThru
if ($p.ExitCode -ne 0) { throw "Reinstalação falhou" }
$proc3 = Start-Process $exe -WorkingDirectory $env:TEMP -PassThru
Start-Sleep -Seconds 15
if ($proc3.HasExited) { throw "O aplicativo não abriu com os dados existentes (código $($proc3.ExitCode))" }
Stop-Process -Id $proc3.Id -Force
Write-Host "`nTODOS OS TESTES DE INSTALAÇÃO PASSARAM" -ForegroundColor Green
