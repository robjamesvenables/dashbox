//+------------------------------------------------------------------+
//|  CurrencyStrengthMeter_EA.mq4                                    |
//|  v7.00 — W/D/H4 scores + pivots + HA cross alerts               |
//|  Place in MQL4/Experts/ folder                                   |
//+------------------------------------------------------------------+
#property copyright "Dashbox Trade"
#property version   "7.00"
#property strict

extern string TelegramBotToken  = "8500092691:AAHX_wIqo2p9qXOTe0RL-etw_41R1Q2bZXQ";
extern string TelegramChatID    = "8361135939";
extern string JsonbinApiKey     = "$2a$10$d0.NsjXsDQakZVLZnl4Lcuv1yl9POT37dx2yf4GzHZOWZxYk/JAya";
extern string JsonbinBinId      = "6a2f6bf4f5f4af5e29f2bdc9";
extern int    PostIntervalSecs  = 60;
extern int    MAPeriod          = 14;
extern int    ATRPeriod         = 14;
extern int    PivotLookback     = 60;
extern int    PivotStrength     = 2;
extern double PivotMergePct     = 0.003;
extern double PivotThresholdPct = 0.005; // 0.5% of price = near level
extern int    HA_EMA_Period     = 21;    // EMA period for HA cross
extern bool   EnableLogging     = false;

//--- Index pairs
string DXY_Pairs[] = {"EURUSD","GBPUSD","USDJPY","USDCHF","USDCAD","AUDUSD"};
string EXY_Pairs[] = {"EURUSD","EURGBP","EURJPY","EURCHF","EURCAD","EURAUD","EURNZD"};
string BXY_Pairs[] = {"GBPUSD","EURGBP","GBPJPY","GBPCHF","GBPCAD","GBPAUD","GBPNZD"};
string AXY_Pairs[] = {"AUDUSD","EURAUD","GBPAUD","AUDJPY","AUDCHF","AUDCAD","AUDNZD"};
string NXY_Pairs[] = {"NZDUSD","EURNZD","GBPNZD","NZDJPY","NZDCHF","NZDCAD","AUDNZD"};
string CAD_Pairs[] = {"USDCAD","EURCAD","GBPCAD","CADJPY","CADCHF","AUDCAD","NZDCAD"};
string CHF_Pairs[] = {"USDCHF","EURCHF","GBPCHF","CHFJPY","AUDCHF","CADCHF","NZDCHF"};
string JXY_Pairs[] = {"USDJPY","EURJPY","GBPJPY","AUDJPY","CADJPY","CHFJPY","NZDJPY"};

int DXY_Dir[]={-1,-1,+1,+1,+1,-1};
int EXY_Dir[]={+1,+1,+1,+1,+1,+1,+1};
int BXY_Dir[]={+1,-1,+1,+1,+1,+1,+1};
int AXY_Dir[]={+1,-1,-1,+1,+1,+1,+1};
int NXY_Dir[]={+1,-1,-1,+1,+1,+1,-1};
int CAD_Dir[]={-1,-1,-1,+1,+1,+1,+1};
int CHF_Dir[]={-1,-1,-1,-1,+1,+1,+1};
int JXY_Dir[]={-1,-1,-1,-1,-1,-1,-1};
string ScoreNames[]={"DXY","EXY","BXY","AXY","NXY","CAD","CHF","JXY"};

string ALL_PAIRS[]={
   "EURUSD","GBPUSD","AUDUSD","NZDUSD","USDCAD","USDCHF","USDJPY",
   "EURJPY","GBPJPY","AUDJPY","NZDJPY","CADJPY","CHFJPY",
   "EURGBP","EURAUD","EURNZD","EURCAD","EURCHF",
   "GBPAUD","GBPNZD","GBPCAD","GBPCHF",
   "AUDNZD","AUDCAD","AUDCHF","NZDCAD","NZDCHF","CADCHF",
   "XAUUSD","NDX100","US30","BTCUSD"
};

