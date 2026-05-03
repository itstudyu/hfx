---
name: factory
description: "harness-factory 메인 진입점. /factory <요구>로 새 작업 시작. planner가 한국어로 100% 유저 합의 후 commander에 인계, commander가 워커들에게 격리된 sub-agent 컨텍스트로 위임. /factory --todos로 오늘/내일 할 일 표시. 첫 호출 시 참조 문서(docs/structure.md 등) 부트스트랩."
when_to_use: 사용자가 새 기능 추가, 버그 수정, 리팩토링, 또는 '오늘/내일 할 일'을 요청할 때
allowed-tools: Agent, Read, Glob, Grep, Bash, AskUserQuestion
model: opus
---

# /factory — harness-factory 메인 진입점

## 트리거

```
/factory <자연어 요구>      새 작업 시작
/factory --todos            오늘/내일 할 일 표시
/factory --refs             참조 문서 매핑 재설정 (보조)
```

## Step 0. 부트스트랩 (첫 호출 시 자동 감지)

`.claude/agents/planner-refs.yaml`을 읽고 `bootstrapped: false`이면 **planner 호출 전 1회만** 실행:

1. 한국어로 안내: "planner가 매 작업 시 참조할 문서를 등록합니다."
2. **AskUserQuestion 1**: `docs/structure.md`를 default로 추가? (예/아니오, 권장: 예)
3. **AskUserQuestion 2**: 추가로 등록할 문서? (없음 / 1~2개 / 3개 이상)
4. 추가 있으면 path와 role을 텍스트로 받음 (예: `docs/coding-rule.md` = `coding-conventions`)
5. **AskUserQuestion 3**: 각 문서 로드 모드 (always / conditional / manual)
6. `planner-refs.yaml` 갱신 (`bootstrapped: true`, `user-defined`에 항목 추가)
7. `docs/structure.md`가 없으면 commander → docs-keeper에 "초기 생성" task 위임 (codebase 스캔 후 생성)
8. "설정 완료" 보고 후 **원래 요구를 planner에 전달**

`/factory --refs`는 부트스트랩을 강제 재실행 (yaml 직접 편집도 가능).

## Step 1. Planner 호출

```
Agent(description="새 작업 계획", subagent_type="planner",
      prompt="<유저 요구>\n참조: planner-refs.yaml의 auto-load:always 항목 모두 읽고 시작하라")
```

planner가:
1. `planner-refs.yaml` 로드 → `auto-load: always` 문서 모두 Read
2. 코드베이스 탐색 + knowledge-pack INDEX (모호 시)
3. AskUserQuestion으로 100% 합의
4. `.hfx/tickets/active/YYYY-MM-DD-<slug>/plan.md` 작성 (status: ready, `references:` 필드에 사용한 문서 기록)

## Step 2. Commander 호출

```
Agent(description="계획 실행", subagent_type="commander",
      prompt="@.hfx/tickets/active/<id>/plan.md 의 계획을 실행해줘")
```

commander가:
1. plan.md 읽고 status.md 생성
2. workers/ 스캔, task 매칭 → Agent로 워커 호출 (병렬/순차)
3. **모든 코드 task 완료 후**: 자동으로 docs-keeper 1회 호출 (마지막 단계)
4. artifacts/ 저장, status: done, `done/`으로 이동
5. 유저에게 한국어 보고

## --todos 모드

```bash
ls .hfx/tickets/active/*/status.md
ls .hfx/tickets/backlog/*/plan.md
grep "^$(date +%Y-%m-%d)" .hfx/log.md
```

출력:
```
## 📋 오늘 (YYYY-MM-DD)
### 진행 중
- [ ] <ticket-id> (<status>, <progress>)
### 오늘 한 일
- HH:MM <action>
## 📅 내일 (backlog)
- <ticket-id> (priority)
```

## 워커 없음 처리

commander가 적합 워커 못 찾으면:
1. 유저 보고: "이 task에 맞는 워커가 없습니다."
2. 안내: "`workers/example-worker.md` 복사해서 4섹션 수정. 도메인 사례는 `references/knowledge-pack/tier-1-essential/voltagent-subagents.md` (131+ 워커)"
3. 사용자가 추가 후 `/factory <원래 요구>` 재실행

## 실패 시

- planner 실패: 즉시 보고, 티켓 미생성
- commander 실패: status: blocked, 보고
- 워커 실패: commander가 즉시 보고 (재시도 X)
- docs-keeper 실패: 코드 task는 done 처리, docs-keeper 실패만 분리 보고 (블록 X)

## 활동 로그

`.hfx/log.md` append-only (commander 자동 처리).

## 원칙

`@references/principles.md` — Karpathy 4원칙 무조건 준수.
