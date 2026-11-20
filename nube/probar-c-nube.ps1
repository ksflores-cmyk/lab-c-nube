# Pruebas del borrador de la nube (Codex r1, 19 nov 2026: hallazgos 8, 9 y 10). Sin MT5, sin red, sin claves reales.
# Uso: powershell -NoProfile -ExecutionPolicy Bypass -File trading\nube\probar-c-nube.ps1
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'c-nube-funciones.ps1')
$fallas = 0
function Revisar($nombre, $ok) { if ($ok) { Write-Host "ok   $nombre" } else { Write-Host "FALLA $nombre"; $script:fallas++ } }

# H8: los secretos salen del entorno antes de cualquier proceso hijo (instalador, compilador)
$env:MT5_LOGIN = '480624987'; $env:MT5_PASSWORD = 'centinela-123'; $env:MT5_SERVER = 'Exness-MT5Trial11'
$s = Leer-Secretos
Revisar 'H8 lee la clave' ($s.Clave -eq 'centinela-123')
Revisar 'H8 la clave ya no esta en el entorno' (-not (Test-Path Env:MT5_PASSWORD))
Revisar 'H8 el login y el servidor tampoco' (-not (Test-Path Env:MT5_LOGIN) -and -not (Test-Path Env:MT5_SERVER))
$hijo = (cmd /c "if defined MT5_PASSWORD (echo VE) else (echo NO)").Trim()
Revisar 'H8 un proceso hijo no ve la clave' ($hijo -eq 'NO')

# H9: solo la demo: login 480624987 y un servidor Trial de Exness
Revisar 'H9 acepta Exness-MT5Trial11' (Cuenta-Valida '480624987' 'Exness-MT5Trial11')
Revisar 'H9 rechaza un servidor real' (-not (Cuenta-Valida '480624987' 'Exness-MT5Real8'))
Revisar 'H9 rechaza un servidor con Trial en otro lado' (-not (Cuenta-Valida '480624987' 'Otro-Trial'))
Revisar 'H9 rechaza otra cuenta' (-not (Cuenta-Valida '12345' 'Exness-MT5Trial11'))
Revisar 'r2-H3 rechaza un servidor con salto de linea al final' (-not (Cuenta-Valida '480624987' "Exness-MT5Trial11`n"))

# r2-H2: solo maquinas de GitHub (no autohospedadas, como la PC de Kevin)
Revisar 'r2-H2 acepta github-hosted' (Entorno-Valido 'true' 'github-hosted')
Revisar 'r2-H2 rechaza self-hosted' (-not (Entorno-Valido 'true' 'self-hosted'))
Revisar 'r2-H2 rechaza fuera de Actions' (-not (Entorno-Valido $null 'github-hosted'))

# H10: al terminar se cierra solo el MT5 que abrio el script, nunca uno que ya estaba
Revisar 'H10 cierra solo el propio' ((@(Elegir-Para-Cerrar -Antes @(10, 20) -Propio 30)) -join ',' -eq '30')
Revisar 'H10 sin propio no cierra nada' (@(Elegir-Para-Cerrar -Antes @(10, 20) -Propio $null).Count -eq 0)
Revisar 'H10 no cierra un PID que ya estaba aunque sea el propio' (@(Elegir-Para-Cerrar -Antes @(10, 30) -Propio 30).Count -eq 0)

