---
name: hfx-upgrade
description: "hfx 자체를 최신 표준으로 업그레이드. references/knowledge-pack의 32개 자료 분기 갱신, 변경된 Anthropic 표준 반영. 90일 초과 시 자동 제안."
when_to_use: 분기 1회, 또는 Anthropic이 새 frontmatter 필드/패턴/모델 발표 시, 또는 사용자가 명시적으로 요청 시
allowed-tools: Read, Glob, Grep, Bash, WebFetch, Edit, Write
model: opus
---

# /hfx-upgrade

## 트리거 조건

1. 사용자가 명시적으로 `/hfx-upgrade` 호출
2. `references/knowledge-pack/LOG.md`의 마지막 갱신이 90일 초과
3. Anthropic blog/docs에 새 항목 (수동 모니터링)

## 동작 순서

### Step 1. 갱신 필요 여부 점검

```bash
last=$(grep -m1 "## 20" references/knowledge-pack/LOG.md | awk '{print $2}')
days=$(( ($(date +%s) - $(date -j -f "%Y-%m-%d" "$last" +%s)) / 86400 ))
echo "$days days since last update"
```

90일 초과 시 사용자에게 보고: "knowledge-pack 갱신이 필요합니다. 진행할까요?"

### Step 2. 갱신 모드 진입 (사용자 승인 후)

각 자료별로:
1. **★수 갱신**: `gh repo view <repo> --json stargazerCount`
2. **신규 항목 체크**: 분기 동안 추가된 자료 (Tier 1~4 후보)
3. **공식 문서 변경**: WebFetch로 frontmatter 필드 변경 감지

### Step 3. INDEX.md, LOG.md 갱신

LOG.md에 새 entry append:

```markdown
## YYYY-MM-DD — Quarterly update (vX.Y)

**Operator**: claude-opus-4-7
**Trigger**: 90 days since v1.0

### Updated
- T1#1 (awesome-claude-code): ★42.3k → ★XX.Xk

### Added
- (신규 자료 있을 때)

### Removed / Deprecated
### Insights
```

### Step 4. 우리 룰에 영향 있는 변경 보고

예: `permissionMode` 신규 값 추가, frontmatter 필드 변경 등.

사용자에게 보고:
```
다음 변경이 hfx에 영향:
1. <변경 내용>
2. 권장 액션: <적용 방법>
적용할까요?
```

## 절대 안 하는 것

- ❌ 자동으로 우리 .claude/ 파일 수정 — 사용자 승인 필수
- ❌ knowledge-pack 외부 파일 임의 변경
- ❌ 90일 미만 시 강제 갱신

## 출력

`references/knowledge-pack/LOG.md` 에 새 entry 추가. 변경 요약을 사용자에게 한국어로 보고.
