//+------------------------------------------------------------------+
//|              Gold_GridStop_DCA_v6.11.mq5                        |
//| Author: HoNgocKhanh                                              |
//| Based on: 07_SuperScalping_ v5.93                                |
//| Version: 6.11 - xem CHANGELOG ben duoi                           |
//+------------------------------------------------------------------+
//+------------------------------------------------------------------+
//| CHANGELOG (moi lan cap nhat deu nang version)                    |
//| v6.11 - sua loi dong BUILD (in "non-string passed")
//| v6.10 - gong lai theo ro (trailing % dinh), hedge + timeout, loc sideway ADX, thoat dao chieu CUT/FLIP, 2 MA, giam spam log
//| v6.00 - ban dau: DCA trong vung SL, SL/BE/rolling theo basket
//+------------------------------------------------------------------+
#property copyright "HoNgocKhanh"
#property version   "6.11"
#property strict
#include <Trade\Trade.mqh>
CTrade trade;

enum ENUM_REVERSAL_MODE
{
   REVERSAL_OFF=0,
   REVERSAL_CUT=1,
   REVERSAL_FLIP=2
};

input group "=== SYMBOL ==="
input string InpTradeSymbol="XAUUSDm";
input ulong InpMagicNumber=999889;

input group "=== GRID STOP ==="
input double InpLotSize=0.01;
input int InpTotalLimitOrders=1;
input double InpFirstOrderDistance=0.5;
input double InpStepDistance=0.5;

input group "=== DCA (BASKET) ==="
input bool InpUseDCA=true;
input int InpDCALevels=4;
input double InpDCAStep=2.0;
input double InpDCALotMultiplier=1.0;
input double InpMaxBasketLot=0.05;

input group "=== BASKET TRAILING / TAKE PROFIT ==="
input bool InpUseBasketTrail=true;
input double InpBasketTrailStartUSD=6.0;
input double InpBasketTrailGivebackPct=35.0;
input bool InpUseBasketTakeProfit=false;
input double InpBasketProfitUSD=20.0;

input group "=== HEDGE KHI NEN MANH ==="
input bool InpUseHedge=true;
input double InpHedgeTriggerMove=7.0;
input ENUM_TIMEFRAMES InpHedgeTimeframe=PERIOD_M1;
input double InpHedgeExitProfitUSD=10.0;
input int InpHedgeMaxMinutes=30;

input group "=== SIDEWAY FILTER ==="
input bool InpUseSidewayFilter=true;
input ENUM_TIMEFRAMES InpSidewayTimeframe=PERIOD_M5;
input int InpADXPeriod=14;
input double InpMinADX=20.0;

input group "=== REVERSAL EXIT ==="
input ENUM_REVERSAL_MODE InpReversalMode=REVERSAL_CUT;
input int InpReversalConfirmBars=2;

input group "=== INITIAL SL (TINH TU LENH DAU) ==="
input double InpInitialSLPrice=15.0;

input group "=== ROLLING SL 15 M1 ==="
input bool InpUseRollingSL=false;
input ENUM_TIMEFRAMES InpSLTimeframe=PERIOD_M1;
input int InpSLBars=15;
input double InpSLBuffer=0.20;
input double InpRollingStep=0.30;

input group "=== BREAK EVEN / PROFIT START (TINH TU GIA TB) ==="
input bool InpUseBreakEven=false;
input double InpBreakEvenStart=4.00;
input double InpBreakEvenOffset=3.00;

input group "=== TRAILING SL ==="
input bool InpUseTrailingSL=false;
input double InpTrailingStart=2.00;
input double InpTrailingDistance=0.70;
input double InpTrailingStep=0.20;

input group "=== STOP EXPIRATION ==="
input int InpMaxOrderAgeSeconds=60;

input group "=== VOLUME FILTER ==="
input bool InpUseVolumeFilter=true;
input int InpVolumeMA_Period=20;
input double InpVolumeMultiplier=2.0;

input group "=== MA FILTER ==="
input bool InpUseMAFilter=true;
input ENUM_MA_METHOD InpMAMethod=MODE_EMA;
input int InpFastMAPeriod=20;
input int InpSlowMAPeriod=50;
input ENUM_TIMEFRAMES InpMATimeframe=PERIOD_M1;
input bool InpUseMASlope=true;
input int InpMASlopeBars=3;

input group "=== SPREAD ==="
input double InpMaxSpread=1.50;

const int RETRY_SECONDS=5;
const int MAX_DCA_LEVELS=30;
const string DCA_COMMENT_PREFIX="Gold-DCA-";
const string HEDGE_COMMENT_PREFIX="Gold-HEDGE";
const string FLIP_COMMENT="Gold-FLIP";

int g_fastMAHandle=INVALID_HANDLE;
int g_slowMAHandle=INVALID_HANDLE;
int g_adxHandle=INVALID_HANDLE;
datetime g_nextDCAAttempt=0;
datetime g_nextHedgeAttempt=0;
bool g_loggedNoDirection=false;
bool g_loggedSideway=false;
double g_trailPeakProfit=0;
datetime g_trailBasketTime=0;
double g_failedSL=0;
datetime g_failedSLTime=0;

struct BasketInfo
{
   int count;
   ENUM_POSITION_TYPE type;
   double firstEntry;
   datetime firstTime;
   double averagePrice;
   double totalVolume;
   double totalProfit;
   double lockedSL;
   int dcaMask;
   int hedgeCount;
   datetime hedgeTime;
   double hedgeVolume;
   double hedgeProfit;
};

