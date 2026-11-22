// COPIA DE LA NUBE; cuenta desde el historial de la cuenta (21 nov 2026): la nube arranca cada dia con el terminal vacio, asi que
// las operaciones hechas se cuentan con las entradas de la cuenta demo (ver EntradasEnLaCuenta), no con CalibC_n.
// Limite conocido: un dia invalido futuro (reinicio o ticks incompletos) ocupa cupo hasta que su fecha se agregue a NO_CUENTAN_FECHAS.
// Experimento C (propuesto por el laboratorio de Rodrigo; Kevin: "Hacer C", 17 nov 2026).
// Asesor Experto SÓLO PARA LA CUENTA DEMO: corre la estrategia 4 del simulador (venta de la mañana de Nueva York)
// para calibrar el simulador contra el bróker. No busca ganar: busca que la demo y el simulador coincidan.
//   - Vende 0.01 lote de XAUUSDm a las 8:30 de Nueva York (espera hasta 15 min si el spread pasa de 0.50).
//   - Stop a 10 USD sobre el precio ejecutado. Recompra a las 10:05 de Nueva York. Una operación por día, lunes a viernes.
//   - Se detiene solo al llegar a 20 operaciones.
// Por cada operación escribe en Common\Files\calibracion-c\: AAAA-MM-DD.json (medidas) y AAAA-MM-DD_ticks.csv
// (ticks del servidor de esos minutos, formato de Exness). Contraste: node trading/mt5/contraste-c.js
// Se niega a operar si la cuenta no es la demo 480624987, si el servidor no es "Trial" o si la cuenta no es demo.
#property strict

#define CUENTA_DEMO   480624987
#define SIMBOLO       "XAUUSDm"
#define LOTE          0.01
#define STOP_USD      10.0
#define ENTRADA_NY    510      // 8:30
#define SALIDA_NY     605      // 10:05
#define VENTANA_MIN   15
#define SPREAD_MAX    0.50
#define MAX_OPS       20
#define MAGICO        26111701
#define CARPETA       "calibracion-c\\"
// Conteo desde el historial de la cuenta (copia de la nube). INICIO_C: primer dia del experimento (hora del servidor).
// NO_CUENTAN_FECHAS (abajo): fechas de entradas del asesor que estan en el historial pero no sirven para el contraste.
#define INICIO_C      D'2026.11.17 00:00'
// Piso conocido: al 21 nov 2026 la cuenta ya tiene entradas de 3 fechas (17, 18 y 20 nov). Si el historial trae menos, es que
// aun no termino de llegar (terminal recien abierto): se trata como lectura fallida y no se vende.
#define ENTRADAS_MINIMAS 3
// Fechas (Nueva York) de entradas que no sirven para el contraste. Si la revision diaria encuentra otra (reinicio o ticks
// incompletos), se agrega aqui. 17 nov 2026: entrada sin registro valido (no cuenta en el contraste).
string NO_CUENTAN_FECHAS[] = {"2026-11-17"};

// ---------- hora de Nueva York (horario de verano de EE. UU.: 2.º domingo de marzo a 1.er domingo de noviembre)
datetime DomingoN(int anio, int mes, int n) { // n-ésimo domingo del mes, 00:00
   MqlDateTime d; ZeroMemory(d); d.year = anio; d.mon = mes; d.day = 1;
   datetime t = StructToTime(d); TimeToStruct(t, d);
   int primero = 1 + (7 - d.day_of_week) % 7;
   d.day = primero + 7 * (n - 1); d.hour = 0; d.min = 0; d.sec = 0;
   return StructToTime(d);
}
bool VeranoEEUU(datetime gmt) {
   MqlDateTime d; TimeToStruct(gmt, d);
   datetime ini = DomingoN(d.year, 3, 2) + 7 * 3600;  // 2:00 EST = 7:00 UTC
   datetime fin = DomingoN(d.year, 11, 1) + 6 * 3600; // 2:00 EDT = 6:00 UTC
   return gmt >= ini && gmt < fin;
}
datetime HoraNY(datetime gmt) { return gmt - (VeranoEEUU(gmt) ? 4 : 5) * 3600; }
int MinutoNY(datetime gmt) { MqlDateTime d; TimeToStruct(HoraNY(gmt), d); return d.hour * 60 + d.min; }
int DiaSemanaNY(datetime gmt) { MqlDateTime d; TimeToStruct(HoraNY(gmt), d); return d.day_of_week; }
string FechaNY(datetime gmt) { string f = TimeToString(HoraNY(gmt), TIME_DATE); StringReplace(f, ".", "-"); return f; }

