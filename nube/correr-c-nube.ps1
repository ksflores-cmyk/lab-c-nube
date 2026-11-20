# Experimento C en la nube (borrador del 19 nov 2026; NO ACTIVO). Lo llamaria el workflow trading/nube/experimento-c.yml
# en una maquina Windows de GitHub Actions. Hace lo mismo que la PC: abre MT5 con CalibracionC (sin cambios) para la
# demo, espera a que el asesor registre la operacion del dia y cierra MT5.
# Seguridad: sin la variable C_NUBE_ACTIVO=si no hace nada; fuera de GitHub Actions se niega; solo la demo 480624987 en
# un servidor Trial de Exness. Los secretos salen del entorno antes de instalar o compilar; la clave va a un .ini que
# se escribe justo antes de abrir MT5 y se borra al minuto. Al final cierra solo el MT5 que abrio (revision de Codex).
# Pruebas sin MT5 ni red:  powershell -NoProfile -ExecutionPolicy Bypass -File trading\nube\probar-c-nube.ps1
param(
  [string]$Carpeta = 'C:\Program Files\MetaTrader 5 EXNESS',
  [string]$Salida = (Join-Path $env:TEMP 'c-nube-salida'),
  [int]$PlazoMinutos = 140,
  [string]$Asesor = '', # ruta de CalibracionC.mq5; por defecto trading\mt5 de este repo; en el repo publico, asesor\
  [string]$Humo = 'false', # 'true': prueba de humo (entra, carga el asesor, guarda registros y cierra a los 3 min)
  [string]$Instalador = 'https://download.mql5.com/cdn/web/exness.technologies.ltd/mt5/exness5setup.exe'
)
$ErrorActionPreference = 'Stop'
$repo = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
. (Join-Path $PSScriptRoot 'c-nube-funciones.ps1')
function Anotar($t) { Write-Host "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') $t" }

$s = Leer-Secretos # primero: saca la clave del entorno
if ($env:C_NUBE_ACTIVO -ne 'si') { Anotar 'C_NUBE_ACTIVO no es "si": no hago nada'; exit 0 }
if (-not (Entorno-Valido $env:GITHUB_ACTIONS $env:RUNNER_ENVIRONMENT)) { Anotar 'solo corre en maquinas de GitHub Actions (no autohospedadas): me niego'; exit 1 }
if (-not $s.Login -or -not $s.Clave -or -not $s.Servidor) { Anotar 'faltan los secretos MT5_LOGIN, MT5_PASSWORD o MT5_SERVER'; exit 1 }
if (-not (Cuenta-Valida $s.Login $s.Servidor)) { Anotar 'la cuenta o el servidor no son la demo: me niego'; exit 1 }
if ($Humo -eq 'true' -and -not (Humo-Permitido ([DateTime]::UtcNow))) { Anotar 'prueba de humo cerca de la venta (8:15-10:15 NY): me niego'; exit 1 }