//+------------------------------------------------------------------+
int OnInit()
{
   if(InpTradeSymbol=="") return INIT_PARAMETERS_INCORRECT;
   if(!SymbolSelect(InpTradeSymbol,true))
   {
      PrintFormat("[INIT ERROR] Không chọn được symbol: %s",InpTradeSymbol);
      return INIT_FAILED;
   }
   if(InpLotSize<=0) return INIT_PARAMETERS_INCORRECT;
   if(InpTotalLimitOrders<1) return INIT_PARAMETERS_INCORRECT;
   if(InpFirstOrderDistance<=0) return INIT_PARAMETERS_INCORRECT;
   if(InpStepDistance<=0) return INIT_PARAMETERS_INCORRECT;
   if(InpInitialSLPrice<=0) return INIT_PARAMETERS_INCORRECT;
   if(InpSLBars<1) return INIT_PARAMETERS_INCORRECT;
   if(InpSLBuffer<0) return INIT_PARAMETERS_INCORRECT;
   if(InpRollingStep<0) return INIT_PARAMETERS_INCORRECT;
   if(InpFastMAPeriod<2) return INIT_PARAMETERS_INCORRECT;
   if(InpSlowMAPeriod<=InpFastMAPeriod) return INIT_PARAMETERS_INCORRECT;
   if(InpMASlopeBars<1) return INIT_PARAMETERS_INCORRECT;
   if(InpVolumeMA_Period<1) return INIT_PARAMETERS_INCORRECT;
   if(InpMaxOrderAgeSeconds<1) return INIT_PARAMETERS_INCORRECT;
   if(InpBreakEvenStart<=0) return INIT_PARAMETERS_INCORRECT;
   if(InpBreakEvenOffset<=0) return INIT_PARAMETERS_INCORRECT;
   if(InpBreakEvenOffset>=InpInitialSLPrice) return INIT_PARAMETERS_INCORRECT;
   if(InpUseBasketTakeProfit && InpBasketProfitUSD<=0) return INIT_PARAMETERS_INCORRECT;
   if(InpUseBasketTrail)
   {
      if(InpBasketTrailStartUSD<=0) return INIT_PARAMETERS_INCORRECT;
      if(InpBasketTrailGivebackPct<=0 || InpBasketTrailGivebackPct>=100) return INIT_PARAMETERS_INCORRECT;
   }

   if(InpUseSidewayFilter)
   {
      if(InpADXPeriod<2) return INIT_PARAMETERS_INCORRECT;
      if(InpMinADX<=0) return INIT_PARAMETERS_INCORRECT;
   }

   if(InpReversalMode!=REVERSAL_OFF)
   {
      if(!InpUseMAFilter) return INIT_PARAMETERS_INCORRECT;
      if(InpReversalConfirmBars<1) return INIT_PARAMETERS_INCORRECT;
   }

   if(InpUseHedge)
   {
      if(InpHedgeTriggerMove<=0) return INIT_PARAMETERS_INCORRECT;
      if(InpHedgeTriggerMove>=InpInitialSLPrice) return INIT_PARAMETERS_INCORRECT;
      if(InpHedgeExitProfitUSD<=0) return INIT_PARAMETERS_INCORRECT;
      if(InpHedgeMaxMinutes<1) return INIT_PARAMETERS_INCORRECT;
   }

   if(InpUseDCA)
   {
      if(InpDCALevels<1 || InpDCALevels>MAX_DCA_LEVELS) return INIT_PARAMETERS_INCORRECT;
      if(InpDCAStep<=0) return INIT_PARAMETERS_INCORRECT;
      if(InpDCALotMultiplier<1.0) return INIT_PARAMETERS_INCORRECT;
      if(InpMaxBasketLot<InpLotSize) return INIT_PARAMETERS_INCORRECT;

      if(InpDCALevels*InpDCAStep>=InpInitialSLPrice)
      {
         PrintFormat("[INIT ERROR] DCA %d x %.2f = %.2f phải nhỏ hơn SL %.2f",
                     InpDCALevels,InpDCAStep,InpDCALevels*InpDCAStep,InpInitialSLPrice);
         return INIT_PARAMETERS_INCORRECT;
      }
   }

   trade.SetExpertMagicNumber(InpMagicNumber);
   trade.SetDeviationInPoints(30);
   trade.SetTypeFillingBySymbol(InpTradeSymbol);

   if(InpUseMAFilter)
   {
      g_fastMAHandle=iMA(InpTradeSymbol,InpMATimeframe,InpFastMAPeriod,0,InpMAMethod,PRICE_CLOSE);
      g_slowMAHandle=iMA(InpTradeSymbol,InpMATimeframe,InpSlowMAPeriod,0,InpMAMethod,PRICE_CLOSE);

      if(g_fastMAHandle==INVALID_HANDLE || g_slowMAHandle==INVALID_HANDLE)
      {
         PrintFormat("[INIT ERROR] Không tạo được MA. Error=%d",GetLastError());
         return INIT_FAILED;
      }
   }

   if(InpUseSidewayFilter)
   {
      g_adxHandle=iADX(InpTradeSymbol,InpSidewayTimeframe,InpADXPeriod);

      if(g_adxHandle==INVALID_HANDLE)
      {
         PrintFormat("[INIT ERROR] Không tạo được ADX. Error=%d",GetLastError());
         return INIT_FAILED;
      }
   }

   MqlTick tick;

   if(!SymbolInfoTick(InpTradeSymbol,tick))
   {
      PrintFormat("[INIT ERROR] Không lấy được tick %s",InpTradeSymbol);
      return INIT_FAILED;
   }

   Print("==================================================");
   Print("[EA] GOLD GRID STOP + DCA v6.11");
   PrintFormat("[EA] BUILD = %s",TimeToString(__DATETIME__,TIME_DATE|TIME_SECONDS));
   Print("[EA] TREND UP   -> BUY STOP  (DCA = BUY MARKET)");
   Print("[EA] TREND DOWN -> SELL STOP (DCA = SELL MARKET)");
   Print("[EA] BASKET SL  -> FIRST ENTRY -/+ INITIAL SL");
   Print("[EA] BE/ROLLING -> AVERAGE PRICE");
   Print("==================================================");
   PrintFormat("[EA] SYMBOL       = %s",InpTradeSymbol);
   PrintFormat("[EA] MAGIC        = %I64u",InpMagicNumber);
   PrintFormat("[EA] LOT          = %.2f",InpLotSize);
   PrintFormat("[EA] GRID         = %d",InpTotalLimitOrders);
   PrintFormat("[EA] DCA          = %s | %d x %.2f | x%.2f | MAX LOT %.2f",
               InpUseDCA?"ON":"OFF",InpDCALevels,InpDCAStep,
               InpDCALotMultiplier,InpMaxBasketLot);
   PrintFormat("[EA] HEDGE        = %s | MOVE %.2f in %s | EXIT TOTAL >= %.2f USD | TIMEOUT %d MIN",
               InpUseHedge?"ON":"OFF",InpHedgeTriggerMove,
               EnumToString(InpHedgeTimeframe),InpHedgeExitProfitUSD,InpHedgeMaxMinutes);
   PrintFormat("[EA] BASKET TRAIL = %s | START %.2f USD | GIVEBACK %.0f%% PEAK",
               InpUseBasketTrail?"ON":"OFF",InpBasketTrailStartUSD,InpBasketTrailGivebackPct);
   PrintFormat("[EA] BASKET TP    = %s | %.2f USD",
               InpUseBasketTakeProfit?"ON":"OFF",InpBasketProfitUSD);
   PrintFormat("[EA] INITIAL SL   = %.2f",InpInitialSLPrice);
   PrintFormat("[EA] BREAK EVEN   = %s | START %.2f | OFFSET +%.2f",
               InpUseBreakEven?"ON":"OFF",InpBreakEvenStart,InpBreakEvenOffset);
   PrintFormat("[EA] ROLLING SL   = %s | BARS %d",
               InpUseRollingSL?"ON":"OFF",InpSLBars);
   PrintFormat("[EA] MA FILTER    = %s | %s %d/%d | TF %s | SLOPE %s(%d)",
               InpUseMAFilter?"ON":"OFF",EnumToString(InpMAMethod),
               InpFastMAPeriod,InpSlowMAPeriod,EnumToString(InpMATimeframe),
               InpUseMASlope?"ON":"OFF",InpMASlopeBars);
   PrintFormat("[EA] SIDEWAY      = %s | ADX(%d) %s < %.1f -> WAIT",
               InpUseSidewayFilter?"ON":"OFF",InpADXPeriod,
               EnumToString(InpSidewayTimeframe),InpMinADX);
   PrintFormat("[EA] REVERSAL     = %s | CONFIRM %d BARS",
               EnumToString(InpReversalMode),InpReversalConfirmBars);
   PrintFormat("[EA] SPREAD       = %.2f",tick.ask-tick.bid);
   Print("==================================================");

   return INIT_SUCCEEDED;
}