# Codex p1, hallazgo 5: buscar claves escritas en los archivos que van al repo publico (valores ficticios). Las
# cadenas se arman por partes para que este archivo, que tambien va al repo publico, no tenga texto con forma de clave.
$pw = 'Pass' + 'word'; $tk = 'TOK' + 'EN'; $falsa = 'DEMO_' + 'FICTICIA'
Revisar 'p1-H5 detecta una clave escrita tras el signo igual' (Buscar-Claves @("$pw=$falsa"))
Revisar 'p1-H5 detecta una asignacion de clave en PowerShell' (Buscar-Claves @("`$$($pw.ToLower()) = '$falsa'"))
Revisar 'p1-H5 detecta un token' (Buscar-Claves @("MARKETDATA_$tk=`"abc123xyz`""))
Revisar 'p2-H2 solo se permite el valor ficticio exacto de las pruebas' ((Buscar-Claves @("$pw=centinela123")) -and -not (Buscar-Claves @("$pw=centinela-123")))
Revisar 'p1-H5 no se queja de leer el secreto del entorno' (-not (Buscar-Claves @('Clave = $env:MT5_PASSWORD', 'Password=$($s.Clave)')))

# Codex c1, hallazgo 4: la prueba de humo no corre cerca de la ventana de la venta (8:15 a 10:15 NY, dias habiles)
Revisar 'c1-H4 humo permitido a las 2:40 NY' (Humo-Permitido ([DateTime]::new(2026, 11, 20, 7, 40, 0, [DateTimeKind]::Utc)))
Revisar 'c1-H4 humo negado a las 8:35 NY (13:35 UTC en invierno)' (-not (Humo-Permitido ([DateTime]::new(2026, 11, 20, 13, 35, 0, [DateTimeKind]::Utc))))
Revisar 'c1-H4 humo negado a las 10:05 NY' (-not (Humo-Permitido ([DateTime]::new(2026, 11, 20, 15, 5, 0, [DateTimeKind]::Utc))))
Revisar 'c1-H4 humo negado a las 8:35 NY en verano (12:35 UTC)' (-not (Humo-Permitido ([DateTime]::new(2026, 6, 10, 12, 35, 0, [DateTimeKind]::Utc))))
Revisar 'c1-H4 humo permitido un sabado a las 8:35 NY' (Humo-Permitido ([DateTime]::new(2026, 11, 21, 13, 35, 0, [DateTimeKind]::Utc)))

# Codex c1, hallazgo 5: la prueba de humo exige la linea "listo" del asesor con la cuenta demo
$lg = Join-Path $env:TEMP ('humo-' + [guid]::NewGuid().ToString('N') + '.log')
Set-Content $lg "0`t09:00`tCalibracionC (XAUUSDm,M1)`tCalibracionC: listo. Operaciones hechas: 0 de 20. Trading algoritmico en el terminal: si; en este asesor: si; cuenta: demo ok" -Encoding Unicode
Revisar 'c1-H5 reconoce la linea listo' (Humo-Listo @($lg))
Set-Content $lg "0`t09:00`tCalibracionC (XAUUSDm,M1)`tCalibracionC: listo. Operaciones hechas: 0 de 20. cuenta: la cuenta no es demo" -Encoding Unicode
Revisar 'c1-H5 no acepta si la cuenta no es demo' (-not (Humo-Listo @($lg)))
# Codex c2, hallazgo 2: "listo" y "demo ok" deben estar en la MISMA linea
Set-Content $lg @("0`t09:00`tCalibracionC (XAUUSDm,M1)`tCalibracionC: listo. Operaciones hechas: 0 de 20. cuenta: la cuenta no es demo", "0`t09:01`tCalibracionC (XAUUSDm,M1)`totra cosa; cuenta: demo ok") -Encoding Unicode
Revisar 'c2-H2 no junta dos lineas distintas' (-not (Humo-Listo @($lg)))
Remove-Item $lg -Force
Revisar 'c1-H5 sin registros no hay listo' (-not (Humo-Listo @()))

# Codex c2, hallazgo 3: el humo tampoco empieza si en los proximos minutos entraria a la ventana (8:11 NY + 5 min)
Revisar 'c2-H3 humo negado a las 8:11 NY (entraria a la ventana)' (-not (Humo-Permitido ([DateTime]::new(2026, 11, 20, 13, 11, 0, [DateTimeKind]::Utc))))
Revisar 'c2-H3 humo permitido a las 8:05 NY' (Humo-Permitido ([DateTime]::new(2026, 11, 20, 13, 5, 0, [DateTimeKind]::Utc)))

# Codex c2, hallazgo 1: cerrar un proceso confirma que de verdad salio
$hijo = Start-Process powershell -ArgumentList '-NoProfile -Command Start-Sleep 120' -PassThru -WindowStyle Hidden
Revisar 'c2-H1 Cerrar-Id cierra y confirma' ((Cerrar-Id -Id $hijo.Id -Espera 2) -and -not (Get-Process -Id $hijo.Id -ErrorAction SilentlyContinue))
Revisar 'c2-H1 Cerrar-Id con un proceso que ya no existe' (Cerrar-Id -Id $hijo.Id -Espera 1)

# el ini se escribe con la cuenta y se borra
$ini = Escribir-Ini $s
$texto = Get-Content $ini -Raw
Revisar 'ini con la cuenta y el asesor' ($texto -match 'Login=480624987' -and $texto -match 'Expert=CalibracionC' -and $texto -match 'AllowDllImport=0')
Remove-Item $ini -Force
Revisar 'ini borrado' (-not (Test-Path $ini))

if ($fallas) { Write-Host "$fallas fallas"; exit 1 } else { Write-Host 'todas pasan'; exit 0 }
