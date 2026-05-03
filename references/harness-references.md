# Harness Design References

이 문서는 v2 [`principles.md`](principles.md)와 [`knowledge-pack/`](knowledge-pack/INDEX.md)이 인용하는 원본 소스의 상세 분석을 담는다.
각 섹션 번호는 v1 시절 출처 각주 번호 `[n]`을 그대로 유지한다 (knowledge-pack의 tier 분류와 매칭).
갱신은 `/hfx-upgrade` 스킬로 수행한다 (분기 1회 또는 새 표준 발표 시).

## ⭐ Knowledge Pack — 외부 레퍼런스 (NEW 2026-05-03)

v2 [`principles.md`](principles.md)가 참조하는 핵심 출처를 보강하는 **20개 GitHub repo + 12개 공식 문서** 분석.

→ **[knowledge-pack/INDEX.md](knowledge-pack/INDEX.md)** 에서 시작.

```
knowledge-pack/
├── INDEX.md          # 카탈로그 (Tier 1~4 + 공식 문서)
├── LOG.md            # append-only 변경 이력
├── tier-1-essential/   (4개, ★ 합계 222.8k)
├── tier-2-strong/      (4개, ★ 합계 84.6k)
├── tier-3-supporting/  (5개, ★ 합계 191.4k)
├── tier-4-inspiration/ (7개, ★ 합계 287.6k)
└── official-docs/      (12개, Anthropic + Claude Code Docs)
```

**`/hfx-upgrade`가 진단·patch·검수 시 1차 참조 자료**.

분기 1회 갱신. 변경은 `LOG.md`에 append-only 기록.

---

## [1] Anthropic: Managed Agents
**URL**: https://www.anthropic.com/engineering/managed-agents

### 검증된 인용
- *"We virtualized the components of an agent: a session (the append-only log of everything that happened), a harness (the loop that calls Claude and routes Claude's tool calls), and a sandbox"*
- *"The solution we arrived at was to decouple what we thought of as the 'brain' (Claude and its harness) from both the 'hands' (sandboxes and tools)"*
- *"We're opinionated about the shape of these interfaces, not about what runs behind them."*

### 성능 수치 (원문 확인)
- p50 TTFT 약 60% 감소, p95 90% 이상 감소 (Lazy provisioning 관련 컨텍스트에서 언급)

### 적용 규칙
- 3계층 가상화 (session / harness / sandbox)
- brain / hands 분리 → 인증 정보 격리
- 도구 인터페이스는 "shape만 고정" — 내부 구현 무관

### 도구 인터페이스 API (원문 확인)
- `execute(name, input) → string` (도구 실행)
- `provision({resources})` (샌드박스 초기화)
- `wake(sessionId)` (하네스 복구)
- `getSession(id)` (이벤트 로그 조회)
- `emitEvent(id, event)` (세션 이벤트 기록)

### 검증 실패 (이전 오류)
- "Evaluator drift 감지, 연속 PASS 10회 임계값" → 본문 없음 (제거)

---

## [2] Anthropic: Effective Harnesses for Long-Running Agents
**URL**: https://www.anthropic.com/engineering/effective-harnesses-for-long-running-agents

### 검증된 인용
- *"agents need a way to bridge the gap between coding sessions"*
- *"a feature list file... expanded on the user's initial prompt"*
- *"leave clear artifacts for the next session"*

### 실제 구성
- **Initializer agent**: 초기 환경 설정
- **Coding agent**: 점진적 진행
- `claude-progress.txt` + git 히스토리로 세션 간 상태 복구

### 적용 규칙
- 명확한 세션 간 핸드오프 산출물
- 기능 목록 파일 사용 (형식 무관, 현재 rules는 JSON 주장 제거)

### 검증 실패 (이전 오류)
- "Harness=OS, Model=CPU, Context=RAM" 메타포 → 본문 없음 (제거)
- "wake(sessionId) / getEvents()" API → 본문 없음 (제거)
- "TTFT 60-90% 감소" 수치 → 본문이 아닌 Managed Agents에 있음 (이동)

---

## [3] Anthropic: Building Effective Agents
**URL**: https://www.anthropic.com/research/building-effective-agents