//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   if(g_fastMAHandle!=INVALID_HANDLE)
   {
      IndicatorRelease(g_fastMAHandle);
      g_fastMAHandle=INVALID_HANDLE;
   }

   if(g_slowMAHandle!=INVALID_HANDLE)
   {
      IndicatorRelease(g_slowMAHandle);
      g_slowMAHandle=INVALID_HANDLE;
   }

   if(g_adxHandle!=INVALID_HANDLE)
   {
      IndicatorRelease(g_adxHandle);
      g_adxHandle=INVALID_HANDLE;
   }
}

//+------------------------------------------------------------------+
double NormalizePrice(double price)
{
   double tickSize=SymbolInfoDouble(InpTradeSymbol,SYMBOL_TRADE_TICK_SIZE);
   int digits=(int)SymbolInfoInteger(InpTradeSymbol,SYMBOL_DIGITS);

   if(tickSize<=0)
      return NormalizeDouble(price,digits);

   price=MathRound(price/tickSize)*tickSize;

   return NormalizeDouble(price,digits);
}

//+------------------------------------------------------------------+
double NormalizeVolume(double volume)
{
   double minLot=SymbolInfoDouble(InpTradeSymbol,SYMBOL_VOLUME_MIN);
   double maxLot=SymbolInfoDouble(InpTradeSymbol,SYMBOL_VOLUME_MAX);
   double step=SymbolInfoDouble(InpTradeSymbol,SYMBOL_VOLUME_STEP);

   if(step<=0)
      return 0;

   volume=MathMax(minLot,MathMin(maxLot,volume));
   volume=MathFloor(volume/step)*step;

   return NormalizeDouble(volume,8);
}

//+------------------------------------------------------------------+
double StopsDistance()
{
   long stops=SymbolInfoInteger(InpTradeSymbol,SYMBOL_TRADE_STOPS_LEVEL);
   long freeze=SymbolInfoInteger(InpTradeSymbol,SYMBOL_TRADE_FREEZE_LEVEL);
   double point=SymbolInfoDouble(InpTradeSymbol,SYMBOL_POINT);

   return MathMax((double)stops,(double)freeze)*point;
}

//+------------------------------------------------------------------+
bool SpreadAllowed()
{
   MqlTick tick;

   if(!SymbolInfoTick(InpTradeSymbol,tick))
      return false;

   double spread=tick.ask-tick.bid;

   if(spread>InpMaxSpread)
   {
      PrintFormat("[FILTER] SPREAD BLOCK | %.2f > %.2f",spread,InpMaxSpread);
      return false;
   }

   return true;
}

//+------------------------------------------------------------------+
bool GetMAValues(int handle,double &currentMA,double &previousMA)
{
   currentMA=0;
   previousMA=0;

   if(handle==INVALID_HANDLE)
      return false;

   int need=InpMASlopeBars+2;

   if(need<3)
      need=3;

   double buffer[];

   ArraySetAsSeries(buffer,true);

   int copied=CopyBuffer(handle,0,0,need,buffer);

   if(copied<need)
   {
      PrintFormat("[MA] CopyBuffer FAILED | copied=%d need=%d error=%d",
                  copied,need,GetLastError());
      return false;
   }

   currentMA=buffer[1];
   previousMA=buffer[1+InpMASlopeBars];

   return true;
}

//+------------------------------------------------------------------+
//| BUY: MA nhanh > MA cham, gia tren MA nhanh, MA nhanh doc len     |
//+------------------------------------------------------------------+
bool AllowBuyByMA()
{
   if(!InpUseMAFilter)
      return true;

   double fast=0;
   double fastOld=0;
   double slow=0;
   double slowOld=0;

   if(!GetMAValues(g_fastMAHandle,fast,fastOld))
      return false;

   if(!GetMAValues(g_slowMAHandle,slow,slowOld))
      return false;

   MqlTick tick;

   if(!SymbolInfoTick(InpTradeSymbol,tick))
      return false;

   if(fast<=slow)
      return false;

   if(tick.ask<=fast)
      return false;

   if(InpUseMASlope && fast<=fastOld)
      return false;

   return true;
}

//+------------------------------------------------------------------+
//| SELL: MA nhanh < MA cham, gia duoi MA nhanh, MA nhanh doc xuong  |
//+------------------------------------------------------------------+
bool AllowSellByMA()
{
   if(!InpUseMAFilter)
      return true;

   double fast=0;
   double fastOld=0;
   double slow=0;
   double slowOld=0;

   if(!GetMAValues(g_fastMAHandle,fast,fastOld))
      return false;

   if(!GetMAValues(g_slowMAHandle,slow,slowOld))
      return false;

   MqlTick tick;

   if(!SymbolInfoTick(InpTradeSymbol,tick))
      return false;

   if(fast>=slow)
      return false;

   if(tick.bid>=fast)
      return false;

   if(InpUseMASlope && fast>=fastOld)
      return false;

   return true;
}

//+------------------------------------------------------------------+
//| Thi truong sideway: ADX nen da dong < InpMinADX                  |
//+------------------------------------------------------------------+
bool IsSidewayMarket()
{
   if(!InpUseSidewayFilter)
      return false;

   if(g_adxHandle==INVALID_HANDLE)
      return false;

   double adx[];

   ArraySetAsSeries(adx,true);

   if(CopyBuffer(g_adxHandle,0,1,1,adx)<1)
      return false;

   return adx[0]<InpMinADX;
}

//+------------------------------------------------------------------+
//| MA nhanh cat MA cham nguoc chieu ro, du N nen da dong lien tiep  |
//+------------------------------------------------------------------+
bool IsMAReversalAgainst(ENUM_POSITION_TYPE type)
{
   if(g_fastMAHandle==INVALID_HANDLE || g_slowMAHandle==INVALID_HANDLE)
      return false;

   double fast[];
   double slow[];

   ArraySetAsSeries(fast,true);
   ArraySetAsSeries(slow,true);

   if(CopyBuffer(g_fastMAHandle,0,1,InpReversalConfirmBars,fast)<InpReversalConfirmBars)
      return false;

   if(CopyBuffer(g_slowMAHandle,0,1,InpReversalConfirmBars,slow)<InpReversalConfirmBars)
      return false;

   for(int i=0;i<InpReversalConfirmBars;i++)
   {
      if(type==POSITION_TYPE_BUY && fast[i]>=slow[i])
         return false;

      if(type==POSITION_TYPE_SELL && fast[i]<=slow[i])
         return false;
   }

   return true;
}

