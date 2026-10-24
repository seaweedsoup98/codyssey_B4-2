# 평가 대비: 코드와 근거로 답하기

각 질문은 **요점 → 근거 위치** 순서다. 실측하지 않은 결과는 답변에 넣지 않는다.

| 예상 질문 | 답변의 핵심 논리 | 코드 / 확인 대상 |
| --- | --- | --- |
| B4-2의 최종 목표는? | 같은 바이너리의 OOM·CPU·Deadlock을 객관적 로그로 진단하고 조치 전후를 검증해 3건의 GitHub Issue로 소통 | `README.md`, Issues #1~#3 |
| 왜 root 실행을 막는가? | 앱의 부트 조건이 일반 사용자이고, 불필요한 권한 확대도 피하기 때문 | `setup.sh`, `run_case.sh`의 `EUID` 검증 |
| 환경변수는 언제 반영되는가? | 부모 셸이 `export`한 값을 **새로 시작한** 자식 프로세스가 상속 | `run_case.sh`의 `source`, `export`, `setsid` |
| `AGENT_PORT=15034`는 왜 확인하나? | 바이너리 고정 포트이며 다른 프로세스가 점유하면 바인딩할 수 없음 | `run_case.sh`의 `ss` 검사; `processes.txt` |
| PID와 스레드는 어떻게 다른가? | PID는 프로세스 식별, TID는 프로세스 안의 실행 흐름 식별 | `processes.txt`의 `PID`, `TID`, `PGID` |
| RSS와 Heap의 차이는? | RSS는 RAM 상주 메모리, Heap은 동적 할당 영역. 같은 지표가 아님 | `monitor.sh`의 `VmRSS`; `application.log` |
| CPU 사용률은 어떻게 측정하나? | `/proc/<PID>/stat`의 CPU ticks 차이를 시간 차이와 CLK_TCK로 나눔 | `monitor.sh`의 `ticks`, `previous_ticks`, `cpu` 계산 |
| 첫 샘플의 CPU가 `NA`인 이유는? | 직전 CPU 시간과 구간 길이가 없어 차분 불가 | `monitor.sh`의 `cpu=NA` |
| OOM과 MemoryGuard 종료는 같은가? | Linux OOM Killer와 앱 자체 MemoryGuard는 서로 다른 종료 주체; 로그로 판정 | Issue #1, `application.log` |
| 메모리 제한 상향은 누수를 고치나? | 아니며 임계치 도달만 늦추는 임시 조치 | Issue #1의 Before/After |
| CPU Spike가 시스템 지연을 증명하나? | 과점유는 지연 원인이 될 수 있지만 실제 지연은 별도 측정이 필요 | `monitor.tsv`, Issue #2 |
| 종료 코드 143이면 Watchdog인가? | 단정 불가. SIGTERM 관련 코드지만 실험기의 종료 요청일 수도 있음 | `result.txt`의 `reason`, `application.log` |
| Deadlock과 단순 대기를 어떻게 구분하나? | PID·로그 정체만으로 부족. 양방향 자원 보유·대기 및 순환 고리를 증명 | Issue #3, `application.log`, `processes.txt` |
| `WCHAN=futex_wait`만으로 Deadlock인가? | 아니다. 정상 동기화 대기도 futex를 사용할 수 있음 | `processes.txt`, `docs/CONCEPTS.md` |
| 멀티스레드를 끄면 근본 해결인가? | 재현 회피일 뿐. 근본 해결은 락 획득 순서·시간 제한 등 구조 개선 | Issue #3 |
| 왜 6번 실행하는가? | 장애 3종 × 설정 전후 2조건; 각 쌍에서는 변수 하나만 바꿔 비교 | `run_case.sh`의 `case` 분기 |
| 실험기가 왜 프로세스 그룹을 종료하나? | 제한 시간이 지나도 남은 자식 프로세스까지 정리하기 위해 | `run_case.sh`의 `setsid`, `group_alive`, `cleanup` |
| 로그의 사실성과 재현성을 어떻게 보장하나? | 원본 앱 로그 + 동일 시각의 관제/스레드 데이터 + 변수와 바이너리 해시 보관 | `evidence/.../`의 5개 파일 |

## 발표·시연 순서

1. `README.md`의 실험 조건 표: 무엇을 바꾸고 무엇을 고정했는지 설명.
2. `scripts/setup.sh` → `scripts/run_case.sh` → `scripts/monitor.sh` 순서로 함수 흐름 추적.
3. 각 Issue에서 **원본 증거 → 원인 추론 → 변경 설정 → 검증 결과**를 보여 주기.
4. 실제 수집되지 않은 수치는 발표하지 않기. `reason=observation_limit`와 앱 자체 종료를 엄격히 구분.