### 검증된 인용
- Workflow vs Agent: *"LLMs and tools follow predefined code paths"* vs *"LLMs dynamically direct their own processes and tool usage"*
- Evaluator-Optimizer: *"One LLM call generates a response while another provides evaluation and feedback in a loop"*
- Orchestrator-Workers: *"A central LLM dynamically breaks down tasks, delegates them to worker LLMs, and synthesizes their results"*
- 원칙: *"Start with simple prompts, optimize them with comprehensive evaluation, and add multi-step agentic systems only when simpler solutions fall short."*

### 다섯 가지 프로덕션 패턴
1. Prompt Chaining
2. Routing
3. Parallelization (sectioning / voting)
4. Orchestrator-Workers
5. Evaluator-Optimizer

### 빌딩 블록
- **Augmented LLM** = Retrieval + Tools + Memory
- 도구 문서화는 프롬프트 엔지니어링만큼 중요

### 적용 규칙
- PGE는 Evaluator-Optimizer 패턴에 해당 (Generator ↔ Evaluator 루프)
- hfx 스킬은 Orchestrator, 3개 에이전트는 Workers

---

## [4] Anthropic: Prompt Caching
**URL**: https://platform.claude.com/docs/en/docs/build-with-claude/prompt-caching
(이전 `docs.anthropic.com/en/docs/build-with-claude/prompt-caching`은 301로 redirect됨)

### 검증된 수치 (2026-04 기준 공식)
- 캐시 읽기 = 기본 입력가 × 0.1 (= 10%)
- 5분 TTL 쓰기 = × 1.25 (125%)
- 1시간 TTL 쓰기 = × 2.0 (200%)
- 최대 cache breakpoint = 4개
- 자동 lookback window = 20 블록

### 최소 캐시 토큰 (모델별)
- Claude Mythos Preview / Opus 4.7 / 4.6 / 4.5 / Haiku 4.5 / Haiku 3: 4096
- Sonnet 4.6 / Haiku 3.5: 2048
- Sonnet 4.5 / Opus 4.1 / Opus 4 / Sonnet 4 / Sonnet 3.7: 1024

### Cache prefix 생성 순서
`tools → system → messages` (원문 그대로)

### 캐시 무효화 상세 (2026-04 기준)
- 도구 정의 변경 → tools/system/messages 전체 무효화
- web search 토글, citations 토글, speed 설정 변경 → system/messages만 보존
- tool choice, images, extended thinking 설정 변경 → messages만 보존

### Workspace isolation
- 2026-02-05부터 캐시는 organization → workspace 단위로 격리 (Claude API & Azure AI Foundry)

### 적용 규칙
- SessionStart hook은 messages 계층에 주입되므로 rules 본문을 넣으면 캐시가 자주 무효화됨 → 현재는 해시만 주입, 본문은 CLAUDE.md의 `@import`로 system 계층에 포함
- 도구 정의는 세션 중 변경 금지

---

## [5] Claude Code: Sub-agents
**URL**: https://code.claude.com/docs/en/sub-agents

### 공식 지원 frontmatter 필드 (2026-04-18 기준)
`name` (필수), `description` (필수), `tools`, `disallowedTools`, `model`, `permissionMode`, `maxTurns`, `skills`, `mcpServers`, `memory`, `background`, `effort`, `isolation`, `color`, `initialPrompt`, `hooks`

### CLI 정의 sub-agent (`--agents` flag)
- `--agents` JSON으로 세션 한정 sub-agent 정의 가능 (디스크 미저장)
- `prompt` key = 파일 기반의 markdown body와 동일
- 우선순위: Managed > CLI (`--agents`) > Project > User > Plugin
- `CLAUDE_CODE_SUBAGENT_MODEL` env로 전역 모델 오버라이드

### 신규/확장 필드 상세
- `skills`: 스킬 전체 내용을 startup에 프리로드 (Level 2 content 즉시 주입)
- `mcpServers`: 특정 sub-agent에 MCP 서버 스코핑 (inline 또는 reference)
- `memory`: `user` | `project` | `local` → MEMORY.md 자동 생성, 200행/25KB 자동 로드
- `background`: true → 백그라운드 태스크로 실행
- `effort`: `low` | `medium` | `high` | `xhigh` | `max` (모델에 따라 가용 레벨 상이)
- `color`: red | blue | green | yellow | purple | orange | pink | cyan
- `initialPrompt`: `--agent`로 메인 세션 실행 시 자동 제출되는 첫 턴