//+------------------------------------------------------------------+
double FindLowestLow15()
{
   MqlRates rates[];

   ArraySetAsSeries(rates,true);

   int copied=CopyRates(InpTradeSymbol,InpSLTimeframe,1,InpSLBars,rates);

   if(copied<InpSLBars)
      return 0;

   double lowest=rates[0].low;

   for(int i=1;i<InpSLBars;i++)
   {
      if(rates[i].low<lowest)
         lowest=rates[i].low;
   }

   return lowest;
}

//+------------------------------------------------------------------+
double FindHighestHigh15()
{
   MqlRates rates[];

   ArraySetAsSeries(rates,true);

   int copied=CopyRates(InpTradeSymbol,InpSLTimeframe,1,InpSLBars,rates);

   if(copied<InpSLBars)
      return 0;

   double highest=rates[0].high;

   for(int i=1;i<InpSLBars;i++)
   {
      if(rates[i].high>highest)
         highest=rates[i].high;
   }

   return highest;
}

//+------------------------------------------------------------------+
//| BUY initial SL = Entry - 10                                     |
//+------------------------------------------------------------------+
double FindInitialBuySL(double entry)
{
   double sl=NormalizePrice(entry-InpInitialSLPrice);

   if(sl>=entry)
      return 0;

   return sl;
}

//+------------------------------------------------------------------+
//| SELL initial SL = Entry + 10                                    |
//+------------------------------------------------------------------+
double FindInitialSellSL(double entry)
{
   double sl=NormalizePrice(entry+InpInitialSLPrice);

   if(sl<=entry)
      return 0;

   return sl;
}

//+------------------------------------------------------------------+
//| BASKET - gom tat ca vi the cung magic thanh 1 ro                 |
//+------------------------------------------------------------------+
bool IsHedgeComment(const string comment)
{
   return StringFind(comment,HEDGE_COMMENT_PREFIX)==0;
}

//+------------------------------------------------------------------+
double Direction(ENUM_POSITION_TYPE type)
{
   return (type==POSITION_TYPE_BUY)?1.0:-1.0;
}

//+------------------------------------------------------------------+
bool GatherBasket(BasketInfo &basket)
{
   basket.count=0;
   basket.type=POSITION_TYPE_BUY;
   basket.firstEntry=0;
   basket.firstTime=0;
   basket.averagePrice=0;
   basket.totalVolume=0;
   basket.totalProfit=0;
   basket.lockedSL=0;
   basket.dcaMask=0;
   basket.hedgeCount=0;
   basket.hedgeTime=0;
   basket.hedgeVolume=0;
   basket.hedgeProfit=0;

   long firstTimeMsc=0;
   double weightedPrice=0;
   double highestSL=0;
   double lowestSL=0;

   for(int i=PositionsTotal()-1;i>=0;i--)
   {
      ulong ticket=PositionGetTicket(i);

      if(ticket==0)
         continue;

      if(PositionGetString(POSITION_SYMBOL)!=InpTradeSymbol)
         continue;

      if((ulong)PositionGetInteger(POSITION_MAGIC)!=InpMagicNumber)
         continue;

      double volume=PositionGetDouble(POSITION_VOLUME);
      double profit=PositionGetDouble(POSITION_PROFIT)+PositionGetDouble(POSITION_SWAP);
      string comment=PositionGetString(POSITION_COMMENT);

      if(IsHedgeComment(comment))
      {
         datetime hedgeOpenTime=(datetime)PositionGetInteger(POSITION_TIME);

         if(basket.hedgeCount==0 || hedgeOpenTime<basket.hedgeTime)
            basket.hedgeTime=hedgeOpenTime;

         basket.hedgeCount++;
         basket.hedgeVolume+=volume;
         basket.hedgeProfit+=profit;
         continue;
      }

      double openPrice=PositionGetDouble(POSITION_PRICE_OPEN);
      double sl=PositionGetDouble(POSITION_SL);
      long timeMsc=PositionGetInteger(POSITION_TIME_MSC);

      if(basket.count==0 || timeMsc<firstTimeMsc)
      {
         firstTimeMsc=timeMsc;
         basket.firstEntry=openPrice;
         basket.firstTime=(datetime)PositionGetInteger(POSITION_TIME);
         basket.type=(ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);
      }

      if(sl>0)
      {
         if(sl>highestSL)
            highestSL=sl;

         if(lowestSL==0 || sl<lowestSL)
            lowestSL=sl;
      }

      if(StringFind(comment,DCA_COMMENT_PREFIX)==0)
      {
         int level=(int)StringToInteger(StringSubstr(comment,StringLen(DCA_COMMENT_PREFIX)));

         if(level>0 && level<=MAX_DCA_LEVELS)
            basket.dcaMask|=(1<<level);
      }

      weightedPrice+=openPrice*volume;
      basket.totalVolume+=volume;
      basket.totalProfit+=profit;
      basket.count++;
   }

   if(basket.count>0 && basket.totalVolume>0)
   {
      basket.averagePrice=weightedPrice/basket.totalVolume;
      basket.lockedSL=(basket.type==POSITION_TYPE_BUY)?highestSL:lowestSL;
   }

   return (basket.count>0 || basket.hedgeCount>0);
}

//+------------------------------------------------------------------+
int NextDCALevel(int dcaMask)
{
   for(int level=1;level<=InpDCALevels;level++)
   {
      if((dcaMask&(1<<level))==0)
         return level;
   }

   return 0;
}

