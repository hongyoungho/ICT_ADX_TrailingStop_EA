//+------------------------------------------------------------------+
//| ICT + ADX + Dual MA + Zigzag Multi-Signal EA                     |
//+------------------------------------------------------------------+
#property copyright "Copilot"
#property version   "2.00"
#property strict

//--- Input Parameters
input double Lots = 0.10;
input int    ADX_Period = 14;
input double ADX_Threshold = 25.0;
input int    MA1_Period = 20;        // 첫번째 Moving Average
input int    MA2_Period = 50;        // 두번째 Moving Average
input int    ZigZag_Depth = 12;      // Zigzag 깊이
input int    Lookback = 100;
input int    TrailStartPoints = 80;
input int    TrailStepPoints = 20;
input int    StopLossPoints = 80;
input int    TakeProfitPoints = 180;

// 지표 핸들
int adxHandle, ma1Handle, ma2Handle, zigzagHandle;
double adxBuffer[], ma1Buffer[], ma2Buffer[], zigzagBuffer[];
double highBuffer[], lowBuffer[], closeBuffer[];

// 상태 추적
int lastSignalState = 0;      // 0: 없음, 1: 매수 준비, -1: 매도 준비
int confirmedSignal = 0;      // 0: 없음, 1: 매수 확정, -1: 매도 확정
int positionSignalCount = 0;  // 포지션 중 신호 개수 추적

int OnInit()
{
   adxHandle = iADX(_Symbol, _Period, ADX_Period);
   ma1Handle = iMA(_Symbol, _Period, MA1_Period, 0, MODE_EMA, PRICE_CLOSE);
   ma2Handle = iMA(_Symbol, _Period, MA2_Period, 0, MODE_EMA, PRICE_CLOSE);
   zigzagHandle = iCustom(_Symbol, _Period, "ZigZag");

   if(adxHandle == INVALID_HANDLE || ma1Handle == INVALID_HANDLE || 
      ma2Handle == INVALID_HANDLE || zigzagHandle == INVALID_HANDLE)
   {
      Print("Indicator initialization failed");
      return(INIT_FAILED);
   }

   ArraySetAsSeries(adxBuffer, true);
   ArraySetAsSeries(ma1Buffer, true);
   ArraySetAsSeries(ma2Buffer, true);
   ArraySetAsSeries(zigzagBuffer, true);
   ArraySetAsSeries(highBuffer, true);
   ArraySetAsSeries(lowBuffer, true);
   ArraySetAsSeries(closeBuffer, true);

   return(INIT_SUCCEEDED);
}

void OnDeinit(const int reason)
{
   IndicatorRelease(adxHandle);
   IndicatorRelease(ma1Handle);
   IndicatorRelease(ma2Handle);
   IndicatorRelease(zigzagHandle);
}

void OnTick()
{
   if(!IsNewBar())
      return;

   // 지표 데이터 복사
   if(CopyBuffer(adxHandle, 0, 0, Lookback, adxBuffer) <= 0)
      return;
   if(CopyBuffer(ma1Handle, 0, 0, Lookback, ma1Buffer) <= 0)
      return;
   if(CopyBuffer(ma2Handle, 0, 0, Lookback, ma2Buffer) <= 0)
      return;
   if(CopyBuffer(zigzagHandle, 0, 0, Lookback, zigzagBuffer) <= 0)
      return;
   if(CopyHigh(_Symbol, _Period, 0, Lookback, highBuffer) <= 0)
      return;
   if(CopyLow(_Symbol, _Period, 0, Lookback, lowBuffer) <= 0)
      return;
   if(CopyClose(_Symbol, _Period, 0, Lookback, closeBuffer) <= 0)
      return;

   // ADX 강도 확인
   if(adxBuffer[0] < ADX_Threshold)
      return;

   // 3개 지표 신호 분석
   int ma1Signal = GetMA_Signal(1);           // MA1 신호 (1=상승, -1=하락, 0=없음)
   int ma2Signal = GetMA_Signal(2);           // MA2 신호 (1=상승, -1=하락, 0=없음)
   int zigzagSignal = GetZigZagSignal();      // Zigzag 신호 (1=상승, -1=하락, 0=없음)

   int totalSignal = CountSignals(ma1Signal, ma2Signal, zigzagSignal);

   // ========== 진입 로직 ==========
   if(PositionsTotal() == 0)
   {
      // 신호 3개 모두 같은 방향 → 진입
      if(ma1Signal != 0 && ma2Signal != 0 && zigzagSignal != 0 &&
         ma1Signal == ma2Signal && ma2Signal == zigzagSignal)
      {
         confirmedSignal = ma1Signal;
         positionSignalCount = 3;

         if(confirmedSignal == 1)
         {
            double entry = Ask;
            double sl = entry - StopLossPoints * _Point;
            double tp = entry + TakeProfitPoints * _Point;
            OpenBuy(entry, sl, tp);
            Print("BUY OPENED - All 3 signals aligned");
         }
         else if(confirmedSignal == -1)
         {
            double entry = Bid;
            double sl = entry + StopLossPoints * _Point;
            double tp = entry - TakeProfitPoints * _Point;
            OpenSell(entry, sl, tp);
            Print("SELL OPENED - All 3 signals aligned");
         }
      }
      // 신호 2개 이상 같은 방향 → 대기
      else if(totalSignal >= 2)
      {
         lastSignalState = GetMajoritySignal(ma1Signal, ma2Signal, zigzagSignal);
         Print("Waiting for confirmation - ", totalSignal, " signals aligned");
      }
   }

   // ========== 포지션 관리 ==========
   else
   {
      ManageTrailingStop();
      ManageActivePosition(ma1Signal, ma2Signal, zigzagSignal);
   }
}