// ---------- utilidades
string Q(string s) { return "\"" + s + "\""; }
string N(double v, int dg = 3) { return DoubleToString(v, dg); }
bool Escribir(string nombre, string texto) {
   int h = FileOpen(CARPETA + nombre, FILE_WRITE | FILE_TXT | FILE_ANSI | FILE_COMMON);
   if(h == INVALID_HANDLE) { Print("CalibracionC: no se pudo escribir ", nombre, ": ", GetLastError()); return false; }
   uint esc = FileWriteString(h, texto); FileClose(h);
   // Revisa que se escribió todo (revisión de Codex, ronda 2). En modo texto Windows cambia cada "\n" por "\r\n": los bytes escritos son los caracteres más un byte por
   // línea. Se aceptan las dos cuentas. Corrige el 17 nov el control de la ronda 2, que exigía bytes = caracteres
   // y rechazó el registro de la primera operación.
   string copia = texto; int lineas = StringReplace(copia, "\n", "\n"); if(lineas < 0) lineas = 0;
   uint largo = (uint)StringLen(texto);
   if(esc != largo && esc != largo + (uint)lineas) { Print("CalibracionC: escritura incompleta en ", nombre, " (", esc, " de ", largo, " + ", lineas, " saltos)"); return false; }
   return true;
}
ENUM_ORDER_TYPE_FILLING Relleno() {
   long fm = SymbolInfoInteger(SIMBOLO, SYMBOL_FILLING_MODE);
   if((fm & SYMBOL_FILLING_FOK) != 0) return ORDER_FILLING_FOK;
   if((fm & SYMBOL_FILLING_IOC) != 0) return ORDER_FILLING_IOC;
   return ORDER_FILLING_RETURN;
}
bool CuentaValida(string &motivo) {
   if(AccountInfoInteger(ACCOUNT_LOGIN) != CUENTA_DEMO) { motivo = "la cuenta activa no es la demo"; return false; }
   if(AccountInfoInteger(ACCOUNT_TRADE_MODE) != ACCOUNT_TRADE_MODE_DEMO) { motivo = "la cuenta no es demo"; return false; }
   if(StringFind(AccountInfoString(ACCOUNT_SERVER), "Trial") < 0) { motivo = "el servidor no es Trial"; return false; }
   return true;
}
ulong MiPosicion() {
   for(int i = PositionsTotal() - 1; i >= 0; i--) { ulong tk = PositionGetTicket(i); if(PositionGetInteger(POSITION_MAGIC) == MAGICO) return tk; }
   return 0;
}
double Gv(string n, double def) { return GlobalVariableCheck(n) ? GlobalVariableGet(n) : def; }
// Candado C (Kevin: "Candado C", 20 nov 2026): la cuenta demo es la misma en la PC y en la nube. Antes de vender se
// revisa el historial de la CUENTA (no las variables de este terminal): si ya hay una entrada de hoy (fecha de Nueva
// York) con este numero magico, hecha por cualquier copia, no se vende. Si el historial no se puede leer, tampoco se
// vende en este paso (se reintenta al segundo siguiente, dentro de la ventana).
// Devuelve 1 si la cuenta ya tiene una entrada de hoy, 0 si no, y -1 si no se pudo leer bien el historial (en ese
// caso tampoco se vende; Codex c1, hallazgos 2 y 3: cualquier lectura fallida bloquea, con su propio mensaje).
string gErrHist = ""; // detalle de la ultima lectura fallida (se imprime una vez, con el aviso)
int OperoHoyEnLaCuenta(string fecha) {
   long desfase = (long)(TimeTradeServer() - TimeGMT());
   if(!HistorySelect(TimeTradeServer() - 3 * 86400, TimeTradeServer() + 3600)) { gErrHist = StringFormat("fallo HistorySelect, error %d", GetLastError()); return -1; }
   for(int i = HistoryDealsTotal() - 1; i >= 0; i--) {
      ulong d = HistoryDealGetTicket(i);
      if(d == 0) { gErrHist = StringFormat("fallo HistoryDealGetTicket(%d), error %d", i, GetLastError()); return -1; }
      long magico = 0, entrada = 0, hora = 0;
      // primero el magico: un deal ajeno ya no puede bloquear aunque falle leer lo demas (Codex c2, hallazgo 4)
      if(!HistoryDealGetInteger(d, DEAL_MAGIC, magico)) { gErrHist = StringFormat("fallo DEAL_MAGIC del deal %I64u, error %d", d, GetLastError()); return -1; }
      if(magico != MAGICO) continue;
      if(!HistoryDealGetInteger(d, DEAL_ENTRY, entrada) || !HistoryDealGetInteger(d, DEAL_TIME, hora)) { gErrHist = StringFormat("fallo DEAL_ENTRY/DEAL_TIME del deal %I64u, error %d", d, GetLastError()); return -1; }
      if(entrada != DEAL_ENTRY_IN) continue;
      if(FechaNY((datetime)(hora - desfase)) == fecha) return 1;
   }
   return 0;
}