//+------------------------------------------------------------------+
//| Mo them 1 lenh DCA khi gia cham tang tiep theo                   |
//+------------------------------------------------------------------+
bool TryOpenDCA(const BasketInfo &basket,const MqlTick &tick)
{
   if(!InpUseDCA)
      return false;

   if(TimeCurrent()<g_nextDCAAttempt)
      return false;

   int level=NextDCALevel(basket.dcaMask);

   if(level==0)
      return false;

   double dir=Direction(basket.type);
   bool isBuy=(basket.type==POSITION_TYPE_BUY);

   double levelPrice=NormalizePrice(basket.firstEntry-dir*level*InpDCAStep);
   double entryPrice=isBuy?tick.ask:tick.bid;

   if((entryPrice-levelPrice)*dir>0)
      return false;

   // SL da doi vao vung loi nhuan thi khong DCA nua.
   if(basket.lockedSL>0 && (basket.lockedSL-basket.averagePrice)*dir>=0)
      return false;

   double lot=NormalizeVolume(InpLotSize*MathPow(InpDCALotMultiplier,level));

   if(lot<=0)
      return false;

   if(basket.totalVolume+lot>InpMaxBasketLot+1e-8)
   {
      PrintFormat("[DCA] MAX BASKET LOT | Total=%.2f + %.2f > %.2f",
                  basket.totalVolume,lot,InpMaxBasketLot);
      g_nextDCAAttempt=TimeCurrent()+RETRY_SECONDS;
      return false;
   }

   if(!SpreadAllowed())
   {
      g_nextDCAAttempt=TimeCurrent()+RETRY_SECONDS;
      return false;
   }

   double sl=NormalizePrice(basket.firstEntry-dir*InpInitialSLPrice);
   double slReference=isBuy?tick.bid:tick.ask;

   if((slReference-sl)*dir<StopsDistance())
   {
      PrintFormat("[DCA] SL TOO CLOSE #%d | Distance=%.2f",
                  level,(slReference-sl)*dir);
      g_nextDCAAttempt=TimeCurrent()+RETRY_SECONDS;
      return false;
   }

   string comment=StringFormat("%s%d",DCA_COMMENT_PREFIX,level);

   ResetLastError();

   bool ok=isBuy
      ?trade.Buy(lot,InpTradeSymbol,0,sl,0,comment)
      :trade.Sell(lot,InpTradeSymbol,0,sl,0,comment);

   if(!ok)
   {
      PrintFormat("[DCA] FAILED #%d | Level=%.2f | Retcode=%u | %s | Error=%d",
                  level,levelPrice,trade.ResultRetcode(),
                  trade.ResultRetcodeDescription(),GetLastError());
      g_nextDCAAttempt=TimeCurrent()+RETRY_SECONDS;
      return false;
   }

   PrintFormat("[DCA] OK #%d | Level=%.2f | Lot=%.2f | SL=%.2f | BasketLot=%.2f",
               level,levelPrice,lot,sl,basket.totalVolume+lot);

   return true;
}

//+------------------------------------------------------------------+
//| Dich SL tien ve phia loi nhuan neu candidate tot hon target      |
//+------------------------------------------------------------------+
double AdvanceSL(double target,double candidate,double reference,double dir,double minStep)
{
   double gain=(candidate-target)*dir;

   if(gain<=0 || gain<minStep)
      return target;

   double room=(reference-candidate)*dir;

   if(room<=0 || room<StopsDistance())
      return target;

   return candidate;
}

//+------------------------------------------------------------------+
//| SL muc tieu chung cho ca ro. Chi di ve phia loi nhuan.           |
//+------------------------------------------------------------------+
double CalculateBasketSL(const BasketInfo &basket,const MqlTick &tick,bool hardOnly)
{
   bool isBuy=(basket.type==POSITION_TYPE_BUY);
   double dir=Direction(basket.type);
   double reference=isBuy?tick.bid:tick.ask;

   double target=NormalizePrice(basket.firstEntry-dir*InpInitialSLPrice);

   if(basket.lockedSL>0 && (basket.lockedSL-target)*dir>0)
      target=basket.lockedSL;

   if(hardOnly)
      return target;

   double profit=(reference-basket.averagePrice)*dir;

   if(profit<InpBreakEvenStart)
      return target;

   double firstProfitSL=NormalizePrice(basket.averagePrice+dir*InpBreakEvenOffset);

   if(InpUseBreakEven)
      target=AdvanceSL(target,firstProfitSL,reference,dir,0);

   if(InpUseRollingSL)
   {
      double extreme=isBuy?FindLowestLow15():FindHighestHigh15();

      if(extreme>0)
      {
         double candidate=NormalizePrice(extreme-dir*InpSLBuffer);

         if((candidate-firstProfitSL)*dir<0)
            candidate=firstProfitSL;

         target=AdvanceSL(target,candidate,reference,dir,InpRollingStep);
      }
   }

   if(InpUseTrailingSL && profit>=InpTrailingStart)
   {
      double candidate=NormalizePrice(reference-dir*InpTrailingDistance);

      if((candidate-firstProfitSL)*dir<0)
         candidate=firstProfitSL;

      target=AdvanceSL(target,candidate,reference,dir,InpTrailingStep);
   }

   return target;
}

//+------------------------------------------------------------------+
//| Dong bo SL cua moi lenh trong ro ve SL muc tieu                  |
//+------------------------------------------------------------------+
void SyncBasketSL(const BasketInfo &basket,const MqlTick &tick,bool hardOnly=false)
{
   bool isBuy=(basket.type==POSITION_TYPE_BUY);
   double dir=Direction(basket.type);
   double reference=isBuy?tick.bid:tick.ask;

   double target=CalculateBasketSL(basket,tick,hardOnly);

   if(target<=0)
      return;

   double room=(reference-target)*dir;

   if(room<=0 || room<StopsDistance())
      return;

   if(target==g_failedSL && TimeCurrent()-g_failedSLTime<RETRY_SECONDS)
      return;

   double tickSize=SymbolInfoDouble(InpTradeSymbol,SYMBOL_TRADE_TICK_SIZE);

   if(tickSize<=0)
      tickSize=SymbolInfoDouble(InpTradeSymbol,SYMBOL_POINT);

   for(int i=PositionsTotal()-1;i>=0;i--)
   {
      ulong ticket=PositionGetTicket(i);

      if(ticket==0)
         continue;

      if(PositionGetString(POSITION_SYMBOL)!=InpTradeSymbol)
         continue;

      if((ulong)PositionGetInteger(POSITION_MAGIC)!=InpMagicNumber)
         continue;

      if(IsHedgeComment(PositionGetString(POSITION_COMMENT)))
         continue;

      double currentSL=PositionGetDouble(POSITION_SL);

      if(currentSL>0 && (target-currentSL)*dir<=tickSize*0.5)
         continue;

      ResetLastError();

      if(!trade.PositionModify(ticket,target,0))
      {
         PrintFormat("[SL ERROR] Ticket=%I64u Old=%.2f New=%.2f Retcode=%u %s Error=%d",
                     ticket,currentSL,target,trade.ResultRetcode(),
                     trade.ResultRetcodeDescription(),GetLastError());

         g_failedSL=target;
         g_failedSLTime=TimeCurrent();
         return;
      }

      PrintFormat("[SL MOVED] Ticket=%I64u %.2f -> %.2f | Avg=%.2f | Lot=%.2f",
                  ticket,currentSL,target,basket.averagePrice,basket.totalVolume);
   }
}

