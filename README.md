# ICT + ADX + Triple Indicator EA with Trailing Stop

## 전략 개요

이 Expert Advisor는 **3개의 기술적 지표**를 동시에 분석하여 거래 신호를 생성합니다.

### 사용 지표
1. **ADX (Average Directional Index)** - 추세 강도 확인
2. **Dual Moving Averages** - MA(20) + MA(50) 크로스 신호
3. **Zigzag** - 고점/저점 변곡점 감지

---

## 진입 규칙

### 신호 대기
- 2개 이상의 지표가 같은 방향 → **대기 상태** (3번째 신호 기다림)

### 진입 조건
- **3개 지표 모두 같은 방향** + **ADX > 25** → **진입**
- 매수: MA1↑ + MA2↑ + ZigZag↑
- 매도: MA1↓ + MA2↓ + ZigZag↓

---

## 포지션 관리

### 진행 중 신호 변화
| 상황 | 동작 |
|------|------|
| **1개 지표 크로스** | ⚠️ 경고 (계속 진행) |
| **2개 이상 유지** | ✅ 계속 진행 |
| **3개 모두 반대** | ❌ 포지션 종료 |

### 트레일링 스탑
- **시작점**: 80포인트 이상 수익 발생
- **보폭**: 20포인트마다 손절선 상향 조정
- **목적**: 수익을 자동으로 보호

---

## 설정값 최적화

```mql5
input double Lots = 0.10;              // 거래량
input int ADX_Period = 14;             // ADX 기간
input double ADX_Threshold = 25.0;     // ADX 강도 (25 이상 권장)
input int MA1_Period = 20;             // 첫번째 이동평균
input int MA2_Period = 50;             // 두번째 이동평균
input int ZigZag_Depth = 12;           // Zigzag 깊이
input int TrailStepPoints = 20;        // 트레일 보폭
input int StopLossPoints = 80;         // 초기 손절
input int TakeProfitPoints = 180;      // 초기 익절
```

### 추천 최적화
- **보수적**: ADX_Threshold = 30, StopLossPoints = 100
- **공격적**: ADX_Threshold = 20, StopLossPoints = 50
- **장기**: TimeFrame = H4, MA1=50, MA2=200
- **단기**: TimeFrame = M15, MA1=10, MA2=20

---

## 사용 방법

### MT5 (MQL5)
1. `ICT_ADX_TripleIndicator_EA.mq5`를 MetaEditor에 복사
2. 컴파일
3. 차트에 드래그하여 실행
4. 파라미터 조정

### Python (MetaTrader5 API)
```bash
pip install MetaTrader5 pandas numpy
python ICT_ADX_TripleIndicator.py
```

---

## 주의사항

⚠️ **중요**
- 이 EA는 자동매매 도구일 뿐 100% 승리를 보장하지 않습니다.
- 반드시 **데모 계좌**에서 충분히 테스트 후 사용하세요.
- **손절선은 필수**입니다. 손절선 없이 거래하지 마세요.
- 시장 뉉스나 급변 시기에는 EA를 비활성화하세요.
- 정기적으로 거래 결과를 분석하고 파라미터를 조정하세요.

---

## 버전 히스토리

**v2.0** (현재)
- 3개 지표 동시 분석 기능
- 트레일링 스탑 최적화
- 다중 신호 검증 로직

**v1.0**
- 기본 ICT + ADX 전략

---

## 라이선스

MIT License - 자유롭게 수정/배포 가능

---

## 지원

문제 발생 시 GitHub Issues에 보고해주세요.