// Cuenta las FECHAS de Nueva York distintas con una entrada (DEAL_ENTRY_IN) de este asesor (numero magico) en SIMBOLO,
// desde INICIO_C, leyendo el historial de la CUENTA (la copia de la nube no conserva variables entre dias).
// Devuelve -1 (y deja el detalle en gErrHist) si cualquier lectura falla, si el desfase horario es imposible (>14 h) o si
// aparecen menos de ENTRADAS_MINIMAS fechas: en esos casos no se vende. Deja las fechas en gFechasCuenta.
string gFechasCuenta[];
int EntradasEnLaCuenta() {
   long desfase = (long)(TimeTradeServer() - TimeGMT());
   if(desfase > 14 * 3600 || desfase < -14 * 3600) { gErrHist = StringFormat("desfase horario imposible (%I64d s)", desfase); return -1; }
   if(!HistorySelect(INICIO_C, TimeTradeServer() + 3600)) { gErrHist = StringFormat("fallo HistorySelect, error %d", GetLastError()); return -1; }
   string fechas[]; int nf = 0;
   ArrayResize(gFechasCuenta, 0);
   for(int i = HistoryDealsTotal() - 1; i >= 0; i--) {
      ulong d = HistoryDealGetTicket(i);
      if(d == 0) { gErrHist = StringFormat("fallo HistoryDealGetTicket(%d), error %d", i, GetLastError()); return -1; }
      long magico = 0, entrada = 0, hora = 0; string simbolo = "";
      if(!HistoryDealGetInteger(d, DEAL_MAGIC, magico)) { gErrHist = StringFormat("fallo DEAL_MAGIC del deal %I64u, error %d", d, GetLastError()); return -1; }
      if(magico != MAGICO) continue;
      if(!HistoryDealGetInteger(d, DEAL_ENTRY, entrada) || !HistoryDealGetInteger(d, DEAL_TIME, hora)) { gErrHist = StringFormat("fallo DEAL_ENTRY/DEAL_TIME del deal %I64u, error %d", d, GetLastError()); return -1; }
      if(entrada != DEAL_ENTRY_IN) continue;
      if(!HistoryDealGetString(d, DEAL_SYMBOL, simbolo)) { gErrHist = StringFormat("fallo DEAL_SYMBOL del deal %I64u, error %d", d, GetLastError()); return -1; }
      if(simbolo != SIMBOLO) continue;
      string f = FechaNY((datetime)(hora - desfase));
      bool ya = false;
      for(int k = 0; k < nf; k++) if(fechas[k] == f) { ya = true; break; }
      if(!ya) { ArrayResize(fechas, nf + 1); fechas[nf] = f; nf++; }
   }
   if(nf < ENTRADAS_MINIMAS) { gErrHist = StringFormat("el historial trae %d fechas con entrada y se esperaban al menos %d", nf, ENTRADAS_MINIMAS); return -1; }
   ArrayResize(gFechasCuenta, nf);
   for(int k = 0; k < nf; k++) gFechasCuenta[k] = fechas[k];
   return nf;
}
// Operaciones validas hechas segun la cuenta: fechas distintas con entrada que NO estan en NO_CUENTAN_FECHAS; -1 si no se pudo leer.
int Hechas() {
   int n = EntradasEnLaCuenta();
   if(n < 0) return -1;
   int validas = 0;
   for(int i = 0; i < n; i++) {
      bool fuera = false;
      for(int k = 0; k < ArraySize(NO_CUENTAN_FECHAS); k++) if(NO_CUENTAN_FECHAS[k] == gFechasCuenta[i]) { fuera = true; break; }
      if(!fuera) validas++;
   }
   return validas;
}

