# lab-c-nube

Experimento C del laboratorio de trading de Kevin (solo cuenta DEMO de Exness; nunca dinero real).
Un asesor de MetaTrader 5 vende 0.01 lote de oro a las 8:30 de Nueva York cada dia habil, durante 20 dias, para
comparar la demo contra un simulador. No busca ganar: mide si el simulador se parece a la demo.

- `asesor/CalibracionC.mq5`: el asesor. Se niega a operar si la cuenta no es la demo 480624987 en un servidor Trial.
- `nube/correr-c-nube.ps1`: lo corre en una maquina Windows de GitHub Actions y guarda el registro del dia.
- `nube/probar-c-nube.ps1`: pruebas sin MT5 ni red.
- `.github/workflows/experimento-c.yml`: arranque manual; el horario va comentado hasta pasar la prueba de humo.

La clave de la demo vive solo en los secretos del repo (MT5_LOGIN, MT5_PASSWORD, MT5_SERVER). Nunca en un archivo.
