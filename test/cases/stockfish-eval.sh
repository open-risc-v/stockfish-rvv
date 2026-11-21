#!/usr/bin/env bash
# stockfish 真实包用例：静态评估（NNUE affine 全连接层）输出逐字节比。
set -euo pipefail
: "${STAGE:=run}" "${SIDE:=A}" "${BIN:=build/native}" "${DATA:=build/ab-data}" "${OUT:=build/ab-data/out}"
mkdir -p "$DATA" "$OUT"
CASE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
NET="$CASE_DIR/../../test/data/nn-bddd9d57eb87.nnue"
case "$STAGE" in
  gen) : > "$DATA/sf.ready" ;;
  run)
    SF="$BIN/tools/stockfish"
    [ -x "$SF" ] || { echo "缺少 $SF（该侧未构建）" >&2; exit 1; }
    printf 'setoption name EvalFile value %s\nposition fen r1bqkbnr/pppp1ppp/2n5/4p3/2B1P3/5N2/PPPP1PPP/RNBQK2R w KQkq - 2 3\neval\nquit\n' "$NET" \
      | ${RUNNER:-} "$SF" 2>&1 | grep -v "^Stockfish dev-" > "$OUT/eval.txt"
    ;;
esac