// ---------- estado de la operación del día (en memoria; el día operado y el conteo, en variables globales de MT5)
string gFecha = ""; ulong gPos = 0; MqlTick gTickEnt; double gPedidoEnt = 0, gLatEnt = 0; uint gRetEnt = 0; double gSaldo0 = 0;
MqlTick gTickSal; double gPedidoSal = 0, gLatSal = 0; uint gRetSal = 0; bool gCerrando = false; datetime gCerradaEn = 0; string gAviso = "";
bool gCopia = false, gReinicio = false; datetime gReintentoReg = 0; int gIntentosTicks = 0;

int OnInit() {
   // Una sola copia a la vez: si MT5 abre dos gráficos con este asesor, la segunda se retira (variable temporal de
   // la sesión del terminal: se borra sola al cerrar MT5).
   // Toma del candado atómica: sólo una copia logra pasarlo de 0 a 1 (revisión de Codex, ronda 2).
   if(!GlobalVariableCheck("CalibC_activo")) GlobalVariableTemp("CalibC_activo");
   if(!GlobalVariableSetOnCondition("CalibC_activo", 1, 0)) { Print("CalibracionC: ya hay otra copia activa; ésta se retira"); gCopia = true; ExpertRemove(); return INIT_SUCCEEDED; }
   // Si MT5 se reinició con una posición de este asesor abierta, se adopta: se cierra a su hora y se registra
   // marcada como "reinicio" (el contraste no la cuenta: faltan los datos de la entrada).
   ulong p = MiPosicion();
   if(p > 0) { gPos = p; gFecha = FechaNY(TimeGMT()); gReinicio = true; Print("CalibracionC: adopté una posición abierta tras un reinicio"); }
   EventSetTimer(1);
   string motivo = "";
   int hechasInit = Hechas();
   string textoHechas = (hechasInit < 0) ? "historial no legible" : IntegerToString(hechasInit);
   Print("CalibracionC: listo. Operaciones hechas (según la cuenta): ", textoHechas, " de ", MAX_OPS,
         ". Trading algorítmico en el terminal: ", (TerminalInfoInteger(TERMINAL_TRADE_ALLOWED) ? "sí" : "NO"),
         "; en este asesor: ", (MQLInfoInteger(MQL_TRADE_ALLOWED) ? "sí" : "NO"),
         "; cuenta: ", (CuentaValida(motivo) ? "demo ok" : motivo));
   return INIT_SUCCEEDED;
}
void OnDeinit(const int r) { EventKillTimer(); if(!gCopia) GlobalVariableSet("CalibC_activo", 0); }
void OnTick() { if(!gCopia) Paso(); }
void OnTimer() { if(!gCopia) Paso(); }

