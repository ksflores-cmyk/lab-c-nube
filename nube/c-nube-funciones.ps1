# Funciones del borrador de la nube (19 nov 2026). Las prueba trading\nube\probar-c-nube.ps1.

# Lee los secretos y los saca del entorno de inmediato: ningun proceso hijo (instalador, compilador) los hereda
# (Codex r1, hallazgo 8).
function Leer-Secretos {
  $s = [pscustomobject]@{ Login = $env:MT5_LOGIN; Clave = $env:MT5_PASSWORD; Servidor = $env:MT5_SERVER }
  Remove-Item Env:MT5_PASSWORD, Env:MT5_LOGIN, Env:MT5_SERVER -ErrorAction SilentlyContinue
  return $s
}

# Solo la demo: login 480624987 y un servidor Trial de Exness (Codex r1, hallazgo 9). El asesor lo vuelve a revisar.
function Cuenta-Valida([string]$Login, [string]$Servidor) {
  return ($Login -eq '480624987') -and ($Servidor -cmatch '\AExness-MT5Trial\d+\z') # \z: sin salto de linea al final (Codex r2)
}

# Solo maquinas de GitHub, nunca un runner autohospedado como la PC de Kevin (Codex r2, hallazgo 2).
function Entorno-Valido($GithubActions, $RunnerEnvironment) {
  return ($GithubActions -eq 'true') -and ($RunnerEnvironment -eq 'github-hosted')
}

# Que cerrar al terminar: solo el MT5 que abrio el script, y nunca uno que ya estaba antes (Codex r1, hallazgo 10).
function Elegir-Para-Cerrar([int[]]$Antes, $Propio) {
  if ($null -eq $Propio) { return @() }
  if ($Antes -contains [int]$Propio) { return @() }
  return @([int]$Propio)
}

# Busca claves escritas a mano en textos que van al repo publico (Codex p1, hallazgo 5): una palabra como password,
# clave, token o secret seguida de = o : y un valor literal (no una variable con $). Solo se permite el valor ficticio
# exacto de las pruebas ('centinela-123').
function Buscar-Claves([string[]]$Textos) {
  $patron = '(?im)(password|passwd|clave|token|secret)\w*\s*[=:]\s*["'']?(?![$"''\s])([^\s"''$]{3,})'
  foreach ($t in $Textos) {
    foreach ($m in [regex]::Matches([string]$t, $patron)) { if ($m.Groups[2].Value -cne 'centinela-123') { return $true } } # solo el valor exacto (Codex p2)
  }
  return $false
}

# La prueba de humo no corre cerca de la venta: de lunes a viernes, de 8:15 a 10:15 de Nueva York (la ventana de
# entrada es 8:30-8:45 y la salida a las 10:05). Asi nunca puede operar (Codex c1, hallazgo 4).
function Humo-Instante-Libre([DateTime]$Utc) {
  $ny = [System.TimeZoneInfo]::ConvertTimeFromUtc([DateTime]::SpecifyKind($Utc, [DateTimeKind]::Utc), [System.TimeZoneInfo]::FindSystemTimeZoneById('Eastern Standard Time'))
  if ($ny.DayOfWeek -eq 'Saturday' -or $ny.DayOfWeek -eq 'Sunday') { return $true }
  $min = $ny.Hour * 60 + $ny.Minute
  return -not ($min -ge 8 * 60 + 15 -and $min -le 10 * 60 + 15)
}
# Codex c2, hallazgo 3: libre ahora Y durante los 5 minutos que dura el humo (se revisa otra vez justo antes de abrir MT5)
function Humo-Permitido([DateTime]$Utc) {
  return (Humo-Instante-Libre $Utc) -and (Humo-Instante-Libre $Utc.AddMinutes(5))
}

# Codex c2, hallazgo 1: cierra un proceso y confirma que salio; $false si sigue vivo
function Cerrar-Id([int]$Id, [int]$Espera = 30) {
  $p = Get-Process -Id $Id -ErrorAction SilentlyContinue
  if (-not $p) { return $true }
  try { $p.CloseMainWindow() | Out-Null } catch { }
  for ($i = 0; $i -lt $Espera -and -not $p.HasExited; $i++) { Start-Sleep 1; try { $p.Refresh() } catch { } }
  if (-not $p.HasExited) { Stop-Process -Id $Id -Force -ErrorAction SilentlyContinue }
  for ($i = 0; $i -lt 10; $i++) {
    if (-not (Get-Process -Id $Id -ErrorAction SilentlyContinue)) { return $true }
    Start-Sleep 1
  }
  return $false
}

# La prueba de humo pasa solo si un registro del asesor tiene su linea "listo" con la cuenta demo valida
# (Codex c1, hallazgo 5). Los registros de MT5 estan en UTF-16.
function Humo-Listo([string[]]$Rutas) {
  foreach ($r in $Rutas) {
    if (-not (Test-Path $r)) { continue }
    # linea por linea (Codex c2, hallazgo 2): "listo" y "demo ok" en la misma
    foreach ($l in (Get-Content $r -Encoding Unicode)) { if ($l -match 'CalibracionC: listo\..*cuenta: demo ok') { return $true } }
  }
  return $false
}

# ini temporal (igual que trading\mt5\calibracion-c.ini, mas la cuenta). Se escribe justo antes de abrir MT5.
function Escribir-Ini($s) {
  $ini = Join-Path $env:TEMP ('c-nube-' + [guid]::NewGuid().ToString('N') + '.ini')
  $texto = "[Common]`r`nLogin=$($s.Login)`r`nPassword=$($s.Clave)`r`nServer=$($s.Servidor)`r`n" +
    "[Experts]`r`nAllowLiveTrading=1`r`nAllowDllImport=0`r`nEnabled=1`r`nAccount=0`r`nProfile=0`r`n" +
    "[StartUp]`r`nExpert=CalibracionC`r`nSymbol=XAUUSDm`r`nPeriod=M1`r`n"
  Set-Content -Path $ini -Value $texto -Encoding ASCII -NoNewline
  return $ini
}