string EXTRA_INSTRUMENTS[] = {"XAUUSD","NDX100","US30","BTCUSD"};
string EXTRA_NAMES[]       = {"Gold","Nasdaq","Dow Jones","Bitcoin"};

datetime LastPostTime   = 0;
datetime LastAlertTimes[]; // tracks last alert time per pair to avoid spam

//+------------------------------------------------------------------+
int OnInit()
{
   int total = ArraySize(ALL_PAIRS);
   ArrayResize(LastAlertTimes, total);
   ArrayInitialize(LastAlertTimes, 0);
   Print("Dashbox EA v7.00 started.");
   PostAll();
   return INIT_SUCCEEDED;
}

void OnTick()
{
   if(TimeCurrent() - LastPostTime >= PostIntervalSecs)
   {
      PostAll();
      LastPostTime = TimeCurrent();
   }
}

void OnTimer() { OnTick(); }

//+------------------------------------------------------------------+
// HEIKEN ASHI CALCULATION
//+------------------------------------------------------------------+
double HA_Close(string sym, int tf, int shift)
{
   return (iOpen(sym,tf,shift)+iHigh(sym,tf,shift)+iLow(sym,tf,shift)+iClose(sym,tf,shift))/4.0;
}

double HA_Open(string sym, int tf, int shift)
{
   // HA Open = (prev HA Open + prev HA Close) / 2
   // For simplicity use 3-bar average of open/close
   if(shift >= iBars(sym,tf)-2) return iOpen(sym,tf,shift);
   double prevClose = HA_Close(sym,tf,shift+1);
   double prevOpen  = (iOpen(sym,tf,shift+1) + iClose(sym,tf,shift+1)) / 2.0;
   return (prevOpen + prevClose) / 2.0;
}

// Returns +1 if HA just crossed bullish over EMA, -1 if bearish, 0 if no cross
int DetectHACross(string sym)
{
   // Need at least 3 closed H4 bars
   if(iBars(sym, PERIOD_H4) < 5) return 0;

   // Current closed bar = shift 1, previous = shift 2
   double haClose1 = HA_Close(sym, PERIOD_H4, 1);
   double haOpen1  = HA_Open(sym,  PERIOD_H4, 1);
   double haClose2 = HA_Close(sym, PERIOD_H4, 2);
   double haOpen2  = HA_Open(sym,  PERIOD_H4, 2);

   // EMA on H4 close as proxy for HA EMA
   double emaH4_1 = iMA(sym, PERIOD_H4, HA_EMA_Period, 0, MODE_EMA, PRICE_CLOSE, 1);
   double emaH4_2 = iMA(sym, PERIOD_H4, HA_EMA_Period, 0, MODE_EMA, PRICE_CLOSE, 2);

   bool bullNow  = (haClose1 > haOpen1); // current HA candle is bullish
   bool bullPrev = (haClose2 > haOpen2); // previous HA candle was bearish
   bool crossedAboveEMA = (haClose1 > emaH4_1) && (haClose2 <= emaH4_2);
   bool crossedBelowEMA = (haClose1 < emaH4_1) && (haClose2 >= emaH4_2);

   // Bullish cross: HA turned green AND closed above EMA
   if(bullNow && !bullPrev && crossedAboveEMA) return +1;

   // Bearish cross: HA turned red AND closed below EMA
   if(!bullNow && bullPrev && crossedBelowEMA) return -1;

   return 0;
}