//+------------------------------------------------------------------+
//| Dong vi the cua EA (onlyHedge=true: chi dong lenh hedge)         |
//+------------------------------------------------------------------+
void ClosePositions(bool onlyHedge)
{
   for(int i=PositionsTotal()-1;i>=0;i--)
   {
      ulong ticket=PositionGetTicket(i);

      if(ticket==0)
         continue;

      if(PositionGetString(POSITION_SYMBOL)!=InpTradeSymbol)
         continue;

      if((ulong)PositionGetInteger(POSITION_MAGIC)!=InpMagicNumber)
         continue;

      if(onlyHedge && !IsHedgeComment(PositionGetString(POSITION_COMMENT)))
         continue;

      ResetLastError();

      if(!trade.PositionClose(ticket))
      {
         PrintFormat("[CLOSE] FAILED | Ticket=%I64u | Retcode=%u | %s | Error=%d",
                     ticket,trade.ResultRetcode(),
                     trade.ResultRetcodeDescription(),GetLastError());
      }
   }
}

//+------------------------------------------------------------------+
//| Gong lai: dong ro khi lai rut khoi dinh qua InpBasketTrailGiveback% |
//+------------------------------------------------------------------+
bool TryTrailBasketProfit(const BasketInfo &basket)
{
   if(!InpUseBasketTrail)
      return false;

   // Ro moi -> dinh bat dau lai.
   if(basket.firstTime!=g_trailBasketTime)
   {
      g_trailBasketTime=basket.firstTime;
      g_trailPeakProfit=0;
   }

   double profit=basket.totalProfit;

   if(profit>g_trailPeakProfit)
   {
      if(g_trailPeakProfit<InpBasketTrailStartUSD && profit>=InpBasketTrailStartUSD)
      {
         PrintFormat("[TRAIL] ACTIVE | Profit=%.2f >= %.2f | Positions=%d | Lot=%.2f",
                     profit,InpBasketTrailStartUSD,basket.count,basket.totalVolume);
      }

      g_trailPeakProfit=profit;
   }

   if(g_trailPeakProfit<InpBasketTrailStartUSD)
      return false;

   double floorProfit=g_trailPeakProfit*(1.0-InpBasketTrailGivebackPct/100.0);

   if(profit>floorProfit)
      return false;

   PrintFormat("[TRAIL] CLOSE ALL | Peak=%.2f | Floor=%.2f | Profit=%.2f | Positions=%d | Lot=%.2f",
               g_trailPeakProfit,floorProfit,profit,basket.count,basket.totalVolume);

   ClosePositions(false);
   g_trailPeakProfit=0;

   return true;
}

//+------------------------------------------------------------------+
//| Chot toan bo ro khi tong lai (da gom swap) dat nguong USD        |
//+------------------------------------------------------------------+
bool TryTakeBasketProfit(const BasketInfo &basket)
{
   if(!InpUseBasketTakeProfit)
      return false;

   if(basket.totalProfit<InpBasketProfitUSD)
      return false;

   PrintFormat("[BASKET TP] CLOSE ALL | Profit=%.2f >= %.2f | Positions=%d | Lot=%.2f",
               basket.totalProfit,InpBasketProfitUSD,basket.count,basket.totalVolume);

   ClosePositions(false);

   return true;
}

//+------------------------------------------------------------------+
//| Gia chay nguoc chieu ro >= InpHedgeTriggerMove trong nen hien tai |
//+------------------------------------------------------------------+
double AdverseMove(const BasketInfo &basket,const MqlTick &tick)
{
   double barOpen=iOpen(InpTradeSymbol,InpHedgeTimeframe,0);
   datetime barTime=iTime(InpTradeSymbol,InpHedgeTimeframe,0);

   if(barOpen<=0 || barTime==0)
      return 0;

   // Lenh moi vao trong nen nay: chi tinh phan gia chay SAU khi vao lenh.
   double reference=(basket.firstTime>=barTime)?basket.firstEntry:barOpen;

   if(basket.type==POSITION_TYPE_BUY)
      return reference-tick.bid;

   return tick.ask-reference;
}

//+------------------------------------------------------------------+
//| Mo lenh nguoc chieu, lot = 100% tong lot ro (khoa hoan toan)     |
//+------------------------------------------------------------------+
bool TryOpenHedge(const BasketInfo &basket,const MqlTick &tick)
{
   if(!InpUseHedge)
      return false;

   if(TimeCurrent()<g_nextHedgeAttempt)
      return false;

   double move=AdverseMove(basket,tick);

   if(move<InpHedgeTriggerMove)
      return false;

   double lot=NormalizeVolume(basket.totalVolume);

   if(lot<=0)
      return false;

   bool isBuyBasket=(basket.type==POSITION_TYPE_BUY);

   ResetLastError();

   bool ok=isBuyBasket
      ?trade.Sell(lot,InpTradeSymbol,0,0,0,HEDGE_COMMENT_PREFIX)
      :trade.Buy(lot,InpTradeSymbol,0,0,0,HEDGE_COMMENT_PREFIX);

   if(!ok)
   {
      PrintFormat("[HEDGE] FAILED | Move=%.2f | Lot=%.2f | Retcode=%u | %s | Error=%d",
                  move,lot,trade.ResultRetcode(),
                  trade.ResultRetcodeDescription(),GetLastError());
      g_nextHedgeAttempt=TimeCurrent()+RETRY_SECONDS;
      return false;
   }

   PrintFormat("[HEDGE] OPEN %s | Move=%.2f >= %.2f | Lot=%.2f | BasketProfit=%.2f",
               isBuyBasket?"SELL":"BUY",move,InpHedgeTriggerMove,lot,basket.totalProfit);

   return true;
}

//+------------------------------------------------------------------+
//| Dao chieu: cat ro, hoac cat roi vao nguoc chieu (FLIP)           |
//+------------------------------------------------------------------+
bool TryReversalExit(const BasketInfo &basket)
{
   if(InpReversalMode==REVERSAL_OFF)
      return false;

   if(!IsMAReversalAgainst(basket.type))
      return false;

   bool wasBuy=(basket.type==POSITION_TYPE_BUY);

   PrintFormat("[REVERSAL] MA CROSS AGAINST %s | Mode=%s | Basket=%.2f | Hedge=%.2f | Lot=%.2f",
               wasBuy?"BUY":"SELL",EnumToString(InpReversalMode),
               basket.totalProfit,basket.hedgeProfit,basket.totalVolume);

   ClosePositions(false);

   if(InpReversalMode!=REVERSAL_FLIP)
      return true;

   bool allowed=wasBuy?AllowSellByMA():AllowBuyByMA();

   if(!allowed || !SpreadAllowed())
   {
      Print("[REVERSAL] FLIP SKIPPED | MA/SPREAD NOT READY");
      return true;
   }

   MqlTick tick;

   if(!SymbolInfoTick(InpTradeSymbol,tick))
      return true;

   double lot=NormalizeVolume(InpLotSize);

   if(lot<=0)
      return true;

   double entry=wasBuy?tick.bid:tick.ask;
   double sl=NormalizePrice(wasBuy?entry+InpInitialSLPrice:entry-InpInitialSLPrice);

   ResetLastError();

   bool ok=wasBuy
      ?trade.Sell(lot,InpTradeSymbol,0,sl,0,FLIP_COMMENT)
      :trade.Buy(lot,InpTradeSymbol,0,sl,0,FLIP_COMMENT);

   if(ok)
   {
      PrintFormat("[REVERSAL] FLIP %s | Lot=%.2f | SL=%.2f",
                  wasBuy?"SELL":"BUY",lot,sl);
   }
   else
   {
      PrintFormat("[REVERSAL] FLIP FAILED | Retcode=%u | %s | Error=%d",
                  trade.ResultRetcode(),trade.ResultRetcodeDescription(),GetLastError());
   }

   return true;
}

