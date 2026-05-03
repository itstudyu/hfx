# Workers — 사용자 정의 에이전트

이 디렉토리에 워커 `.md` 파일을 추가하면 commander가 자동 발견합니다.

## 명명 규약

`<role>-<expertise>.md` (kebab-case)

예시: `frontend-developer.md`, `python-pro.md`, `db-architect.md`

## 필수 frontmatter

```yaml
---
name: <kebab-case>           # 파일명과 동일
description: "<영어 1~2 문장>. commander가 매칭에 사용하므로 명확하게."
tools: Read, Edit, Write, Bash, Glob, Grep    # 도메인별 조정
model: sonnet                # 또는 opus / haiku
maxTurns: 20
---
```

## 워커 본문 필수 섹션

1. **Core Identity** — 무엇을 하는 워커인가
2. **Self-Verification** — 작업 후 어떻게 검증할 것인가 (Karpathy: Goal-Driven)
3. **Negative Space** — 절대 하지 않는 것
4. **Output Format** — commander에게 무엇을 반환할지

## 언어

워커는 **영어로** 작성. (코드/도구가 영어 기반)

## 예시

이 디렉토리에 함께 배포된 [`example-worker.md`](example-worker.md) 참조 — 단순 구조의 모범. 새 워커 추가 시 이 파일을 복사한 후 4섹션을 도메인에 맞게 수정.

## 검증

워커 추가 후:
- `.claude/hooks/update-org-chart.sh` 가 자동 실행되어 `.hfx/org-chart.md` 갱신
- `/hfx --todos` 로 워커가 commander에 인식되는지 확인