//+------------------------------------------------------------------+
// CHECK IF PAIR IS NEAR A PIVOT LEVEL
//+------------------------------------------------------------------+
bool IsNearPivot(string sym, int &outTouches, string &outType)
{
   double bid = MarketInfo(sym, MODE_BID);
   if(bid == 0) return false;
   double threshold = bid * PivotThresholdPct;

   // Scan recent daily swing levels
   int S = PivotStrength;
   for(int i = S+1; i < PivotLookback-S; i++)
   {
      double hi  = iHigh(sym, PERIOD_D1, i);
      double lo  = iLow(sym,  PERIOD_D1, i);

      // Check swing high (resistance)
      bool isSwingHigh = true;
      for(int j=1;j<=S;j++){
         if(iHigh(sym,PERIOD_D1,i-j)>=hi||iHigh(sym,PERIOD_D1,i+j)>=hi){isSwingHigh=false;break;}
      }
      if(isSwingHigh && MathAbs(bid-hi) <= threshold){
         // Count touches
         int touches = CountTouches(sym, hi, threshold);
         if(touches >= 2){ outTouches=touches; outType="resistance"; return true; }
      }

      // Check swing low (support)
      bool isSwingLow = true;
      for(int j=1;j<=S;j++){
         if(iLow(sym,PERIOD_D1,i-j)<=lo||iLow(sym,PERIOD_D1,i+j)<=lo){isSwingLow=false;break;}
      }
      if(isSwingLow && MathAbs(bid-lo) <= threshold){
         int touches = CountTouches(sym, lo, threshold);
         if(touches >= 2){ outTouches=touches; outType="support"; return true; }
      }
   }
   return false;
}

int CountTouches(string sym, double level, double tolerance)
{
   // ATR rejection filter — price must move away by 1x ATR after touching level
   double atr = iATR(sym, PERIOD_D1, 14, 1);
   if(atr == 0) atr = tolerance; // fallback

   int touches = 0;
   bool inZone = false;
   int lastTouchBar = -1;

   for(int i=PivotLookback; i>=1; i--) // scan oldest to newest
   {
      double hi = iHigh(sym, PERIOD_D1, i);
      double lo = iLow(sym,  PERIOD_D1, i);
      bool near = (MathAbs(hi-level)<=tolerance || MathAbs(lo-level)<=tolerance ||
                   (lo<=level+tolerance && hi>=level-tolerance));

      if(near && !inZone)
      {
         // Check if price moved away by at least 1 ATR after this touch
         // Look forward (lower bar index = more recent)
         bool rejected = false;
         for(int j = i-1; j >= MathMax(1, i-5); j--)
         {
            double futureHi = iHigh(sym, PERIOD_D1, j);
            double futureLo = iLow(sym,  PERIOD_D1, j);
            // For resistance: price should move down by 1 ATR
            if(level > lo && futureLo < level - atr) { rejected = true; break; }
            // For support: price should move up by 1 ATR
            if(level < hi && futureHi > level + atr) { rejected = true; break; }
         }
         if(rejected) touches++;
         inZone = true;
      }
      else if(!near) inZone = false;
   }
   return touches;
}

//+------------------------------------------------------------------+
// CHECK W AND D STRENGTH AGREEMENT
//+------------------------------------------------------------------+
// Returns +1 if W and D both bullish for base vs quote, -1 bearish, 0 no agreement
int StrengthAgreement(string sym)
{
   // Get W and D scores for base and quote currency
   string base  = StringSubstr(sym,0,3);
   string quote = StringSubstr(sym,3,3);

   // Calculate simple W and D momentum for each currency
   // Using EMA distance on EURUSD as proxy for EUR strength etc
   // For now use direct pair W and D direction
   double closeW = iClose(sym, PERIOD_W1, 1);
   double openW  = iOpen(sym,  PERIOD_W1, 1);
   double closeD = iClose(sym, PERIOD_D1, 1);
   double openD  = iOpen(sym,  PERIOD_D1, 1);

   bool wBull = (closeW > openW);
   bool dBull = (closeD > openD);

   if(wBull && dBull)  return +1; // Both Weekly and Daily bullish
   if(!wBull && !dBull) return -1; // Both Weekly and Daily bearish
   return 0; // Mixed — no clear agreement
}

