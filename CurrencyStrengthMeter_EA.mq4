//+------------------------------------------------------------------+
//|  CurrencyStrengthMeter_EA.mq4                                    |
//|  Posts scores + prices to JSONbin every 60s                      |
//|  Place in MQL4/Experts/ folder                                   |
//+------------------------------------------------------------------+
#property copyright "Dashbox Trade"
#property version   "4.00"
#property strict

//--- Inputs
extern string JsonbinApiKey     = "$2a$10$Ac9QwenauyC33dSBuR863OVTtKBL3NTZYR5DCg.SjFoRnzkKbWQG.";
extern string JsonbinBinId      = "6a2f6bf4f5f4af5e29f2bdc9";
extern string TelegramBotToken  = "8500092691:AAHX_wIqo2p9qXOTe0RL-etw_41R1Q2bZXQ";
extern string TelegramChatID    = "8361135939";
extern int    PostIntervalSecs  = 60;
extern int    MAPeriod          = 14;
extern int    ATRPeriod         = 14;
extern bool   EnableLogging     = false;

//--- Currency pairs for each index
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

//+------------------------------------------------------------------+
int OnInit()
{
   Print("CurrencyStrengthMeter EA v4.00 started.");
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
double CalcIndexScore(string &pairs[], int &dirs[], int count)
{
   double totalScore = 0;
   int    validCount = 0;
   for(int i = 0; i < count; i++)
   {
      double close = iClose(pairs[i], PERIOD_H4, 1);
      double ma    = iMA(pairs[i], PERIOD_H4, MAPeriod, 0, MODE_EMA, PRICE_CLOSE, 1);
      double atr   = iATR(pairs[i], PERIOD_H4, ATRPeriod, 1);
      if(ma == 0 || atr == 0) continue;
      double raw = MathMax(MathMin((close - ma) / atr, 3.0), -3.0);
      totalScore += raw * dirs[i];
      validCount++;
   }
   if(validCount == 0) return 0;
   return totalScore / validCount;
}

//+------------------------------------------------------------------+
void PostAll()
{
   // Calculate scores
   double scores[8];
   int pairCounts[8] = {6,7,7,7,7,7,7,7};
   scores[0] = CalcIndexScore(DXY_Pairs, DXY_Dir, pairCounts[0]);
   scores[1] = CalcIndexScore(EXY_Pairs, EXY_Dir, pairCounts[1]);
   scores[2] = CalcIndexScore(BXY_Pairs, BXY_Dir, pairCounts[2]);
   scores[3] = CalcIndexScore(AXY_Pairs, AXY_Dir, pairCounts[3]);
   scores[4] = CalcIndexScore(NXY_Pairs, NXY_Dir, pairCounts[4]);
   scores[5] = CalcIndexScore(CAD_Pairs, CAD_Dir, pairCounts[5]);
   scores[6] = CalcIndexScore(CHF_Pairs, CHF_Dir, pairCounts[6]);
   scores[7] = CalcIndexScore(JXY_Pairs, JXY_Dir, pairCounts[7]);

   // Build JSON
   string json = "{";
   json += "\"ts\":" + IntegerToString(TimeCurrent()) + ",";
   json += "\"scores\":{";
   for(int i = 0; i < 8; i++)
   {
      json += "\"" + ScoreNames[i] + "\":" + DoubleToStr(scores[i], 4);
      if(i < 7) json += ",";
   }
   json += "},\"prices\":{";
   int total = ArraySize(ALL_PAIRS);
   bool first = true;
   for(int i = 0; i < total; i++)
   {
      double bid = MarketInfo(ALL_PAIRS[i], MODE_BID);
      int digits = (int)MarketInfo(ALL_PAIRS[i], MODE_DIGITS);
      if(bid == 0) continue;
      if(!first) json += ",";
      json += "\"" + ALL_PAIRS[i] + "\":" + DoubleToStr(bid, digits);
      first = false;
   }
   json += "}}";

   if(EnableLogging) Print("JSON: ", json);

   PostToJsonbin(json);
}

//+------------------------------------------------------------------+
void PostToJsonbin(string json)
{
   string url     = "https://api.jsonbin.io/v3/b/" + JsonbinBinId;
   string headers = "Content-Type: application/json\r\nX-Master-Key: " + JsonbinApiKey + "\r\n";

   char   postData[];
   char   result[];
   string resultHeaders;

   StringToCharArray(json, postData, 0, StringLen(json));

   int res = WebRequest("PUT", url, headers, 5000, postData, result, resultHeaders);

   if(res == -1)
      Print("Jsonbin error: ", GetLastError(), " — add https://api.jsonbin.io to MT4 WebRequest list");
   else if(EnableLogging)
      Print("Jsonbin OK. HTTP ", res);
}
//+------------------------------------------------------------------+
