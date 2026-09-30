import MetaTrader5 as mt5
import pandas as pd
import numpy as np
from datetime import datetime, timedelta
import time

SYMBOL = "EURUSD"
TIMEFRAME = mt5.TIMEFRAME_H1
LOT_SIZE = 0.1
ADX_PERIOD = 14
ADX_THRESHOLD = 25.0
MA1_PERIOD = 20
MA2_PERIOD = 50
ZIGZAG_DEPTH = 12

class TripleIndicatorStrategy:
    def __init__(self):
        if not mt5.initialize():
            print("MT5 initialization failed")
            exit()
        
        self.symbol = SYMBOL
        self.timeframe = TIMEFRAME
        self.lot_size = LOT_SIZE
        self.confirmed_signal = 0  # 0: 없음, 1: 매수, -1: 매도
        self.position_signal_count = 0
    
    def get_data(self, bars=100):
        """캔들 데이터 가져오기"""
        rates = mt5.copy_rates_from_pos(self.symbol, self.timeframe, 0, bars)
        df = pd.DataFrame(rates)
        df['time'] = pd.to_datetime(df['time'], unit='s')
        return df
    
    def calculate_adx(self, df, period=ADX_PERIOD):
        """ADX 계산"""
        high = df['high'].values
        low = df['low'].values
        close = df['close'].values
        
        tr = np.zeros(len(df))
        for i in range(1, len(df)):
            tr[i] = max(high[i] - low[i],
                       abs(high[i] - close[i-1]),
                       abs(low[i] - close[i-1]))
        
        atr = pd.Series(tr).rolling(period).mean()
        
        # DM 계산
        up_move = np.diff(high, prepend=0)
        down_move = -np.diff(low, prepend=0)
        
        plus_dm = np.where((up_move > down_move) & (up_move > 0), up_move, 0)
        minus_dm = np.where((down_move > up_move) & (down_move > 0), down_move, 0)
        
        plus_di = 100 * pd.Series(plus_dm).rolling(period).mean() / atr
        minus_di = 100 * pd.Series(minus_dm).rolling(period).mean() / atr
        
        dx = 100 * abs(plus_di - minus_di) / (plus_di + minus_di)
        adx = dx.rolling(period).mean()
        
        return adx.values
    
    def calculate_ma(self, df, period, ma_type='EMA'):
        """이동평균 계산"""
        close = df['close'].values
        if ma_type == 'EMA':
            return pd.Series(close).ewm(span=period, adjust=False).mean().values
        else:
            return pd.Series(close).rolling(period).mean().values
    
    def calculate_zigzag(self, df, depth=ZIGZAG_DEPTH):
        """Zigzag 지표 계산 (간단한 버전)"""
        high = df['high'].values
        low = df['low'].values
        zigzag = np.zeros(len(df))
        
        for i in range(depth, len(df)):
            # 고점 감지
            if high[i] == max(high[max(0, i-depth):i+1]):
                zigzag[i] = high[i]
            # 저점 감지
            elif low[i] == min(low[max(0, i-depth):i+1]):
                zigzag[i] = low[i]
        
        return zigzag
    
    def get_ma_signal(self, close, ma, index):
        """MA 신호 (크로스)"""
        if index < 1:
            return 0
        
        # 상승 크로스
        if close[index] > ma[index] and close[index-1] <= ma[index-1]:
            return 1
        # 하락 크로스
        elif close[index] < ma[index] and close[index-1] >= ma[index-1]:
            return -1
        
        return 0
    
    def get_zigzag_signal(self, zigzag, high, low, index):
        """Zigzag 신호"""
        if index < 2:
            return 0
        
        # 고점에서 하강
        if zigzag[index-2] > 0 and zigzag[index-1] == 0 and low[index] < zigzag[index-2]:
            return -1
        # 저점에서 상승
        elif zigzag[index-2] < zigzag[index-1] and zigzag[index-1] == 0 and high[index] > zigzag[index-2]:
            return 1
        
        return 0
    
    def count_signals(self, ma1_sig, ma2_sig, zigzag_sig):
        """신호 개수 세기"""
        count = 0
        if ma1_sig != 0:
            count += 1
        if ma2_sig != 0:
            count += 1
        if zigzag_sig != 0:
            count += 1
        return count
    
    def get_majority_signal(self, ma1_sig, ma2_sig, zigzag_sig):
        """다수결 신호"""
        up_count = 0
        down_count = 0
        
        if ma1_sig == 1:
            up_count += 1
        elif ma1_sig == -1:
            down_count += 1
        
        if ma2_sig == 1:
            up_count += 1
        elif ma2_sig == -1:
            down_count += 1
        
        if zigzag_sig == 1:
            up_count += 1
        elif zigzag_sig == -1:
            down_count += 1
        
        if up_count > down_count:
            return 1
        elif down_count > up_count:
            return -1
        return 0
    
    def analyze_signals(self, df):
        """3개 지표 분석"""
        close = df['close'].values
        high = df['high'].values
        low = df['low'].values
        
        adx = self.calculate_adx(df)
        ma1 = self.calculate_ma(df, MA1_PERIOD)
        ma2 = self.calculate_ma(df, MA2_PERIOD)
        zigzag = self.calculate_zigzag(df)
        
        # 최신 신호
        ma1_signal = self.get_ma_signal(close, ma1, -1)
        ma2_signal = self.get_ma_signal(close, ma2, -1)
        zigzag_signal = self.get_zigzag_signal(zigzag, high, low, -1)
        
        return {
            'adx': adx[-1],
            'ma1_signal': ma1_signal,
            'ma2_signal': ma2_signal,
            'zigzag_signal': zigzag_signal,
            'signal_count': self.count_signals(ma1_signal, ma2_signal, zigzag_signal),
            'majority': self.get_majority_signal(ma1_signal, ma2_signal, zigzag_signal)
        }
    
    def place_order(self, signal_type):
        """주문 실행"""
        point = mt5.symbol_info(self.symbol).point
        
        if signal_type == 1:  # 매수
            price = mt5.symbol_info_tick(self.symbol).ask
            sl = price - 80 * point
            tp = price + 180 * point
            
            request = {
                "action": mt5.TRADE_ACTION_DEAL,
                "symbol": self.symbol,
                "volume": self.lot_size,
                "type": mt5.ORDER_TYPE_BUY,
                "price": price,
                "sl": sl,
                "tp": tp,
                "comment": "Triple_Signal_BUY"
            }
        
        elif signal_type == -1:  # 매도
            price = mt5.symbol_info_tick(self.symbol).bid
            sl = price + 80 * point
            tp = price - 180 * point
            
            request = {
                "action": mt5.TRADE_ACTION_DEAL,
                "symbol": self.symbol,
                "volume": self.lot_size,
                "type": mt5.ORDER_TYPE_SELL,
                "price": price,
                "sl": sl,
                "tp": tp,
                "comment": "Triple_Signal_SELL"
            }
        
        result = mt5.order_send(request)
        print(f"Order result: {result}")
    
    def manage_position(self, signals):
        """포지션 관리"""
        if len(mt5.positions_get(symbol=self.symbol)) == 0:
            return
        
        signal_count = signals['signal_count']
        majority = signals['majority']
        
        # 1개 지표만 크로스 → 경고만
        if signal_count == 1:
            print("WARNING: 1 signal crossed - Monitoring...")
            return
        
        # 2개 이상 유지 → 계속 진행
        if signal_count >= 2:
            print(f"Position Active - {signal_count} signals aligned")
            return
        
        # 3개 모두 반대 → 종료
        if signal_count == 3 and majority == -self.confirmed_signal:
            print("All signals reversed - Closing position")
            self.close_all_positions()
            self.confirmed_signal = 0
    
    def close_all_positions(self):
        """모든 포지션 종료"""
        positions = mt5.positions_get(symbol=self.symbol)
        for pos in positions:
            request = {
                "action": mt5.TRADE_ACTION_DEAL,
                "symbol": self.symbol,
                "volume": pos.volume,
                "type": mt5.ORDER_TYPE_SELL if pos.type == mt5.POSITION_TYPE_BUY else mt5.ORDER_TYPE_BUY,
                "position": pos.ticket
            }
            mt5.order_send(request)
    
    def run(self):
        """전략 실행"""
        print("Triple Indicator Strategy Started...")
        
        while True:
            df = self.get_data()
            signals = self.analyze_signals(df)
            
            print(f"Time: {datetime.now()}, ADX: {signals['adx']:.2f}, "
                  f"MA1: {signals['ma1_signal']}, MA2: {signals['ma2_signal']}, "
                  f"ZigZag: {signals['zigzag_signal']}, Count: {signals['signal_count']}")
            
            # ADX 강도 확인
            if signals['adx'] < ADX_THRESHOLD:
                time.sleep(60)
                continue
            
            # 포지션 없을 때
            if len(mt5.positions_get(symbol=self.symbol)) == 0:
                # 3개 신호 모두 같은 방향
                if (signals['ma1_signal'] != 0 and signals['ma2_signal'] != 0 and 
                    signals['zigzag_signal'] != 0 and
                    signals['ma1_signal'] == signals['ma2_signal'] == signals['zigzag_signal']):
                    
                    self.confirmed_signal = signals['ma1_signal']
                    self.place_order(self.confirmed_signal)
                    print(f"ENTERED: All 3 signals aligned - Signal: {self.confirmed_signal}")
            
            # 포지션 있을 때
            else:
                self.manage_position(signals)
            
            time.sleep(60)

if __name__ == "__main__":
    strategy = TripleIndicatorStrategy()
    strategy.run()