//+------------------------------------------------------------------+
// MAIN ALERT CHECK — runs every 60s
//+------------------------------------------------------------------+
void CheckHACrossAlerts()
{
   int total = ArraySize(ALL_PAIRS);
   for(int i=0; i<total; i++)
   {
      string sym = ALL_PAIRS[i];
      double bid = MarketInfo(sym, MODE_BID);
      if(bid == 0) continue;

      // Avoid spam — only alert once per 4 hours per pair
      if(TimeCurrent() - LastAlertTimes[i] < 14400) continue;

      // Step 1: Is pair near a key daily pivot level?
      int    pivotTouches = 0;
      string pivotType    = "";
      if(!IsNearPivot(sym, pivotTouches, pivotType)) continue;

      // Step 2: Does H4 Heiken Ashi cross confirm?
      int haCross = DetectHACross(sym);
      if(haCross == 0) continue;

      // Step 3: Does W and D agree with the cross direction?
      int wdAgree = StrengthAgreement(sym);

      // Determine trade direction
      string direction = "";
      if(haCross == +1 && pivotType == "support")    direction = "BUY";
      if(haCross == -1 && pivotType == "resistance") direction = "SELL";
      if(direction == "") continue; // cross doesn't match pivot type

      // W/D agreement bonus (not a blocker but affects conviction)
      int wdConfirms = 0;
      if(direction == "BUY"  && wdAgree == +1) wdConfirms = 1;
      if(direction == "SELL" && wdAgree == -1) wdConfirms = 1;

      // Calculate 1:1 levels
      int    digits   = (int)MarketInfo(sym, MODE_DIGITS);
      double point    = MarketInfo(sym, MODE_POINT);
      int    dg       = (int)MarketInfo(sym, MODE_DIGITS);
      double slDist;
      if(dg<=2)      slDist = 1.20;    // JPY — 120 pips
      else if(bid>1000) slDist = bid*0.008; // Gold/indices — 0.8%
      else           slDist = 0.0100;  // Standard forex — 100 pips
      double entry    = bid;
      double sl       = direction=="BUY" ? entry-slDist : entry+slDist;
      double tp       = direction=="BUY" ? entry+slDist : entry-slDist; // 1:1

      string pivotRank = pivotTouches>=4?"FORTRESS":pivotTouches==3?"STRONG":"VALID";
      string wdNote   = wdConfirms==1?"✅ W+D agree":"⚠ W/D mixed — H4 only";

      // Build Telegram message
      string msg = "⚡ <b>DASHBOX ALERT</b>\n\n";
      msg += "<b>" + sym + "</b> " + direction + "\n";
      msg += "📍 " + pivotRank + " " + pivotType + " (" + IntegerToString(pivotTouches) + " touches)\n";
      msg += "🕯 H4 Heiken Ashi cross confirmed\n";
      msg += wdNote + "\n\n";
      msg += "Entry: " + DoubleToStr(entry, digits) + "\n";
      msg += "SL:    " + DoubleToStr(sl, digits) + "\n";
      msg += "TP:    " + DoubleToStr(tp, digits) + " (1:1)\n\n";
      msg += "⚠️ Confirm on chart before entering.";

      SendTelegram(msg);
      LastAlertTimes[i] = TimeCurrent();

      if(EnableLogging) Print("Alert sent: ", sym, " ", direction);
   }
}

//+------------------------------------------------------------------+
double CalcScore(string &pairs[],int &dirs[],int count,int period)
{
   // Use percentage change over 5 bars — more accurate than EMA/ATR
   double total=0; int valid=0;
   int lookback=5; // 5 bars = 1 week on W, 1 week on D, 20hrs on H4
   for(int i=0;i<count;i++){
      double cNow  = iClose(pairs[i],period,1);
      double cPrev = iClose(pairs[i],period,lookback+1);
      if(cNow==0||cPrev==0) continue;
      double pctChange = ((cNow-cPrev)/cPrev)*100.0; // % change
      total += MathMax(MathMin(pctChange,3.0),-3.0)*dirs[i];
      valid++;
   }
   return valid>0?NormalizeDouble(total/valid*10,2):0; // scale to readable range
}