void Paso() {
   datetime gmt = TimeGMT();
   int minNY = MinutoNY(gmt), dow = DiaSemanaNY(gmt);
   string fecha = FechaNY(gmt);
   string motivo = "";
   bool cuentaOk = CuentaValida(motivo);
   // Fuera de la demo no toca nada, ni siquiera posiciones con este número mágico (revisión de Codex).
   if(!cuentaOk) { if(gAviso != motivo) { Print("CalibracionC NO opera: ", motivo); gAviso = motivo; } return; }
   ulong pos = MiPosicion();

   // 1. Hay posición: corregir el stop sobre lo ejecutado y cerrar a las 10:05 NY (o si cambió el día).
   if(pos > 0) {
      if(PositionSelectByTicket(pos)) {
         double ent = PositionGetDouble(POSITION_PRICE_OPEN), sl = NormalizeDouble(ent + STOP_USD, 3);
         if(MathAbs(PositionGetDouble(POSITION_SL) - sl) > 0.0005) {
            MqlTradeRequest r; MqlTradeResult s; ZeroMemory(r); ZeroMemory(s);
            r.action = TRADE_ACTION_SLTP; r.position = pos; r.symbol = SIMBOLO; r.sl = sl; r.tp = 0; r.magic = MAGICO;
            if(!OrderSend(r, s)) Print("CalibracionC: no se pudo corregir el stop ", s.retcode);
         }
      }
      if(!gCerrando && (minNY >= SALIDA_NY || fecha != gFecha)) {
         MqlTradeRequest r; MqlTradeResult s; ZeroMemory(r); ZeroMemory(s);
         SymbolInfoTick(SIMBOLO, gTickSal);
         double vol = PositionSelectByTicket(pos) ? PositionGetDouble(POSITION_VOLUME) : LOTE; // el volumen real (revisión de Codex)
         r.action = TRADE_ACTION_DEAL; r.symbol = SIMBOLO; r.position = pos; r.volume = vol; r.type = ORDER_TYPE_BUY;
         r.price = gTickSal.ask; r.type_filling = Relleno(); r.deviation = 100; r.magic = MAGICO; r.comment = "CalibracionC cierre";
         ulong u0 = GetMicrosecondCount(); bool ok = OrderSend(r, s); ulong u1 = GetMicrosecondCount();
         gPedidoSal = r.price; gLatSal = (u1 - u0) / 1000.0; gRetSal = s.retcode;
         if(ok && s.retcode == TRADE_RETCODE_DONE) { gCerrando = true; gCerradaEn = TimeGMT(); }
         else Print("CalibracionC: cierre no confirmado ", s.retcode, "; se reintenta");
      }
      gPos = pos;
      return;
   }
   // 2. La posición de hoy ya no existe: cerró (por el stop o por el cierre). Un minuto después, se escriben los datos.
   if(gPos > 0 && gCerradaEn == 0) { gCerradaEn = TimeGMT(); gCerrando = false; }
   // Se registra después de las 10:06 NY, para que los ticks cubran también la salida del simulador aunque la demo
   // haya salido antes por el stop (revisión de Codex). Si falla la escritura, se reintenta al minuto.
   if(gPos > 0 && TimeGMT() - gCerradaEn >= 60 && (minNY >= SALIDA_NY + 1 || fecha != gFecha) && TimeGMT() >= gReintentoReg) {
      if(Registrar()) { gPos = 0; gCerradaEn = 0; gCerrando = false; } else gReintentoReg = TimeGMT() + 60;
      return;
   }
   if(gPos > 0) return;

   // 3. Sin posición: ¿toca entrar?
   if(!cuentaOk) return;
   if(dow == 0 || dow == 6) return;
   if(minNY < ENTRADA_NY || minNY > ENTRADA_NY + VENTANA_MIN || minNY >= SALIDA_NY) return;
   // Tope de 20 segun el historial de la CUENTA (la nube no conserva CalibC_n); se lee solo dentro de la ventana de entrada.
   int hechas = Hechas();
   if(hechas < 0) { if(gAviso != "historial") { Print("CalibracionC: no pude leer el historial de la cuenta; no vendo y reintento: ", gErrHist); gAviso = "historial"; } return; }
   if(hechas >= MAX_OPS) { if(gAviso != "tope") { Print("CalibracionC: ya hay 20 de 20 en la cuenta; no vendo"); gAviso = "tope"; } return; }
   if(GlobalVariableCheck("CalibC_dia_" + fecha)) return; // ya operó hoy (este terminal)
   int hoy = OperoHoyEnLaCuenta(fecha);
   if(hoy == 1) { if(gAviso != "candado") { Print("CalibracionC: la cuenta ya tiene una entrada de hoy; no vendo (candado C)"); gAviso = "candado"; } return; }
   if(hoy < 0) { if(gAviso != "historial") { Print("CalibracionC: no pude leer el historial de la cuenta; reintento (candado C): ", gErrHist); gAviso = "historial"; } return; }
   if(!TerminalInfoInteger(TERMINAL_TRADE_ALLOWED) || !MQLInfoInteger(MQL_TRADE_ALLOWED)) { if(gAviso != "algo") { Print("CalibracionC: el trading algorítmico está apagado"); gAviso = "algo"; } return; }
   SymbolSelect(SIMBOLO, true);
   MqlTick t; if(!SymbolInfoTick(SIMBOLO, t)) return;
   if(t.ask - t.bid > SPREAD_MAX + 1e-9) return;
   MqlTradeRequest r; MqlTradeResult s; ZeroMemory(r); ZeroMemory(s);
   r.action = TRADE_ACTION_DEAL; r.symbol = SIMBOLO; r.volume = LOTE; r.type = ORDER_TYPE_SELL; r.price = t.bid;
   r.sl = NormalizeDouble(t.bid + STOP_USD, 3); r.type_filling = Relleno(); r.deviation = 100; r.magic = MAGICO; r.comment = "CalibracionC";
   GlobalVariableSet("CalibC_dia_" + fecha, 1); // una por día, aunque falle (se anota abajo)
   gSaldo0 = AccountInfoDouble(ACCOUNT_BALANCE);
   ulong u0 = GetMicrosecondCount(); bool ok = OrderSend(r, s); ulong u1 = GetMicrosecondCount();
   gTickEnt = t; gPedidoEnt = r.price; gLatEnt = (u1 - u0) / 1000.0; gRetEnt = s.retcode; gFecha = fecha;
   if(!ok || (s.retcode != TRADE_RETCODE_DONE && s.retcode != TRADE_RETCODE_DONE_PARTIAL && s.retcode != TRADE_RETCODE_PLACED)) {
      Escribir(fecha + ".json", "{\"fecha\": " + Q(fecha) + ", \"rechazada\": true, \"retcode\": " + IntegerToString(s.retcode) + ", \"comentario\": " + Q(s.comment) + "}\n");
      Print("CalibracionC: venta rechazada ", s.retcode, " ", s.comment);
      return;
   }
   for(int k = 0; k < 300 && gPos == 0; k++) { gPos = MiPosicion(); if(gPos == 0) Sleep(100); }
   if(gPos == 0) Print("CalibracionC: la posición no apareció en 30 s");
}

