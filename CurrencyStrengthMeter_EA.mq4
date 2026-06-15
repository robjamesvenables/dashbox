//+------------------------------------------------------------------+
//|  CurrencyStrengthMeter_EA.mq4                                    |
//|  Posts W/D/H4 scores + prices + auto pivot levels to JSONbin    |
//|  Place in MQL4/Experts/ folder                                   |
//+------------------------------------------------------------------+
#property copyright "Dashbox Trade"
#property version   "6.00"
#property strict

extern string JsonbinApiKey     = "$2a$10$d0.NsjXsDQakZVLZnl4Lcuv1yl9POT37dx2yf4GzHZOWZxYk/JAya";
extern string JsonbinBinId      = "6a2f6bf4f5f4af5e29f2bdc9";
extern int    PostIntervalSecs  = 60;
extern int    MAPeriod          = 14;
extern int    ATRPeriod         = 14;
extern int    PivotLookback     = 100;   // Daily candles to scan for pivots
extern int    PivotStrength     = 3;     // Candles each side for swing detection
extern double PivotMergePct     = 0.003; // Merge levels within 0.3% of each other
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
   "AUDNZD","AUDCAD","AUDCHF","NZDCAD","NZDCHF","CADCHF"
};

datetime LastPostTime=0;

//+------------------------------------------------------------------+
int OnInit(){ Print("EA v6.00 started — W/D/H4 + auto pivots."); PostAll(); return INIT_SUCCEEDED; }
void OnTick(){ if(TimeCurrent()-LastPostTime>=PostIntervalSecs){ PostAll(); LastPostTime=TimeCurrent(); } }
void OnTimer(){ OnTick(); }

//+------------------------------------------------------------------+
double CalcScore(string &pairs[],int &dirs[],int count,int period)
{
   double total=0; int valid=0;
   for(int i=0;i<count;i++){
      double c=iClose(pairs[i],period,1);
      double ma=iMA(pairs[i],period,MAPeriod,0,MODE_EMA,PRICE_CLOSE,1);
      double atr=iATR(pairs[i],period,ATRPeriod,1);
      if(ma==0||atr==0) continue;
      total+=MathMax(MathMin((c-ma)/atr,3.0),-3.0)*dirs[i];
      valid++;
   }
   return valid>0?total/valid:0;
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

//+------------------------------------------------------------------+
// Count how many times price has touched a level within tolerance
int CountTouches(string sym, double level, double tolerance, int lookback)
{
   int touches=0;
   bool inZone=false;
   for(int i=1;i<=lookback;i++){
      double hi=iHigh(sym,PERIOD_D1,i);
      double lo=iLow(sym,PERIOD_D1,i);
      bool near=(MathAbs(hi-level)<=tolerance||MathAbs(lo-level)<=tolerance||
                 (lo<=level+tolerance&&hi>=level-tolerance));
      if(near&&!inZone){ touches++; inZone=true; }
      else if(!near) inZone=false;
   }
   return touches;
}

// Detect pivot levels for one pair, returns JSON array string
string DetectPivots(string sym)
{
   int digits=(int)MarketInfo(sym,MODE_DIGITS);
   double point=MarketInfo(sym,MODE_POINT);
   double bid=MarketInfo(sym,MODE_BID);
   if(bid==0) return "[]";

   // Tolerance for touch counting: 0.15% of price or 15 pips
   double tolerance=MathMax(bid*0.0015, 15*point*10);

   // Store found levels: [level, type(1=res,-1=sup), touches]
   double levels[];
   int    types[];
   int    touchCounts[];
   int    found=0;

   ArrayResize(levels,50);
   ArrayResize(types,50);
   ArrayResize(touchCounts,50);

   int S=PivotStrength;

   for(int i=S+1;i<PivotLookback-S&&found<40;i++)
   {
      double hi=iHigh(sym,PERIOD_D1,i);
      double lo=iLow(sym,PERIOD_D1,i);

      // Check swing high (resistance)
      bool isSwingHigh=true;
      for(int j=1;j<=S;j++){
         if(iHigh(sym,PERIOD_D1,i-j)>=hi||iHigh(sym,PERIOD_D1,i+j)>=hi){ isSwingHigh=false; break; }
      }

      // Check swing low (support)
      bool isSwingLow=true;
      for(int j=1;j<=S;j++){
         if(iLow(sym,PERIOD_D1,i-j)<=lo||iLow(sym,PERIOD_D1,i+j)<=lo){ isSwingLow=false; break; }
      }

      if(isSwingHigh){
         // Check not too close to existing level
         bool duplicate=false;
         for(int k=0;k<found;k++){
            if(MathAbs(levels[k]-hi)/hi<PivotMergePct){ duplicate=true; break; }
         }
         if(!duplicate){
            int tc=CountTouches(sym,hi,tolerance,PivotLookback);
            if(tc>=2){ // only keep confirmed levels
               levels[found]=hi; types[found]=1; touchCounts[found]=tc;
               found++;
            }
         }
      }

      if(isSwingLow){
         bool duplicate=false;
         for(int k=0;k<found;k++){
            if(MathAbs(levels[k]-lo)/lo<PivotMergePct){ duplicate=true; break; }
         }
         if(!duplicate){
            int tc=CountTouches(sym,lo,tolerance,PivotLookback);
            if(tc>=2){
               levels[found]=lo; types[found]=-1; touchCounts[found]=tc;
               found++;
            }
         }
      }
   }

   if(found==0) return "[]";

   // Build JSON array — only levels within 200 pips of current price
   string arr="[";
   bool first=true;
   double maxDist=200*point*10;
   // For JPY pairs, 200 pips = 2.0
   if(digits==3||digits==2) maxDist=2.0;

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

//+------------------------------------------------------------------+
void PostAll()
{
   string json="{";
   json+="\"ts\":"+IntegerToString(TimeCurrent())+",";

   // Strength scores — W, D, H4
   json+=BuildScoreBlock("scores_W",PERIOD_W1)+",";
   json+=BuildScoreBlock("scores_D",PERIOD_D1)+",";
   json+=BuildScoreBlock("scores_H4",PERIOD_H4)+",";
   json+=BuildScoreBlock("scores",PERIOD_H4)+",";  // backward compat

   // Live prices
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

   // Auto pivot levels for all pairs
   json+="\"pivots\":{";
   bool firstPiv=true;
   for(int i=0;i<total;i++){
      string pivJson=DetectPivots(ALL_PAIRS[i]);
      if(pivJson=="[]") continue;
      if(!firstPiv) json+=",";
      json+="\""+ALL_PAIRS[i]+"\":"+pivJson;
      firstPiv=false;
   }
   json+="}}";

   if(EnableLogging) Print("JSON length: ",StringLen(json));
   PostToJsonbin(json);
}

//+------------------------------------------------------------------+
void PostToJsonbin(string json)
{
   string url="https://api.jsonbin.io/v3/b/"+JsonbinBinId;
   string headers="Content-Type: application/json\r\nX-Master-Key: "+JsonbinApiKey+"\r\n";
   char postData[]; char result[]; string resultHeaders;
   StringToCharArray(json,postData,0,StringLen(json));
   int res=WebRequest("PUT",url,headers,10000,postData,result,resultHeaders);
   if(res==-1) Print("Jsonbin error: ",GetLastError());
   else if(EnableLogging) Print("Jsonbin OK. HTTP ",res, " JSON size: ",StringLen(json));
}
