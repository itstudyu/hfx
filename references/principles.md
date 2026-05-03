# hfx 핵심 원칙

`CLAUDE.md`가 import하는 행동 강령. 모든 에이전트와 스킬이 이를 따른다.

상세 출처는 [references/knowledge-pack/](knowledge-pack/INDEX.md) — 32개 자료 분석 (Anthropic 공식 + GitHub Tier 1~4).

---

## 1. Karpathy 4원칙 (무조건 준수)

출처: [forrestchang/andrej-karpathy-skills](https://github.com/forrestchang/andrej-karpathy-skills) ★107k

### Think Before Coding
가정 명시. 헷갈리면 멈춤. 트레이드오프 제시. 불확실하면 무조건 유저에게 질문.

### Simplicity First
- 200줄이 50줄이면 50줄로
- 시니어가 봐도 안 복잡한가?
- 추측에 의한 추상화 금지

### Surgical Changes
- 변경 라인은 사용자 요청에 직접 추적 가능
- 인접 코드 "개선" 금지
- orphan 정리만 (내가 만든 것만)

### Goal-Driven Execution
- 명령형 → 검증 가능한 목표형 변환
- "Add validation" → "테스트 작성 후 통과시켜라"
- 모든 plan.md에 `dod:` 필드 필수

---

## 2. PGE 패턴 (우리 구조)

- **Planner**: 계획만 작성. 한국어로 유저와 100% 합의 후 commander에 인계. 다른 에이전트 직접 호출 금지.
- **Commander**: 지휘만. 직접 코드 작성 금지. plan.md를 task별로 워커에 위임. 결과 통합.
- **Workers**: 격리된 sub-agent 컨텍스트에서 단일 task 수행. self-verify 의무.

---

## 3. Anthropic 원칙 (필수)

출처: [Building Effective Agents](https://www.anthropic.com/research/building-effective-agents)

- **Workflow vs Agent**: simplest first. 정해진 경로면 workflow.
- **Augmented LLM = building block**: Retrieval + Tools + Memory를 갖춘 LLM이 기본 단위.
- **Sub-agent로 컨텍스트 격리**: returns only the summary.
- **Tool 설계 우선순위 1**: tools are primary actions Claude considers.

---

## 4. 컨텍스트 관리

출처: [Building agents with the Claude Agent SDK](https://claude.com/blog/building-agents-with-the-claude-agent-sdk)

- 파일시스템 = 1차 외부 메모리 (`.hfx/tickets/`)
- vector embedding보다 grep/tail 기반 agentic search 선호
- sub-agent로 대형 context 격리
- planner는 모호한 요구 시 `references/knowledge-pack/INDEX.md` **만** 자동 참조 (개별 tier 파일은 grep 후 명시적으로만 읽기 — 컨텍스트 폭주 방지)

---

## 5. 안티패턴 (금지)

1. **자기 평가 편향**: Generator가 자기 코드를 리뷰. → 워커 self-verify + commander 통합.
2. **Kitchen sink 세션**: 무관한 task 혼합. → 티켓 1개에 1개 목표.
3. **메가세션**: 한 번에 다 해결. → sprint 단위 분해.
4. **검증 없는 "완료"**: 테스트 미실행. → dod 강제.
5. **무한 탐색**: 스코핑 없는 "investigate". → 명확한 boundaries.

---

## 6. 도구 권한 정책

- **Planner**: Read, Glob, Grep, Write/Edit (`.hfx/tickets/active/`만), Bash, AskUserQuestion. **Agent 금지**.
- **Commander**: Read, Glob, Grep, Bash, Agent, TodoWrite. **Edit, Write 금지**.
- **Workers**: 도메인별 (사용자 정의). self-verify 도구 필수.

권한은 frontmatter `tools:`, `disallowedTools:` 로 강제. 별도 훅 사용 금지 (Simplicity First).