//+------------------------------------------------------------------+
void ManageBasket()
{
   BasketInfo basket;

   if(!GatherBasket(basket))
   {
      g_trailPeakProfit=0;
      return;
   }

   // Ro chinh da het (cham SL) ma hedge con lai -> dong luon.
   if(basket.count==0)
   {
      PrintFormat("[HEDGE] ORPHAN CLOSE | Lot=%.2f | Profit=%.2f",
                  basket.hedgeVolume,basket.hedgeProfit);
      ClosePositions(true);
      return;
   }

   MqlTick tick;

   if(!SymbolInfoTick(InpTradeSymbol,tick))
      return;

   if(TryReversalExit(basket))
      return;

   if(basket.hedgeCount>0)
   {
      double totalProfit=basket.totalProfit+basket.hedgeProfit;

      if(totalProfit>=InpHedgeExitProfitUSD)
      {
         PrintFormat("[HEDGE] TOTAL TP | Total=%.2f >= %.2f | Basket=%.2f | Hedge=%.2f",
                     totalProfit,InpHedgeExitProfitUSD,
                     basket.totalProfit,basket.hedgeProfit);
         ClosePositions(false);
         return;
      }

      int heldSeconds=(int)(TimeCurrent()-basket.hedgeTime);

      if(heldSeconds>=InpHedgeMaxMinutes*60)
      {
         PrintFormat("[HEDGE] TIMEOUT | Held=%d sec >= %d min | Total=%.2f | Basket=%.2f | Hedge=%.2f",
                     heldSeconds,InpHedgeMaxMinutes,totalProfit,
                     basket.totalProfit,basket.hedgeProfit);
         ClosePositions(false);
         return;
      }

      // Dang hedge: khong DCA, khong chot rieng ro chinh, khong BE/rolling.
      SyncBasketSL(basket,tick,true);
      return;
   }

   if(TryTrailBasketProfit(basket))
      return;

   if(TryTakeBasketProfit(basket))
      return;

   if(TryOpenHedge(basket,tick))
      return;

   if(TryOpenDCA(basket,tick))
   {
      if(!GatherBasket(basket) || basket.count==0)
         return;
   }

   SyncBasketSL(basket,tick);
}

//+------------------------------------------------------------------+
void DeleteExpiredPendingOrders()
{
   datetime now=TimeCurrent();

   for(int i=OrdersTotal()-1;i>=0;i--)
   {
      ulong ticket=OrderGetTicket(i);

      if(ticket==0)
         continue;

      if(!OrderSelect(ticket))
         continue;

      if(OrderGetString(ORDER_SYMBOL)!=InpTradeSymbol)
         continue;

      if((ulong)OrderGetInteger(ORDER_MAGIC)!=InpMagicNumber)
         continue;

      ENUM_ORDER_TYPE type=
         (ENUM_ORDER_TYPE)OrderGetInteger(ORDER_TYPE);

      if(type!=ORDER_TYPE_BUY_STOP &&
         type!=ORDER_TYPE_SELL_STOP)
         continue;

      datetime setup=
         (datetime)OrderGetInteger(ORDER_TIME_SETUP);

      int age=(int)(now-setup);

      if(age>=InpMaxOrderAgeSeconds)
      {
         ResetLastError();

         if(trade.OrderDelete(ticket))
         {
            PrintFormat("[EXPIRY] DELETE %I64u | AGE=%d SEC",ticket,age);
         }
         else
         {
            PrintFormat("[EXPIRY ERROR] %I64u | Retcode=%u | %s",
                        ticket,trade.ResultRetcode(),
                        trade.ResultRetcodeDescription());
         }
      }
   }
}

//+------------------------------------------------------------------+
int CountPendingOrders()
{
   int count=0;

   for(int i=OrdersTotal()-1;i>=0;i--)
   {
      ulong ticket=OrderGetTicket(i);

      if(ticket==0)
         continue;

      if(!OrderSelect(ticket))
         continue;

      if(OrderGetString(ORDER_SYMBOL)!=InpTradeSymbol)
         continue;

      if((ulong)OrderGetInteger(ORDER_MAGIC)!=InpMagicNumber)
         continue;

      ENUM_ORDER_TYPE type=
         (ENUM_ORDER_TYPE)OrderGetInteger(ORDER_TYPE);

      if(type==ORDER_TYPE_BUY_STOP ||
         type==ORDER_TYPE_SELL_STOP)
      {
         count++;
      }
   }

   return count;
}

//+------------------------------------------------------------------+
int CountPositions()
{
   int count=0;

   for(int i=PositionsTotal()-1;i>=0;i--)
   {
      ulong ticket=PositionGetTicket(i);

      if(ticket==0)
         continue;

      if(!PositionSelectByTicket(ticket))
         continue;

      if(PositionGetString(POSITION_SYMBOL)!=InpTradeSymbol)
         continue;

      if((ulong)PositionGetInteger(POSITION_MAGIC)!=InpMagicNumber)
         continue;

      count++;
   }

   return count;
}

//+------------------------------------------------------------------+
bool IsVolumeSpike()
{
   if(!InpUseVolumeFilter)
      return false;

   int need=InpVolumeMA_Period+1;

   long volumes[];

   ArraySetAsSeries(volumes,true);

   int copied=CopyTickVolume(InpTradeSymbol,PERIOD_M1,1,need,volumes);

   if(copied<need)
      return false;

   double average=0;

   for(int i=1;i<=InpVolumeMA_Period;i++)
      average+=(double)volumes[i];

   average/=InpVolumeMA_Period;

   if(average<=0)
      return false;

   bool spike=(double)volumes[0]>=average*InpVolumeMultiplier;

   if(spike)
   {
      PrintFormat("[FILTER] VOLUME SPIKE | Current=%d Average=%.1f",
                  volumes[0],average);
   }

   return spike;
}

//+------------------------------------------------------------------+
bool ValidBuyStop(double entry,double ask)
{
   if(entry<=ask)
      return false;

   double minimum=StopsDistance();

   if(entry-ask<minimum)
      return false;

   return true;
}