### 빌트인 sub-agent 3종
- **Explore**: Haiku, 읽기 전용, thoroughness levels (quick/medium/very thorough)
- **Plan**: 모델 상속, 읽기 전용, plan-mode research
- **General-purpose**: 전체 도구, 복잡한 멀티스텝

### permissionMode 값
`default` | `acceptEdits` | `auto` | `dontAsk` | `bypassPermissions` | `plan`
- **`plan`은 read-only exploration** — Bash 등 실행 도구 불가
- `auto` 모드에서 sub-agent frontmatter의 permissionMode는 무시됨 — parent classifier가 결정

### 도구 리네임
- **`Task` → `Agent`** (v2.1.63). 기존 `Task(...)` 참조는 alias로 계속 동작.
- `Agent(worker, researcher)` 문법으로 spawnable sub-agent를 제한할 수 있다.

### /agents 커맨드
- 인터랙티브 UI로 sub-agent 생성·편집·삭제 가능 (Running / Library 탭)
- `claude agents` CLI로 비인터랙티브 리스트 출력

### disallowedTools 우선순위
- `tools`와 `disallowedTools` 모두 설정 시 `disallowedTools`가 먼저 적용 → 남은 풀에서 `tools` 해석

### Frontmatter 훅 스코핑
- Frontmatter hooks는 Agent 도구 또는 @-mention으로 spawn될 때만 발화
- `--agent`로 메인 세션 실행 시에는 발화하지 않음 (session-wide hooks는 settings.json에 설정)

### 주의
- **`role:` 필드는 공식 스펙에 없음** — 커스텀 필드는 무시됨
- `isolation: worktree`는 대상이 **현재 repo**일 때만 의미 — 변경이 없으면 자동 정리
- Plugin sub-agent에서 `hooks`, `mcpServers`, `permissionMode`는 보안상 무시

### 적용 규칙
- PGE 역할은 description 태그로 (`[planner]` / `[generator]` / `[evaluator]`)
- Evaluator에 `permissionMode: plan`을 주지 않는다 — Bash 기반 rubric이 실패

---

## [6] Claude Code: Hooks
**URL**: https://code.claude.com/docs/en/hooks

### 4종 훅 핸들러 (2026-04-18 기준)
- **command**: 기존 shell 스크립트 (bash/python). stdin JSON, exit code 제어. `async` 필드로 백그라운드 실행 가능. `asyncRewake` 필드로 백그라운드 실행 후 exit 2 시 Claude 재기동.
- **http**: POST endpoint. non-2xx = non-blocking error; 2xx + decision JSON으로 차단.
- **prompt**: LLM 평가. prompt 템플릿 + model 필드.
- **agent**: Sub-agent 검증. model 필드 선택 가능.

### 공식 hook 이벤트 (30종 전체 목록)
`SessionStart`, `SessionEnd`, `UserPromptSubmit`, `PreToolUse`, `PostToolUse`, `PostToolUseFailure`, `PermissionRequest`, `PermissionDenied`, `Notification`, `Stop`, `StopFailure`, `SubagentStart`, `SubagentStop`, `TaskCreated`, `TaskCompleted`, `InstructionsLoaded`, `ConfigChange`, `CwdChanged`, `FileChanged`, `WorktreeCreate`, `WorktreeRemove`, `PreCompact`, `PostCompact`, `Elicitation`, `ElicitationResult`, `TeammateIdle`

### 추가 환경변수
- `$CLAUDE_PLUGIN_DATA`: 플러그인 persistent data 디렉토리
- `$CLAUDE_CODE_REMOTE`: 웹 환경에서 `"true"` 설정

Matcher patterns: pipe-separated (`Bash|Edit`), event별 의미 차이 (예: `SessionStart` matches `startup`/`resume`/`clear`/`compact`).