$antes = @(Get-Process terminal64 -ErrorAction SilentlyContinue | ForEach-Object { $_.Id })
$propio = $null
$ini = $null
$script:fallo = $false
# cierra solo el MT5 que abrio este script (y lo olvida, para no intentarlo dos veces)
function Cerrar-Propio {
  foreach ($id in (Elegir-Para-Cerrar -Antes $antes -Propio $script:propio)) {
    # si no se pudo cerrar, NO se olvida (el finally reintenta) y no se copia nada (Codex c2, hallazgo 1)
    if (-not (Cerrar-Id -Id $id -Espera 30)) { throw "MT5 ($id) sigue abierto tras cerrarlo" }
  }
  $script:propio = $null
}
try {
  # 1. instalar MT5 de Exness si falta (en la maquina de la nube, nunca en la PC de Kevin)
  $terminal = Join-Path $Carpeta 'terminal64.exe'
  if (-not (Test-Path $terminal)) {
    $setup = Join-Path $env:TEMP 'exness5setup.exe'
    Anotar "bajando el instalador gratuito de MT5: $Instalador"
    Invoke-WebRequest -Uri $Instalador -OutFile $setup -UseBasicParsing
    Start-Process $setup -ArgumentList '/auto' -Wait
    for ($i = 0; $i -lt 60 -and -not (Test-Path $terminal); $i++) { Start-Sleep 5 }
    if (-not (Test-Path $terminal)) { throw "no aparecio $terminal tras instalar" }
    # el instalador abre MT5 al terminar: se cierran solo los que no estaban antes
    Get-Process terminal64 -ErrorAction SilentlyContinue | Where-Object { $antes -notcontains $_.Id } | Stop-Process -Force
  }
  # 2. compilar CalibracionC tal cual esta en el repo
  $experts = Join-Path $Carpeta 'MQL5\Experts'
  New-Item -ItemType Directory -Force -Path $experts | Out-Null
  if (-not $Asesor) { $Asesor = Join-Path $repo 'trading\mt5\CalibracionC.mq5' }
  if (-not (Test-Path $Asesor)) { throw "no encuentro el asesor en $Asesor" }
  Copy-Item $Asesor $experts -Force
  $mq5 = Join-Path $experts 'CalibracionC.mq5'
  Start-Process (Join-Path $Carpeta 'MetaEditor64.exe') -ArgumentList "/portable /compile:`"$mq5`" /log" -Wait
  if (-not (Test-Path (Join-Path $experts 'CalibracionC.ex5'))) { throw 'no se compilo CalibracionC.ex5' }
  # 3. el ini con la clave se escribe ahora, se abre MT5 y se borra al minuto
  # otra vez justo antes de abrir MT5: la instalacion pudo tardar (Codex c2, hallazgo 3)
  if ($Humo -eq 'true' -and -not (Humo-Permitido ([DateTime]::UtcNow))) { throw 'prueba de humo: la instalacion se acerco a la venta (8:15-10:15 NY); no abro MT5' }
  $ini = Escribir-Ini $s
  $propio = (Start-Process $terminal -ArgumentList "/portable /config:`"$ini`"" -PassThru).Id
  Start-Sleep 60
  Remove-Item $ini -Force -ErrorAction SilentlyContinue
  # 4. esperar el registro del dia (CalibracionC lo escribe despues de las 10:06 de Nueva York); en la prueba de humo,
  #    solo 2 minutos mas (el asesor no opera fuera de las 8:30 NY)
  $comun = Join-Path $env:APPDATA 'MetaQuotes\Terminal\Common\Files\calibracion-c'
  $hoyNY = [System.TimeZoneInfo]::ConvertTimeBySystemTimeZoneId([DateTime]::UtcNow, 'Eastern Standard Time').ToString('yyyy-MM-dd')
  if ($Humo -eq 'true') { Anotar 'prueba de humo: espero 2 minutos y cierro'; Start-Sleep 120 }
  else {
    $limite = (Get-Date).AddMinutes($PlazoMinutos)
    while ((Get-Date) -lt $limite -and -not (Test-Path (Join-Path $comun "$hoyNY.json"))) { Start-Sleep 30 }
  }
  # 5. cerrar MT5 ANTES de copiar (asi vacia sus registros a disco; Codex c1, hallazgo 5)
  Cerrar-Propio
  # 6. copiar lo escrito y SOLO los registros del asesor (su linea "listo" dice si entro a la demo y si puede operar).
  #    Los registros de la terminal (carpeta logs) NO se copian: incluyen la IP desde la que se entro antes a la cuenta
  #    (la de la casa de Kevin) y el artefacto de un repo publico lo puede bajar cualquiera.
  New-Item -ItemType Directory -Force -Path $Salida | Out-Null
  if (Test-Path $comun) { Copy-Item (Join-Path $comun '*') $Salida -Force }
  Get-ChildItem (Join-Path $Carpeta 'MQL5\Logs') -Filter *.log -ErrorAction SilentlyContinue | ForEach-Object { Copy-Item $_.FullName (Join-Path $Salida ('asesor-' + $_.Name)) -Force }
  if ($Humo -eq 'true') {
    $logs = @(Get-ChildItem $Salida -Filter 'asesor-*.log' -ErrorAction SilentlyContinue | ForEach-Object { $_.FullName })
    if (Humo-Listo $logs) { Anotar 'PRUEBA DE HUMO OK: MT5 entro a la demo y el asesor cargo con permiso para operar' }
    else { Anotar 'PRUEBA DE HUMO FALLIDA: no aparece la linea "listo ... cuenta: demo ok" del asesor'; $script:fallo = $true }
  }
  elseif (Test-Path (Join-Path $Salida "$hoyNY.json")) { Anotar "registro del $hoyNY copiado" } else { Anotar "SIN registro del $hoyNY al vencer el plazo" }
} finally {
  if ($ini) { Remove-Item $ini -Force -ErrorAction SilentlyContinue }
  Cerrar-Propio
}
if ($script:fallo) { exit 1 }