string BuildScoreBlock(string label,int period)
{
   int counts[8]={6,7,7,7,7,7,7,7};
   string block="\""+label+"\":{";
   double s=0;
   for(int i=0;i<8;i++){
      if(i==0) s=CalcScore(DXY_Pairs,DXY_Dir,counts[0],period);
      if(i==1) s=CalcScore(EXY_Pairs,EXY_Dir,counts[1],period);
      if(i==2) s=CalcScore(BXY_Pairs,BXY_Dir,counts[2],period);
      if(i==3) s=CalcScore(AXY_Pairs,AXY_Dir,counts[3],period);
      if(i==4) s=CalcScore(NXY_Pairs,NXY_Dir,counts[4],period);
      if(i==5) s=CalcScore(CAD_Pairs,CAD_Dir,counts[5],period);
      if(i==6) s=CalcScore(CHF_Pairs,CHF_Dir,counts[6],period);
      if(i==7) s=CalcScore(JXY_Pairs,JXY_Dir,counts[7],period);
      block+="\""+ScoreNames[i]+"\":"+DoubleToStr(s,4);
      if(i<7) block+=",";
   }
   return block+"}";
}

double CalcMomentum(string sym)
{
   double total=0; int valid=0;
   int periods[3]={PERIOD_W1,PERIOD_D1,PERIOD_H4};
   for(int i=0;i<3;i++){
      double c=iClose(sym,periods[i],1);
      double ma=iMA(sym,periods[i],MAPeriod,0,MODE_EMA,PRICE_CLOSE,1);
      double atr=iATR(sym,periods[i],ATRPeriod,1);
      if(ma==0||atr==0) continue;
      total+=MathMax(MathMin((c-ma)/atr,3.0),-3.0);
      valid++;
   }
   return valid>0?total/valid:0;
}

int CountTouchesLocal(string sym, double level, double tolerance)
{
   return CountTouches(sym, level, tolerance);
}

string DetectPivots(string sym)
{
   int digits=(int)MarketInfo(sym,MODE_DIGITS);
   double point=MarketInfo(sym,MODE_POINT);
   double bid=MarketInfo(sym,MODE_BID);
   if(bid==0) return "[]";

   double tolerance;
   if(bid>1000)     tolerance=bid*0.005;
   else if(bid>100) tolerance=bid*0.003;
   else if(digits<=2) tolerance=bid*0.004;
   else             tolerance=bid*0.002;

   double levels[]; int types[]; int touchCounts[];
   int found=0;
   ArrayResize(levels,20); ArrayResize(types,20); ArrayResize(touchCounts,20);

   int S=PivotStrength;
   for(int i=S+1;i<PivotLookback-S&&found<15;i++)
   {
      double hi=iHigh(sym,PERIOD_D1,i);
      double lo=iLow(sym,PERIOD_D1,i);

      bool isSwingHigh=true;
      for(int j=1;j<=S;j++){
         if(iHigh(sym,PERIOD_D1,i-j)>=hi||iHigh(sym,PERIOD_D1,i+j)>=hi){isSwingHigh=false;break;}
      }
      bool isSwingLow=true;
      for(int j=1;j<=S;j++){
         if(iLow(sym,PERIOD_D1,i-j)<=lo||iLow(sym,PERIOD_D1,i+j)<=lo){isSwingLow=false;break;}
      }

      if(isSwingHigh){
         bool dup=false;
         for(int k=0;k<found;k++) if(MathAbs(levels[k]-hi)/hi<PivotMergePct){dup=true;break;}
         if(!dup){
            int tc=CountTouches(sym,hi,tolerance);
            if(tc>=2){levels[found]=hi;types[found]=1;touchCounts[found]=tc;found++;}
         }
      }
      if(isSwingLow){
         bool dup=false;
         for(int k=0;k<found;k++) if(MathAbs(levels[k]-lo)/lo<PivotMergePct){dup=true;break;}
         if(!dup){
            int tc=CountTouches(sym,lo,tolerance);
            if(tc>=2){levels[found]=lo;types[found]=-1;touchCounts[found]=tc;found++;}
         }
      }
   }

   if(found==0) return "[]";

   string arr="[";
   bool first=true;
   double maxDist;
   if(bid>50000)     maxDist=bid*0.05;
   else if(bid>30000) maxDist=bid*0.04;
   else if(bid>1000)  maxDist=bid*0.05;
   else if(bid>100)   maxDist=bid*0.03;
   else if(digits<=2) maxDist=3.0;
   else               maxDist=0.02;

   for(int i=0;i<found;i++){
      if(MathAbs(bid-levels[i])>maxDist) continue;
      if(!first) arr+=",";
      string t=types[i]==1?"resistance":"support";
      arr+="{\"l\":"+DoubleToStr(levels[i],digits)+",\"t\":\""+t+"\",\"c\":"+IntegerToString(touchCounts[i])+"}";
      first=false;
   }
   arr+="]";
   return arr;
}