### 입력 규약
- **입력은 stdin JSON으로만 전달** — `$TOOL_INPUT_FILE_PATH`는 **존재하지 않음**
- 단, `$CLAUDE_ENV_FILE`은 SessionStart 훅에서 세션 환경변수 영속에 사용 가능 (공식)
- 기타 공식 env: `$CLAUDE_PROJECT_DIR`, `${CLAUDE_PLUGIN_ROOT}`, `${CLAUDE_PLUGIN_DATA}`, `$CLAUDE_CODE_REMOTE`
- 공통 필드: `session_id`, `cwd`, `hook_event_name`, `permission_mode`, `tool_name`, `tool_input`, `tool_response`, `agent_type`, `agent_id`, `transcript_path`

### Exit code 의미
- `0`: 통과 (SessionStart/UserPromptSubmit은 stdout이 context로 주입)
- `2`: 차단 + stderr가 Claude에 피드백
- 기타: non-blocking error (공식 문서 경고: "exit 1은 차단하지 않으므로 정책 시행에는 exit 2 사용")

### PreToolUse 확장
- `updatedInput`: 도구 입력을 실행 전 수정 가능 (allow/deny 외 제3옵션)
- `defer` permissionDecision: 외부 UI 대기 후 SDK로 재개
- `updatedPermissions`: 훅이 세션 권한을 동적 변경 (addRules/replaceRules/removeRules/setMode)

### PostToolUse 확장
- `decision: "block"` + `reason`: 도구 실행 결과를 차단하고 사유를 Claude에 피드백
- `updatedMCPToolOutput`: MCP 도구 출력을 대체값으로 교체

### PermissionDenied 확장
- `retry: true`: auto mode에서 거부된 도구 호출을 재시도 허용

### 추가 필드
- `if`: 권한 규칙 필터 (`"Bash(git *)"`, `"Edit(*.ts)"`) — 조건부 훅 발화
- `once`: 세션당 1회만 실행 (skills 전용)
- `statusMessage`: 훅 실행 중 커스텀 스피너 메시지
- `asyncRewake`: 백그라운드 비동기 훅, exit 2로 Claude 재기동
- `disableAllHooks: true`: settings에서 모든 훅 비활성화

### 적용 규칙
- bash/python 훅 모두 `cat` / `json.load(sys.stdin)`으로 입력 수신
- PostToolUse에서 file_path가 필요하면 `.tool_input.file_path` 추출

---

## [7] Claude Code: Skills
**URL**: https://code.claude.com/docs/en/skills

### 공식 frontmatter 필드 (2026-04-18 기준, 전체)
`name`, `description`, `when_to_use`, `argument-hint`, `disable-model-invocation`, `user-invocable`, `allowed-tools`, `model`, `effort`, `context` (`fork`), `agent`, `hooks`, `paths`, `shell`

### 신규/확장 필드 상세
- `when_to_use`: description에 합산, 자동 트리거 조건 보충. 합산 1,536자 cap.
- `user-invocable: false`: `/` 메뉴에서 숨김, Claude 자동 호출만 가능
- `context: fork`: 격리된 sub-agent에서 실행. skill 내용이 sub-agent 프롬프트가 됨
- `agent`: `context: fork` 시 사용할 sub-agent 타입 (Explore, Plan, general-purpose, 또는 커스텀)
- `paths`: glob 패턴. 매칭 파일 작업 시만 자동 활성화
- `hooks`: 스킬 라이프사이클에 스코핑된 훅
- `shell`: `bash` (기본) 또는 `powershell`. `CLAUDE_CODE_USE_POWERSHELL_TOOL=1` 필요
- `effort`: `low` | `medium` | `high` | `xhigh` | `max` (세션 effort 레벨 오버라이드)

### 문자열 치환
- `$ARGUMENTS`, `$ARGUMENTS[N]` / `$N` (0-based), `${CLAUDE_SESSION_ID}`, `${CLAUDE_SKILL_DIR}`

