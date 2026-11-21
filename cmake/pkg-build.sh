set -euo pipefail
SRC=$1
OUT=$2
MARCH=${3:-rv64gc}
KERN=${4:-0}
mkdir -p "$OUT/tools" "$OUT/prefix"
rm -rf "$OUT/pkgsrc"
cp -R "$SRC" "$OUT/pkgsrc"
F="-O3 -std=c++17 -march=${MARCH}"
if [ "$KERN" = "1" ]; then
  F="$F -DRVV_KERNELS=1"
fi
# stockfish 的 Makefile 会对 ARCH=general-64 追加 -m64，riscv gcc 不认；
# 命令行变量会屏蔽 Makefile 里的 += 追加，所以 CXXFLAGS/LDFLAGS 都用命令行传。
make -C "$OUT/pkgsrc/src" build ARCH=general-64 -j"$(nproc)" \
  CXXFLAGS="$F" LDFLAGS="-O3 -march=${MARCH}" > "$OUT/build.log" 2>&1 \
  || { tail -30 "$OUT/build.log"; exit 1; }
cp "$OUT/pkgsrc/src/stockfish" "$OUT/tools/stockfish"
