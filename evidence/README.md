# 2026-10-24 Linux 실측 원본 증거

Codyssey 제공 `agent-leak-app-x86` SHA-256 `7e0a19cfa80ece6b547a5008273661f0d4d71e526e96b51e0d0f341dd1bb3e40`을 Linux x86_64의 **non-root 사용자**로 실행했다. 모든 시간은 UTC다. 바이너리와 ZIP은 커밋하지 않았다.

| 디렉터리 | 실험 |
| --- | --- |
| [`oom-before`](oom-before/) / [`oom-after`](oom-after/) | `MEMORY_LIMIT=256` vs `512`; CPU 40/멀티스레드 false 고정 |
| [`cpu-before`](cpu-before/) / [`cpu-after`](cpu-after/) | `CPU_MAX_OCCUPY=80` vs `40`; 메모리 512/멀티스레드 false 고정 |
| [`deadlock-before`](deadlock-before/) / [`deadlock-after`](deadlock-after/) | `MULTI_THREAD_ENABLE=true` vs `false`; 메모리 512/CPU 40 고정 |

각 폴더의 파일:
- `settings.txt`: 실행 매개변수, 시작 시각, 바이너리 해시
- `application.log`: 앱 표준 출력/표준 오류(보호 정책/락 상태 결정적 근거)
- `agent-logs/agent_app.log`: 앱 자체 로그, 별도로 보존
- `monitor.tsv`: `timestamp_utc`, `pid`, `state`, `rss_mib`, `cpu_pct` 원본; PID별 약 1초 간격
- `processes.txt`: 시점별 `ps` PID·PPID·PGID·TID·WCHAN 및 `ss` 리스너
- `result.txt`: 앱 자체 종료(`app_exit`) / 관찰 제한 종료(`observation_limit`), 종료 코드, 종료 시각

**주의:** `CPU_MAX_OCCUPY=80`에서 앱 내부 `Current Load`가 52.07%에 도달한 사실은 OS CPU 52% 점유를 뜻하지 않는다. `observation_limit` 후 코드 143은 실험기가 보낸 SIGTERM이므로 장애 종료 증거가 아니다.