### Shell injection
- `` !`command` `` 또는 ` ```! ` 블록: 렌더 시점에 즉시 실행, 출력이 프롬프트에 주입
- `disableSkillShellExecution: true` settings로 비활성화 가능

### Skill content lifecycle
- 호출된 스킬은 세션 끝까지 conversation에 잔류
- Auto-compaction 후: 가장 최근 호출 스킬부터 각 5,000토큰, 합산 25,000토큰 예산 내 재부착

### Skills는 Agent Skills 오픈 표준(agentskills.io)을 따른다.
Custom commands(`.claude/commands/`)는 skills로 통합. 기존 commands 파일은 계속 동작.

### 파일 위치 우선순위
Enterprise > Personal (`~/.claude/skills/`) > Project (`.claude/skills/`) > Plugin (`plugin-name:skill-name` namespace)

### 적용 규칙
- 파괴적 슬래시 커맨드에는 `disable-model-invocation: true`
- SKILL.md는 500라인 이하 권장, 큰 참조 자료는 별도 파일로 분리
- `description` + `when_to_use` 합산 1,536자 초과 시 skill 리스트에서 잘림. 핵심 용도를 앞에 배치.
- 총 예산은 context window의 1%, fallback 8,000자. `SLASH_COMMAND_TOOL_CHAR_BUDGET` env로 조정.
- Live change detection: 스킬 디렉토리 변경 시 세션 재시작 없이 즉시 반영 (단 신규 top-level 디렉토리 생성은 재시작 필요)
- Nested discovery: 모노레포에서 `packages/frontend/.claude/skills/` 자동 검색

---

## [8] Claude Code: Best Practices
**URL**: https://code.claude.com/docs/en/best-practices
(`www.anthropic.com/engineering/claude-code-best-practices`는 308로 여기로 redirect)

### 검증된 인용
- *"Include tests, screenshots, or expected outputs so Claude can check itself. This is the single highest-leverage thing you can do."*
- *"Claude's context window fills up fast, and performance degrades as it fills."*
- *"If you've corrected Claude more than twice on the same issue in one session, the context is cluttered with failed approaches. Run `/clear` and start fresh with a more specific prompt that incorporates what you learned."*
- *"Would removing this cause Claude to make mistakes? If not, cut it."* (CLAUDE.md 간결성 테스트)

### 워크플로우
Explore → Plan → Code → Commit (4단계)

### 추가 패턴 (2026-04 확인)
- `/btw`: 컨텍스트에 남지 않는 사이드 질문 (dismissible overlay)
- `/rewind`: 대화·코드 체크포인트 복원 또는 특정 메시지부터 요약
- Writer/Reviewer 패턴: 별도 세션으로 코드 작성 ↔ 리뷰 분리 → 자기 평가 편향 방지
- `--permission-mode auto -p`: 비대화형 실행 시 classifier 기반 자동 승인, 반복 차단 시 abort
- 플러그인 (`/plugin`): skills·hooks·subagents·MCP를 번들로 설치

### 적용 규칙
- **2회 실패 후 컨텍스트 초기화** 규칙의 **정식 출처는 여기** (이전에는 Hashimoto로 잘못 매핑되어 있었음)
- CLAUDE.md 간결성 테스트의 출처

---

## [9] Mitchell Hashimoto: My AI Adoption Journey
**URL**: https://mitchellh.com/writing/my-ai-adoption-journey

### 검증된 인용
- *"the agent must have the ability to: read files, execute programs, and make HTTP requests"*
- *"If you give an agent a way to verify its work, it more often than not fixes its own mistakes"*
- *"Break down sessions into separate clear, actionable tasks. Don't try to 'draw the owl' in one mega session"*
- *"Harness Engineering"*: 에이전트 오류마다 재발방지 시스템을 구축

### 적용 규칙
- 최소 4가지 능력 (파일 읽기 / 실행 / HTTP / 검증)
- Sprint 단위 작업
- AGENTS.md / 유사 파일로 세션 간 문서화

### 검증 실패 (이전 오류)
- "Initializer vs Executor 에이전트 분리" → 본문 없음 (제거)
- "Red/Green 테스트 우선" → 본문 없음 (제거)
- "2회 실패 후 컨텍스트 초기화" → 본문 없음. 출처는 [8]로 이동

---

## [10] Lilian Weng: LLM Powered Autonomous Agents
**URL**: https://lilianweng.github.io/posts/2023-06-23-agent/

### 검증된 인용
- ReAct 패턴: *"Thought: ... Action: ... Observation: ... (Repeated many times)"*
- 3대 구성요소: **Planning**, **Memory** (short-term / long-term with MIPS like HNSW/FAISS), **Tool Use**
- Self-reflection: Reflexion, Chain of Hindsight

### 적용 규칙
- ReAct 루프의 **원형**은 Thought-Action-Observation 3단계
- 현재 rules는 5단계(`READ→PLAN→ACT→OBSERVE→CHECKPOINT`) 주장을 철회하고 이 3단계 원형으로 복원

---

---

## [11] Claude Code: Orchestrate teams of Claude Code sessions
**URL**: https://code.claude.com/docs/en/agent-teams

### 검증된 인용
- *"Agent teams let you coordinate multiple Claude Code instances working together. One session acts as the team lead, coordinating work, assigning tasks, and synthesizing results."*
- *"Agent teams are experimental and disabled by default. Enable them by adding `CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS` to your settings.json or environment."*
- Requires Claude Code v2.1.32+

### Sub-agents vs Agent Teams (공식 비교)
|  | Subagents | Agent teams |
|---|---|---|
| Communication | Report to main agent only | Teammates message each other |
| Coordination | Main agent manages | Shared task list, self-coordination |
| Best for | Focused tasks where only the result matters | Complex work requiring discussion |
| Token cost | Lower (summarized back) | Higher (each is separate Claude) |

### Best use cases
- Research and review (여러 teammate가 다각도 투입)
- New modules / features (각자 다른 부분 담당)
- Debugging with competing hypotheses (scientific debate 구조)
- Cross-layer coordination (frontend/backend/tests)

### Architecture 구성요소
| Component | Role |
|---|---|
| Team lead | 메인 세션, 팀 생성·teammate 소환·작업 조율 |
| Teammates | 독립 Claude Code 인스턴스 |
| Task list | 공유 작업 리스트 (pending/in_progress/completed, dependency 지원) |
| Mailbox | 에이전트 간 메시징 |

### 저장 경로
- Team config: `~/.claude/teams/{team-name}/config.json`
- Task list: `~/.claude/tasks/{team-name}/`

### 한계
- In-process teammate는 `/resume`·`/rewind` 복원 안 됨
- Teammate가 task completed 마킹을 놓쳐 의존 task가 막히는 경우 있음
- Lead 승격·변경 불가, nested team 불가, 세션당 1팀
- tmux / iTerm2 없으면 split-pane 불가 (VS Code / Windows Terminal / Ghostty 비지원)

### 적용 규칙
- PGE 같은 sequential 루프는 sub-agent 유지
- 향후 "다각 리뷰 / 경합 가설 조사" 기능 추가 시 agent team 고려

---

## [12] Anthropic: Equipping agents for the real world with Agent Skills
**URL**: https://claude.com/blog/equipping-agents-for-the-real-world-with-agent-skills
(`www.anthropic.com/engineering/equipping-agents-for-the-real-world-with-agent-skills`는 308로 redirect)

### 검증된 인용
- *"Progressive disclosure is the core design principle that makes Agent Skills flexible and scalable."*
- *"organized folders of instructions, scripts, and resources that agents can discover and load dynamically to perform better at specific tasks"*
- *"Like a well-organized manual that starts with a table of contents, then specific chapters, and finally a detailed appendix."*

### Progressive Disclosure 3 레벨
- **Level 1 — Metadata**: `name` + `description`만 startup에 로드
- **Level 2 — Core Context**: 관련 태스크 시 `SKILL.md` 본문 로드
- **Level 3+ — Granular Details**: 필요 시점에만 외부 참조 파일

### Skill 설계 3대 원칙
1. **Start with evaluation** — 실제 태스크에서 에이전트가 막히는 지점을 관찰
2. **Structure for scale** — SKILL.md 비대해지면 별도 파일 분리, mutually-exclusive 컨텍스트 분리
3. **Think from Claude's perspective** — `name`·`description`이 자동 트리거이므로 특별히 관리

### 적용 규칙
- rules 3장에 Progressive Disclosure 추가
- SKILL.md 500라인 이하 권장, 초과 시 분리

---

## [13] Anthropic: Building agents with the Claude Agent SDK
**URL**: https://claude.com/blog/building-agents-with-the-claude-agent-sdk
(`www.anthropic.com/engineering/building-agents-with-the-claude-agent-sdk`는 308로 redirect)

### 검증된 인용
- Canonical loop: *"gather context -> take action -> verify work -> repeat."*
- *"giving Claude a computer unlocks the ability to build agents that are more effective than before."*
- *"Tools are prominent in Claude's context window, making them the primary actions Claude will consider."*
- *"Code is precise, composable, and infinitely reusable."*

### Agent Loop 3단계
1. **Gather context** — agentic search via bash, semantic search, subagents, context compaction
2. **Take action** — tools, bash/scripts, code generation, MCP integrations
3. **Verify work** — rules-based feedback (linting), visual feedback, LLM judging

### Context Management 원칙
- 파일시스템 구조를 "a form of context engineering"으로 활용
- 초기엔 vector embedding보다 `grep`/`tail` agentic search 선호
- Sub-agent로 대형 context 격리
- 토큰 임계 근접 시 자동 compaction

### 적용 규칙
- rules 2장에 공식 gather-act-verify 루프 추가
- rules 3장에 "Tools as primary operations"·"Code as Output" 추가
- rules 5장에 agentic search 선호 원칙 추가

---

## [14] Anthropic: Code execution with MCP
**URL**: https://www.anthropic.com/engineering/code-execution-with-mcp

### 검증된 인용
- *"Tool descriptions occupy more context window space, increasing response time and costs."*
- 10,000행 스프레드시트 필터링 사례: *"reducing from 150,000 tokens to 2,000 tokens... a time and cost saving of 98.7%"*

### 핵심 주장
- 모든 MCP 도구 정의를 upfront 로드하면 (a) context bloat, (b) intermediate 결과가 context를 2회 왕복 → 비효율
- 대안: MCP 서버를 code API로 노출 (`./servers/google-drive/getDocument.ts` 같은 파일 구조) → 에이전트가 필요한 것만 탐색·로드

### 하네스 설계 3원칙
1. **Progressive disclosure** — 도구를 upfront 전부가 아니라 on-demand
2. **Privacy-preserving** — 중간 결과는 실행 환경에만, 명시적 반환만 모델로
3. **State persistence** — 중간 결과를 파일로 저장해 resume·재사용

### 적용 규칙
- rules 5장에 Code Execution with MCP 토큰 절감 원칙 추가
- 큰 데이터 처리 도구는 파일 저장 + 요약 반환 패턴 채택

---

## [15] Community Harness Repositories (보조 사례)

공식 출처와 충돌 시 공식 우선. 본 섹션은 **본문 직접 검증된 항목만** 등재한다.

### 등재 기준 (모두 충족)
- 본문(README/SKILL.md) WebFetch 또는 직접 clone 확인 완료
- ★ 1k+ / OSS 라이선스 / 식별 가능한 메인테이너
- 공식 문서로 환원되지 않는 **고유한 개념**을 제공할 것

### 15.1 revfactory/harness
**URL**: https://github.com/revfactory/harness
**확인 일자**: 2026-04-18 (WebFetch)
- ★ 2.6k / Apache-2.0 / Claude Code 플러그인 형태 meta-skill
- README가 정형화한 **6가지 아키텍처 패턴**: Pipeline, Fan-out/Fan-in, Expert Pool, Producer-Reviewer, Supervisor, Hierarchical Delegation
- 적용 시사점: hfx의 PGE는 Producer-Reviewer 변형으로 매핑 가능

> 본 repo의 A/B 수치(49.5→79.3) 등 성능 주장은 **외부 재현 없음** — rules에는 인용하지 않는다.

### 등재 후보 (본문 미검증, 인용 금지)
다음 repo들은 검색 결과 description만 확인한 상태. rules에 인용하려면 먼저 본문 검증 필요:
- `hesreallyhim/awesome-claude-code` — 큐레이션 리스트 (1차 탐색 진입점으로만 사용)
- `anthropics/skills` — Anthropic 공식 (skills.sh 인스톨 카운트로 인기 확인)
- `affaan-m/everything-claude-code`, `SethGammon/Citadel`, `wshobson/agents`, `trailofbits/skills`, `langchain-ai/langchain-skills`

### 검증 정책
- rules로 인용 시 **commit SHA + 직접 인용한 줄 번호** 기록
- archived / 90일 무활동 → 다음 `/hfx-upgrade` 실행 시 제거

---

## 추가 소스 (미검증 or 보조)

### Simon Willison
주요 URL 2개는 404 응답. 현재 rules에서 제거. 추후 WebSearch로 유효 URL 확인 후 재등록.

### MorphLLM: Agent Engineering Primer
URL·본문 재검증 필요. 현재 rules에는 포함하지 않음.

### Anthropic: 2026 Agentic Coding Trends Report (PDF)
`resources.anthropic.com/hubfs/2026%20Agentic%20Coding%20Trends%20Report.pdf` — 통계·예측 report. 현재 rules에 반영하지 않음 (근거 원칙 중심).

### Anthropic: Building a C compiler with agents
`www.anthropic.com/engineering/building-c-compiler` — 16 agents / 2,000 세션 사례. case study이므로 출처 각주에서 제외.

---

## 신뢰할 수 있는 소스 판단 기준

1. **공식 문서**: anthropic.com, platform.claude.com, code.claude.com, docs.anthropic.com
2. **검증된 개인 블로그**: Mitchell Hashimoto, Simon Willison, Lilian Weng, Andrej Karpathy 등
3. **메이저 AI 기업 엔지니어링 블로그**: OpenAI, Google DeepMind, DeepSeek 공식
4. **피어 리뷰 / 인용 100회 이상 논문**: arXiv
5. **메이저 컨퍼런스 발표**: NeurIPS, ICML, ICLR 등
6. **검증된 GitHub repo** ([15] 참조): ★ 100+ / 90일 내 활동 / OSS 라이선스 / 식별 가능한 메인테이너. 공식 문서와 충돌 시 공식 우선.

**제외**: 익명 블로그, 광고성 콘텐츠, 미검증 Twitter 스레드, 3개월 이상 경과한 beta 관련 자료, ★ 100 미만 fork-only repo.

---

## 갱신 이력

| 날짜 | 변경 내용 |
|------|----------|
| 2026-04-13 | 초기 작성 — 7개 URL + 2개 추가 소스 분석 |
| 2026-04-13 | v2.0 재검증 — 7개 URL + 공식 hooks/skills/settings 4종 원문 대조 후 오매핑 5건 제거, 출처 각주 시스템 도입 |
| 2026-04-14 | v2.1 — 새 공식 출처 4종 추가: [11] Agent Teams, [12] Agent Skills blog, [13] Claude Agent SDK, [14] Code Execution with MCP. Progressive disclosure / gather-act-verify / code-based orchestration 원칙 rules에 반영 |
| 2026-04-16 | v2.2 — 14개 URL 전수 재검증(12개 CHANGED, 2개 UNCHANGED). Hooks 4종 핸들러·updatedInput·$CLAUDE_ENV_FILE, Sub-agent 신규 필드 8종·Task→Agent 리네임·빌트인 3종, Skills Agent Skills 오픈 표준화·신규 필드·문자열 치환·shell injection·content lifecycle, Caching automatic/1h TTL, Agent Teams plan approval·task locking·신규 훅 3종, Best Practices /rewind·auto mode·plugins·/btw 반영 |
| 2026-04-17 | v2.2.1 — 14개 URL 재검증. Caching: Opus 4.7 추가(4096), Haiku 3 최소 토큰 2048→4096 수정. Sub-agents: --agents CLI flag·CLAUDE_CODE_SUBAGENT_MODEL env·우선순위 체계. Hooks: $CLAUDE_PLUGIN_DATA env 추가. Best Practices: Writer/Reviewer 패턴·/btw 상세화 |
| 2026-04-18 | v2.3 — [15] Community Harness Repositories 섹션 신설. 본문 직접 검증된 revfactory/harness만 등재(★ 2.6k, Apache-2.0, 6가지 아키텍처 패턴). 나머지 7개는 "후보(인용 금지)"로만 기록. 판단 기준 6번 추가 |
| 2026-04-18 | v2.3.1 — 15개 URL 재검증. [1] Managed Agents 도구 인터페이스 5종 API 복원. [4] Caching Mythos Preview 모델·캐시 무효화 상세 테이블·workspace isolation. [5] Sub-agents effort xhigh·/agents 커맨드·disallowedTools 우선순위·frontmatter 훅 스코핑. [6] Hooks async 필드·PostToolUse block decision·PermissionDenied retry. [7] Skills effort xhigh·argument-hint·shell 확장 |
