#!/usr/bin/env bash
# stockfish 的 A/B：真机（GCC 15 才有新 intrinsic）编两侧 + bench 比节点数。
#
# 为什么不用容器：stockfish 的 RVV 代码用了较新的 intrinsic（vnclipu 等），
# GCC 13.3 的 riscv_vector.h 只有 masked 形式，编不过；镜像里也只有 g++-13。
# 真机 Bianbu 的 g++ 15.2 可以编。
#
# 为什么两侧都带 -march=rv64gcv：上游只有 ARCH=riscv64-rva23 才开 -DUSE_RVV，
# 而它同时加 zba/zbb/zbs/zicbop/zicond，直接对比会差多个变量。
# 这里手工固定 march，让 A/B 唯一差别是 -DUSE_RVV。
#
# 用法（在真机上，源码已就位）：
#   ./scripts/stockfish-ab.sh /root/sf/src
set -euo pipefail
SRC=${1:?用法: stockfish-ab.sh <stockfish 源码目录>}
cd "$SRC"
NPROC=$(nproc)

MARCH="-march=rv64gcv -O3"

echo "== B 侧（无 USE_RVV）"
make objclean >/dev/null 2>&1 || true
make -j"$NPROC" ARCH=riscv64 COMP=gcc CXX=g++ CXXFLAGS="$MARCH" build > /tmp/sf-b.log 2>&1 \
  || { echo "BUILD FAIL (off)"; tail -20 /tmp/sf-b.log; exit 1; }
cp -f stockfish stockfish_off

echo "== A 侧（USE_RVV）"
make objclean >/dev/null 2>&1 || true
make -j"$NPROC" ARCH=riscv64 COMP=gcc CXX=g++ CXXFLAGS="$MARCH -DUSE_RVV" build > /tmp/sf-a.log 2>&1 \
  || { echo "BUILD FAIL (on)"; tail -25 /tmp/sf-a.log; exit 1; }

echo "== 二进制"
stat -c '%n %s bytes' stockfish stockfish_off

# bench 的 limit 是 depth。depth 太大会在标量侧跑很久：off 只有 ~8.4k nps，
# depth 14 单线程要 5 分钟。要快就用 8，要稳就用 14。
DEPTH=${DEPTH:-14}
echo "== bench off (depth $DEPTH)"
./stockfish_off bench 1 1 "$DEPTH" 2>&1 | tail -3
echo "== bench on (depth $DEPTH)"
./stockfish bench 1 1 "$DEPTH" 2>&1 | tail -3
echo "== 注意：两侧 Nodes searched 必须完全相同，这才是功能位精确的证据"