//+------------------------------------------------------------------+
bool ValidSellStop(double entry,double bid)
{
   if(entry>=bid)
      return false;

   double minimum=StopsDistance();

   if(bid-entry<minimum)
      return false;

   return true;
}

//+------------------------------------------------------------------+
void PlaceBuyStops()
{
   if(!AllowBuyByMA())
   {
      Print("[GRID] BUY BLOCKED BY MA");
      return;
   }

   MqlTick tick;

   if(!SymbolInfoTick(InpTradeSymbol,tick))
      return;

   double lot=NormalizeVolume(InpLotSize);

   if(lot<=0)
   {
      Print("[GRID] INVALID LOT");
      return;
   }

   PrintFormat("[GRID] BUY STOP | ASK=%.2f",tick.ask);

   int success=0;

   for(int i=0;i<InpTotalLimitOrders;i++)
   {
      double offset=
         InpFirstOrderDistance+
         i*InpStepDistance;

      double entry=NormalizePrice(tick.ask+offset);

      if(!ValidBuyStop(entry,tick.ask))
      {
         PrintFormat("[BUY STOP] INVALID ENTRY #%d | %.2f",
                     i+1,entry);
         continue;
      }

      double sl=FindInitialBuySL(entry);

      if(sl<=0)
      {
         PrintFormat("[BUY STOP] INVALID SL #%d",i+1);
         continue;
      }

      double minimum=StopsDistance();

      if(entry-sl<minimum)
      {
         PrintFormat("[BUY STOP] SL TOO CLOSE #%d | Distance=%.2f Minimum=%.2f",
                     i+1,entry-sl,minimum);
         continue;
      }

      ResetLastError();

      bool ok=trade.BuyStop(
         lot,
         entry,
         InpTradeSymbol,
         sl,
         0,
         ORDER_TIME_GTC,
         0,
         StringFormat("Gold-BuyStop-%d",i+1)
      );

      if(ok)
      {
         success++;

         PrintFormat("[BUY STOP] OK #%d | Entry=%.2f | SL=%.2f | Distance=%.2f",
                     i+1,entry,sl,entry-sl);
      }
      else
      {
         PrintFormat("[BUY STOP] FAILED #%d | Entry=%.2f | SL=%.2f | Retcode=%u | %s | Error=%d",
                     i+1,entry,sl,trade.ResultRetcode(),
                     trade.ResultRetcodeDescription(),GetLastError());
      }
   }

   PrintFormat("[GRID] BUY STOP RESULT = %d/%d",
               success,InpTotalLimitOrders);
}

//+------------------------------------------------------------------+
void PlaceSellStops()
{
   if(!AllowSellByMA())
   {
      Print("[GRID] SELL BLOCKED BY MA");
      return;
   }

   MqlTick tick;

   if(!SymbolInfoTick(InpTradeSymbol,tick))
      return;

   double lot=NormalizeVolume(InpLotSize);

   if(lot<=0)
   {
      Print("[GRID] INVALID LOT");
      return;
   }

   PrintFormat("[GRID] SELL STOP | BID=%.2f",tick.bid);

   int success=0;

   for(int i=0;i<InpTotalLimitOrders;i++)
   {
      double offset=
         InpFirstOrderDistance+
         i*InpStepDistance;

      double entry=NormalizePrice(tick.bid-offset);

      if(!ValidSellStop(entry,tick.bid))
      {
         PrintFormat("[SELL STOP] INVALID ENTRY #%d | %.2f",
                     i+1,entry);
         continue;
      }

      double sl=FindInitialSellSL(entry);

      if(sl<=entry)
      {
         PrintFormat("[SELL STOP] INVALID SL #%d",i+1);
         continue;
      }

      double minimum=StopsDistance();

      if(sl-entry<minimum)
      {
         PrintFormat("[SELL STOP] SL TOO CLOSE #%d | Distance=%.2f Minimum=%.2f",
                     i+1,sl-entry,minimum);
         continue;
      }

      ResetLastError();

      bool ok=trade.SellStop(
         lot,
         entry,
         InpTradeSymbol,
         sl,
         0,
         ORDER_TIME_GTC,
         0,
         StringFormat("Gold-SellStop-%d",i+1)
      );

      if(ok)
      {
         success++;

         PrintFormat("[SELL STOP] OK #%d | Entry=%.2f | SL=%.2f | Distance=%.2f",
                     i+1,entry,sl,sl-entry);
      }
      else
      {
         PrintFormat("[SELL STOP] FAILED #%d | Entry=%.2f | SL=%.2f | Retcode=%u | %s | Error=%d",
                     i+1,entry,sl,trade.ResultRetcode(),
                     trade.ResultRetcodeDescription(),GetLastError());
      }
   }

   PrintFormat("[GRID] SELL STOP RESULT = %d/%d",
               success,InpTotalLimitOrders);
}

//+------------------------------------------------------------------+
void PlaceGrid()
{
   if(!SpreadAllowed())
      return;

   if(IsSidewayMarket())
   {
      if(!g_loggedSideway)
      {
         PrintFormat("[GRID] SIDEWAY ADX < %.1f -> WAIT",InpMinADX);
         g_loggedSideway=true;
      }

      return;
   }

   g_loggedSideway=false;

   bool buyAllowed=AllowBuyByMA();
   bool sellAllowed=AllowSellByMA();

   if(!buyAllowed && !sellAllowed)
   {
      if(!g_loggedNoDirection)
      {
         Print("[GRID] NO MA DIRECTION -> WAIT");
         g_loggedNoDirection=true;
      }

      return;
   }

   g_loggedNoDirection=false;

   if(buyAllowed && !sellAllowed)
   {
      Print("[GRID] DIRECTION = BUY");
      PlaceBuyStops();
      return;
   }

   if(sellAllowed && !buyAllowed)
   {
      Print("[GRID] DIRECTION = SELL");
      PlaceSellStops();
      return;
   }

   MqlRates rates[];

   ArraySetAsSeries(rates,true);

   int copied=CopyRates(InpTradeSymbol,PERIOD_M1,1,2,rates);

   if(copied<2)
      return;

   if(rates[0].close>rates[0].open)
   {
      Print("[GRID] BOTH MA CONDITIONS -> M1 BULLISH -> BUY STOP");
      PlaceBuyStops();
   }
   else if(rates[0].close<rates[0].open)
   {
      Print("[GRID] BOTH MA CONDITIONS -> M1 BEARISH -> SELL STOP");
      PlaceSellStops();
   }
   else
   {
      Print("[GRID] M1 CANDLE DOJI -> WAIT");
   }
}

//+------------------------------------------------------------------+
void OnTick()
{
   ManageBasket();

   DeleteExpiredPendingOrders();

   if(CountPositions()>0)
      return;

   if(CountPendingOrders()>0)
      return;

   if(IsVolumeSpike())
      return;

   PlaceGrid();
}
//+------------------------------------------------------------------+
