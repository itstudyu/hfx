#!/usr/bin/env bash
# PostToolUse hook — workers/ 변경 감지 시 .hfx/org-chart.md 자동 갱신
set -euo pipefail

INPUT=$(cat)
CHANGED=$(echo "$INPUT" | python3 -c "import json,sys; d=json.load(sys.stdin); print(d.get('toolInput',{}).get('file_path',''))" 2>/dev/null || echo "")

case "$CHANGED" in
  *.claude/agents/workers/*.md) ;;
  *) exit 0 ;;
esac

mkdir -p .hfx
WORKERS=$(ls -1 .claude/agents/workers/*.md 2>/dev/null | grep -vE '(README\.md|\.gitkeep|\.DS_Store)' | xargs -n1 basename | sed 's/\.md$//' || echo "")

{
  echo "# Org Chart (auto-generated)"
  echo ""
  echo "Last update: $(date -u +%Y-%m-%dT%H:%M:%SZ)"
  echo ""
  echo '```mermaid'
  echo "graph LR"
  echo "    User([👤 User])"
  echo "    Planner[📋 Planner]"
  echo "    Commander[🎯 Commander]"
  i=1
  for w in $WORKERS; do echo "    W$i[⚙️ $w]"; i=$((i+1)); done
  echo "    User -->|/hfx| Planner"
  echo "    Planner <-->|확인 질문| User"
  echo "    Planner -->|plan.md| Commander"
  i=1
  for w in $WORKERS; do
    echo "    Commander -->|Agent| W$i"
    echo "    W$i -->|summary| Commander"
    i=$((i+1))
  done
  echo "    Commander -->|보고| User"
  echo "    style Commander fill:#fdd"
  echo "    style Planner fill:#dfd"
  echo '```'
} > .hfx/org-chart.md

exit 0
