#!/usr/bin/env bash
# add → commit → push 를 한 번에 실행한다. (Git Bash에서 실행)
#
# 사용법
#   commit_script/commit.sh                      # .commit_msg/ 에서 가장 최근 메시지 파일 사용
#   commit_script/commit.sh 2026-11-04_xxx.txt   # 메시지 파일 지정
#
# 커밋에 쓴 메시지 파일은 .commit_msg/done/ 으로 옮겨서 다시 쓰이지 않게 한다.
set -euo pipefail

# 어디서 실행해도 프로젝트 루트에서 동작
cd "$(dirname "$0")/.."

MSG_DIR=".commit_msg"

if [ $# -ge 1 ]; then
  MSG="$MSG_DIR/$1"
  [ -f "$MSG" ] || MSG="$1"
else
  MSG="$(ls -t "$MSG_DIR"/*.txt 2>/dev/null | head -n 1 || true)"
fi

if [ -z "$MSG" ] || [ ! -f "$MSG" ]; then
  echo "❌ 커밋 메시지 파일이 없어요. $MSG_DIR/ 에 .txt 파일을 만들어 주세요."
  exit 1
fi

git add -A

if git diff --cached --quiet; then
  echo "ℹ️  커밋할 변경사항이 없어요."
  exit 0
fi

echo "📝 메시지 파일: $MSG"
echo "   제목: $(head -n 1 "$MSG")"
git commit -F "$MSG"

mkdir -p "$MSG_DIR/done"
mv "$MSG" "$MSG_DIR/done/"

git push
echo "✅ add / commit / push 완료"