// Moving Average 신호 얻기
int GetMA_Signal(int ma_type)
{
   double *maBuffer = (ma_type == 1) ? ma1Buffer : ma2Buffer;

   if(closeBuffer[0] > maBuffer[0] && closeBuffer[1] <= maBuffer[1])
      return 1;  // 상승 크로스
   else if(closeBuffer[0] < maBuffer[0] && closeBuffer[1] >= maBuffer[1])
      return -1; // 하락 크로스

   return 0;    // 신호 없음
}

// Zigzag 신호 얻기 (변곡점 감지)
int GetZigZagSignal()
{
   // Zigzag 고점에서 반락 시작
   if(zigzagBuffer[2] > 0 && zigzagBuffer[1] == 0 && zigzagBuffer[0] < zigzagBuffer[2])
      return -1;  // 하강 신호

   // Zigzag 저점에서 반등 시작
   if(zigzagBuffer[2] < zigzagBuffer[1] && zigzagBuffer[1] == 0 && zigzagBuffer[0] > zigzagBuffer[2])
      return 1;   // 상승 신호

   return 0;      // 신호 없음
}

// 신호 개수 세기
int CountSignals(int ma1, int ma2, int zigzag)
{
   int count = 0;
   if(ma1 != 0) count++;
   if(ma2 != 0) count++;
   if(zigzag != 0) count++;
   return count;
}

// 다수결 신호 구하기
int GetMajoritySignal(int ma1, int ma2, int zigzag)
{
   int upCount = 0, downCount = 0;

   if(ma1 == 1) upCount++; else if(ma1 == -1) downCount++;
   if(ma2 == 1) upCount++; else if(ma2 == -1) downCount++;
   if(zigzag == 1) upCount++; else if(zigzag == -1) downCount++;

   if(upCount > downCount) return 1;
   if(downCount > upCount) return -1;
   return 0;
}

// 포지션 활성 관리
void ManageActivePosition(int ma1Signal, int ma2Signal, int zigzagSignal)
{
   int currentMajority = GetMajoritySignal(ma1Signal, ma2Signal, zigzagSignal);
   int signalsNow = CountSignals(ma1Signal, ma2Signal, zigzagSignal);

   // 1개 지표 크로스 → 경고 (계속 진행)
   if(signalsNow == 1)
   {
      Print("WARNING: 1 signal crossed. Monitoring...");
      return;
   }

   // 2개 이상 같은 방향 유지 → 계속 진행
   if(signalsNow >= 2)
   {
      Print("Position Active - ", signalsNow, " signals aligned, Majority: ", currentMajority);
      return;
   }

   // 3개 모두 반대 방향 → 포지션 종료 (다중 진입 방지)
   if(currentMajority == -confirmedSignal && signalsNow == 3)
   {
      Print("All signals reversed - Closing position");
      CloseAllPositions();
      confirmedSignal = 0;
   }
}

void OpenBuy(double entry, double sl, double tp)
{
   CTrade trade;
   trade.Buy(Lots, _Symbol, entry, sl, tp, "MA_ZZ_BUY");
}

void OpenSell(double entry, double sl, double tp)
{
   CTrade trade;
   trade.Sell(Lots, _Symbol, entry, sl, tp, "MA_ZZ_SELL");
}

// 트레일링 스탑
void ManageTrailingStop()
{
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      if(!PositionSelectByTicket(PositionGetTicket(i)))
         continue;

      string symbol = PositionGetString(POSITION_SYMBOL);
      if(symbol != _Symbol)
         continue;

      int type = (int)PositionGetInteger(POSITION_TYPE);
      double currentPrice = (type == POSITION_TYPE_BUY) ? Bid : Ask;
      double currentStop = PositionGetDouble(POSITION_SL);

      if(type == POSITION_TYPE_BUY)
      {
         double newStop = currentPrice - TrailStepPoints * _Point;
         if(currentStop < newStop)
         {
            CTrade trade;
            trade.PositionModify(_Symbol, newStop, PositionGetDouble(POSITION_TP));
         }
      }
      else if(type == POSITION_TYPE_SELL)
      {
         double newStop = currentPrice + TrailStepPoints * _Point;
         if(currentStop > newStop)
         {
            CTrade trade;
            trade.PositionModify(_Symbol, newStop, PositionGetDouble(POSITION_TP));
         }
      }
   }
}

void CloseAllPositions()
{
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      if(!PositionSelectByTicket(PositionGetTicket(i)))
         continue;

      if(PositionGetString(POSITION_SYMBOL) == _Symbol)
      {
         CTrade trade;
         trade.PositionClose(PositionGetTicket(i));
      }
   }
}

bool IsNewBar()
{
   static datetime lastTime = 0;
   datetime current = iTime(_Symbol, _Period, 0);

   if(lastTime == current)
      return false;

   lastTime = current;
   return true;
}