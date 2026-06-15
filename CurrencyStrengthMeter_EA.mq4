//+------------------------------------------------------------------+
//|  CurrencyStrengthMeter_EA.mq4                                    |
//|  Posts W/D/H4 scores + prices to JSONbin every 60s              |
//|  Place in MQL4/Experts/ folder                                   |
//+------------------------------------------------------------------+
#property copyright "Dashbox Trade"
#property version   "5.00"
#property strict

extern string JsonbinApiKey     = "$2a$10$d0.NsjXsDQakZVLZnl4Lcuv1yl9POT37dx2yf4GzHZOWZxYk/JAya";
extern string JsonbinBinId      = "6a2f6bf4f5f4af5e29f2bdc9";
extern int    PostIntervalSecs  = 60;
extern int    MAPeriod          = 14;
extern int    ATRPeriod         = 14;
extern bool   EnableLogging     = false;

string DXY_Pairs[] = {"EURUSD","GBPUSD","USDJPY","USDCHF","USDCAD","AUDUSD"};
string EXY_Pairs[] = {"EURUSD","EURGBP","EURJPY","EURCHF","EURCAD","EURAUD","EURNZD"};
string BXY_Pairs[] = {"GBPUSD","EURGBP","GBPJPY","GBPCHF","GBPCAD","GBPAUD","GBPNZD"};
string AXY_Pairs[] = {"AUDUSD","EURAUD","GBPAUD","AUDJPY","AUDCHF","AUDCAD","AUDNZD"};
string NXY_Pairs[] = {"NZDUSD","EURNZD","GBPNZD","NZDJPY","NZDCHF","NZDCAD","AUDNZD"};
string CAD_Pairs[] = {"USDCAD","EURCAD","GBPCAD","CADJPY","CADCHF","AUDCAD","NZDCAD"};
string CHF_Pairs[] = {"USDCHF","EURCHF","GBPCHF","CHFJPY","AUDCHF","CADCHF","NZDCHF"};
string JXY_Pairs[] = {"USDJPY","EURJPY","GBPJPY","AUDJPY","CADJPY","CHFJPY","NZDJPY"};

int DXY_Dir[]  = {-1,-1,+1,+1,+1,-1};
int EXY_Dir[]  = {+1,+1,+1,+1,+1,+1,+1};
int BXY_Dir[]  = {+1,-1,+1,+1,+1,+1,+1};
int AXY_Dir[]  = {+1,-1,-1,+1,+1,+1,+1};
int NXY_Dir[]  = {+1,-1,-1,+1,+1,+1,-1};
int CAD_Dir[]  = {-1,-1,-1,+1,+1,+1,+1};
int CHF_Dir[]  = {-1,-1,-1,-1,+1,+1,+1};
int JXY_Dir[]  = {-1,-1,-1,-1,-1,-1,-1};

string ScoreNames[] = {"DXY","EXY","BXY","AXY","NXY","CAD","CHF","JXY"};

string ALL_PAIRS[] = {
   "EURUSD","GBPUSD","AUDUSD","NZDUSD","USDCAD","USDCHF","USDJPY",
   "EURJPY","GBPJPY","AUDJPY","NZDJPY","CADJPY","CHFJPY",
   "EURGBP","EURAUD","EURNZD","EURCAD","EURCHF",
   "GBPAUD","GBPNZD","GBPCAD","GBPCHF",
   "AUDNZD","AUDCAD","AUDCHF","NZDCAD","NZDCHF","CADCHF"
};

datetime LastPostTime = 0;

int OnInit(){ Print("EA v5.00 started."); PostAll(); return INIT_SUCCEEDED; }
void OnTick(){ if(TimeCurrent()-LastPostTime>=PostIntervalSecs){ PostAll(); LastPostTime=TimeCurrent(); } }
void OnTimer(){ OnTick(); }

double CalcScore(string &pairs[], int &dirs[], int count, int period)
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

string BuildScoreBlock(string label, int period)
{
   int counts[8]={6,7,7,7,7,7,7,7};
   string block="\""+label+"\":{";
   for(int i=0;i<8;i++){
      double s=0;
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
   block+="}";
   return block;
}

void PostAll()
{
   string json="{";
   json+="\"ts\":"+IntegerToString(TimeCurrent())+",";
   // Three timeframes
   json+=BuildScoreBlock("scores_W",PERIOD_W1)+",";
   json+=BuildScoreBlock("scores_D",PERIOD_D1)+",";
   json+=BuildScoreBlock("scores_H4",PERIOD_H4)+",";
   // Also keep "scores" as H4 for backward compat
   json+=BuildScoreBlock("scores",PERIOD_H4)+",";
   // Prices
   json+="\"prices\":{";
   int total=ArraySize(ALL_PAIRS); bool first=true;
   for(int i=0;i<total;i++){
      double bid=MarketInfo(ALL_PAIRS[i],MODE_BID);
      int digits=(int)MarketInfo(ALL_PAIRS[i],MODE_DIGITS);
      if(bid==0) continue;
      if(!first) json+=",";
      json+="\""+ALL_PAIRS[i]+"\":"+DoubleToStr(bid,digits);
      first=false;
   }
   json+="}}";

   if(EnableLogging) Print("JSON: ",StringSubstr(json,0,200));
   PostToJsonbin(json);
}

void PostToJsonbin(string json)
{
   string url="https://api.jsonbin.io/v3/b/"+JsonbinBinId;
   string headers="Content-Type: application/json\r\nX-Master-Key: "+JsonbinApiKey+"\r\n";
   char postData[]; char result[]; string resultHeaders;
   StringToCharArray(json,postData,0,StringLen(json));
   int res=WebRequest("PUT",url,headers,5000,postData,result,resultHeaders);
   if(res==-1) Print("Jsonbin error: ",GetLastError());
   else if(EnableLogging) Print("Jsonbin OK. HTTP ",res);
}