void PostAll()
{
   string json="{";
   json+="\"ts\":"+IntegerToString(TimeCurrent())+",";
   json+=BuildScoreBlock("scores_W",PERIOD_W1)+",";
   json+=BuildScoreBlock("scores_D",PERIOD_D1)+",";
   json+=BuildScoreBlock("scores_H4",PERIOD_H4)+",";
   json+=BuildScoreBlock("scores",PERIOD_H4)+",";

   // Prices
   json+="\"prices\":{";
   int total=ArraySize(ALL_PAIRS); bool firstP=true;
   for(int i=0;i<total;i++){
      double bid=MarketInfo(ALL_PAIRS[i],MODE_BID);
      int dg=(int)MarketInfo(ALL_PAIRS[i],MODE_DIGITS);
      if(bid==0) continue;
      if(!firstP) json+=",";
      json+="\""+ALL_PAIRS[i]+"\":"+DoubleToStr(bid,dg);
      firstP=false;
   }
   json+="},";

   // Pivots
   json+="\"pivots\":{";
   bool firstPiv=true;
   for(int i=0;i<total;i++){
      string sym=ALL_PAIRS[i];
      string pivJson=DetectPivots(sym);
      double mom=CalcMomentum(sym);
      if(!firstPiv) json+=",";
      firstPiv=false;
      string momEntry="{\"l\":0,\"t\":\"mom\",\"c\":0,\"m\":"+DoubleToStr(mom,4)+"}";
      if(pivJson=="[]")
         json+="\""+sym+"\":["+momEntry+"]";
      else {
         string inner=StringSubstr(pivJson,1,StringLen(pivJson)-2);
         json+="\""+sym+"\":["+inner+","+momEntry+"]";
      }
   }
   json+="}}";

   if(EnableLogging) Print("JSON length: ",StringLen(json));

   if(StringLen(json)>90000){
      // Post without pivots first
      string quickJson=StringSubstr(json,0,StringFind(json,",\"pivots\""))+"}}";
      PostToJsonbin(quickJson);
   } else {
      PostToJsonbin(json);
   }
}

void PostToJsonbin(string json)
{
   string url="https://api.jsonbin.io/v3/b/"+JsonbinBinId;
   string headers="Content-Type: application/json\r\nX-Master-Key: "+JsonbinApiKey+"\r\n";
   char postData[]; char result[]; string resultHeaders;
   StringToCharArray(json,postData,0,StringLen(json));
   int res=WebRequest("PUT",url,headers,10000,postData,result,resultHeaders);
   if(res==-1) Print("Jsonbin error: ",GetLastError());
   else if(EnableLogging) Print("Jsonbin OK. HTTP ",res);
}

void SendTelegram(string text)
{
   string url="https://api.telegram.org/bot"+TelegramBotToken+"/sendMessage";
   string headers="Content-Type: application/x-www-form-urlencoded\r\n";
   string body="chat_id="+TelegramChatID+"&text="+text+"&parse_mode=HTML";
   char postData[]; char result[]; string resultHeaders;
   StringToCharArray(body,postData,0,StringLen(body));
   int res=WebRequest("POST",url,headers,5000,postData,result,resultHeaders);
   if(res==-1) Print("Telegram error: ",GetLastError());
   else if(EnableLogging) Print("Telegram OK");
}