bool Registrar() {
   HistorySelect(TimeTradeServer() - 2 * 86400, TimeTradeServer() + 120);
   double pEnt = 0, pSal = 0, com = 0, swp = 0, ben = 0; long msEnt = 0, msSal = 0; string mot = "";
   for(int i = 0; i < HistoryDealsTotal(); i++) {
      ulong d = HistoryDealGetTicket(i);
      if(HistoryDealGetInteger(d, DEAL_POSITION_ID) != (long)gPos) continue;
      com += HistoryDealGetDouble(d, DEAL_COMMISSION); swp += HistoryDealGetDouble(d, DEAL_SWAP); ben += HistoryDealGetDouble(d, DEAL_PROFIT);
      long e = HistoryDealGetInteger(d, DEAL_ENTRY);
      if(e == DEAL_ENTRY_IN) { pEnt = HistoryDealGetDouble(d, DEAL_PRICE); msEnt = HistoryDealGetInteger(d, DEAL_TIME_MSC); }
      if(e == DEAL_ENTRY_OUT) { pSal = HistoryDealGetDouble(d, DEAL_PRICE); msSal = HistoryDealGetInteger(d, DEAL_TIME_MSC);
         long r = HistoryDealGetInteger(d, DEAL_REASON); mot = (r == DEAL_REASON_SL ? "sl" : "cierre"); }
   }
   // ticks del servidor: desde 2 minutos antes de la decisión (o de la entrada, tras un reinicio) hasta ahora
   // (después de las 10:06 NY, así cubren la salida del simulador aunque la demo haya salido antes)
   MqlTick tk[];
   long ini = gTickEnt.time_msc > 0 ? gTickEnt.time_msc : msEnt;
   if(ini <= 0) { Print("CalibracionC: no encontré la entrada en el historial; se reintenta"); return false; }
   long desde = ini - 120000, hasta = (long)TimeTradeServer() * 1000;
   int n = CopyTicksRange(SIMBOLO, tk, COPY_TICKS_INFO, (ulong)desde, (ulong)hasta);
   // Los ticks deben llegar hasta casi "ahora" (después de las 10:06 NY). Si no, se reintenta; tras 10 intentos se
   // registra igual, marcada "ticksIncompletos" (el contraste no la cuenta) (revisión de Codex, ronda 2).
   bool completos = n > 0 && (long)tk[n - 1].time_msc >= hasta - 120000;
   if(!completos && gIntentosTicks < 10) { gIntentosTicks++; Print("CalibracionC: ticks incompletos (", n, "); se reintenta"); return false; }
   string csv = "\"Exness\",\"Symbol\",\"Timestamp\",\"Bid\",\"Ask\"\n";
   for(int i = 0; i < n; i++) {
      string f = TimeToString((datetime)(tk[i].time_msc / 1000), TIME_DATE); StringReplace(f, ".", "-");
      string h = TimeToString((datetime)(tk[i].time_msc / 1000), TIME_SECONDS);
      csv += "\"exness\",\"XAUUSDm\",\"" + f + " " + h + "." + StringFormat("%03d", (int)(tk[i].time_msc % 1000)) + "Z\"," + N(tk[i].bid) + "," + N(tk[i].ask) + "\n";
   }
   if(!Escribir(gFecha + "_ticks.csv", csv)) return false;
   // La entrada de hoy ya esta en el historial: Hechas() la incluye. Si hoy es invalida (reinicio o ticks incompletos) se resta.
   // Si no se pudo contar, numero = -1 (sin respaldo en CalibC_n: en la nube vale 0 siempre).
   int hechasReg = Hechas();
   int nOps = -1;
   if(hechasReg >= 0) { nOps = hechasReg - ((gReinicio || !completos) ? 1 : 0); if(nOps < 0) nOps = 0; }
   // desfase de la hora del servidor contra UTC (los ticks se exportan con la hora del servidor; Exness usa UTC)
   long desfase = (long)(TimeTradeServer() - TimeGMT());
   string j = "{\n \"fecha\": " + Q(gFecha) + ", \"numero\": " + IntegerToString(nOps) + ", \"cuenta\": \"demo\", \"lote\": " + N(LOTE, 2) + ", \"stopUSD\": " + N(STOP_USD, 1) +
              ", \"reinicio\": " + (gReinicio ? "true" : "false") + ", \"ticksIncompletos\": " + (completos ? "false" : "true") +
              ", \"desfaseServidorSeg\": " + IntegerToString(desfase) + ",\n";
   j += " \"apertura\": {\"tickMs\": " + IntegerToString(gTickEnt.time_msc) + ", \"bid\": " + N(gTickEnt.bid) + ", \"ask\": " + N(gTickEnt.ask) + ", \"spread\": " + N(gTickEnt.ask - gTickEnt.bid) +
        ", \"precioPedido\": " + N(gPedidoEnt) + ", \"precioEjecutado\": " + N(pEnt) + ", \"dealMs\": " + IntegerToString(msEnt) + ", \"latenciaMs\": " + N(gLatEnt, 1) + ", \"retcode\": " + IntegerToString(gRetEnt) + "},\n";
   j += " \"cierre\": {\"motivo\": " + Q(mot) + ", \"tickMs\": " + IntegerToString(gTickSal.time_msc) + ", \"precioPedido\": " + N(gPedidoSal) + ", \"precioEjecutado\": " + N(pSal) +
        ", \"dealMs\": " + IntegerToString(msSal) + ", \"latenciaMs\": " + N(gLatSal, 1) + ", \"retcode\": " + IntegerToString(gRetSal) + "},\n";
   j += " \"comision\": " + N(com, 2) + ", \"swap\": " + N(swp, 2) + ", \"beneficio\": " + N(ben, 2) + ", \"resultado\": " + N(ben + com + swp, 2) +
        ", \"saldoAntes\": " + N(gSaldo0, 2) + ", \"ticksExportados\": " + IntegerToString(n) + "\n}\n";
   if(!Escribir(gFecha + ".json", j)) return false;
   if(nOps >= 0) GlobalVariableSet("CalibC_n", nOps); // sólo si se pudo contar y quedó escrita (revisión de Codex)
   gReinicio = false; gIntentosTicks = 0;
   Print("CalibracionC: operación ", nOps, " de ", MAX_OPS, " registrada: ", N(ben + com + swp, 2), " USD");
   return true;
}
