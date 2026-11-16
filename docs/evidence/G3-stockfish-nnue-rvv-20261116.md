# stockfish：上游自带 RVV，NNUE 15.5×

**日期**：2026-11-16
**上游**：`official-stockfish/Stockfish` @ `5d03b6e578a5eedc822e4563bdbb89e762fc2a59`
**真机**：SpacemiT K3 / Bianbu，`riscv64`，8 核 16 GB，g++ 15.2.0
**NNUE**：`nn-bddd9d57eb87.nnue`（138 MB，sha256 前 12 位与文件名一致）

## 1. 结论

| 侧 | 编译选项 | Total time | Nodes searched | Nodes/second |
|---|---|---|---|---|
| off | `-march=rv64gcv -O3` | 300347 ms | **2531901** | 8429 |
| on | `-march=rv64gcv -O3 -DUSE_RVV` | **19387 ms** | **2531901** | 130597 |

**15.5× 加速，且 `Nodes searched` 逐位相同**——这是"功能完全一致 + 性能大幅提升"的最强证据形态：
搜索树一个节点都没变，说明 RVV 只改了 NNUE 的数值计算通路，没有改变任何语义。

## 2. 为什么 off 侧只有 8429 nps

这个数字低得反常（K3 单核跑标量 C 的其他负载通常在 0.5–1 M 量级）。原因不是编译没优化，而是
**NNUE 在没有 `USE_RVV`/`USE_AVX2`/`USE_NEON` 时走纯标量循环**：

`nnue/simd.h` 的 `#elif defined(USE_RVV)` 分支决定是否引入 `<riscv_vector.h>`，整组
`vec_load / vec_add_16 / vec_mulhi_16` 宏在 `#ifdef USE_RVV` 之下才成立。没有它，
accumulator 的 tile 更新退化成逐元素操作——而 NNUE 增量更新正是 Stockfish 的绝对热点。

所以 15.5× **不是**"RVV 比标量常见水平快 15 倍"，而是"这个包在 riscv 上只有两条路：
标量（极慢）或 RVV（正常）"。这也说明该包对 RVV 的依赖度是所有已移植包里最高的。

## 3. A/B 的变量控制

上游的 RVV 开关藏在一个容易误用的地方：`Makefile:877`

```make
ifeq ($(rva23),yes)
	CXXFLAGS += -march=rv64gcv1p0_zba_zbb_zbs_zicbop_zicond -DUSE_RVV
endif
```

而 `rva23=yes` 只在 `ARCH=riscv64-rva23` 时成立。如果直接用
`ARCH=riscv64`（无 RVV）对 `ARCH=riscv64-rva23`（有 RVV），**两侧的 `-march` 差了一整套
zba/zbb/zbs/zicbop/zicond 扩展**，结论不可用。

正确做法是绕开这个 ARCH 分支，手工给两侧同一份 march：

```
CXXFLAGS="-march=rv64gcv -O3"                  # off
CXXFLAGS="-march=rv64gcv -O3 -DUSE_RVV"        # on
```

`Makefile` 的 `Section 3.1` 会把外部 `CXXFLAGS` 收进 `ENV_CXXFLAGS` 再拼到 `CXXFLAGS`，
所以这条路径是官方支持的。

另外 `-march=rv64gcv1p0` 这种写法不要照抄：`v1p0` 后缀在 GCC 13/15 上都不认，直接用 `rv64gcv`。

## 4. 构建环境：必须真机 GCC 15，容器 GCC 13 编不过

镜像 `rvv-cross:2/3` 里只有 `riscv64-linux-gnu-g++-13`（13.3.0），编 `-DUSE_RVV` 时报：

```
no known conversion for argument 1 from 'vuint16m2_t' to 'vbool8_t'
candidate: 'vuint16m2_t __riscv_vnclipu(vbool8_t, vuint32m4_t, ...)'
```

即 GCC 13 的 `riscv_vector.h` 只有 **masked** 形式的 `vnclipu`，没有 stockfish 用的
unmasked 形式。这与 eigen 那次是同一类问题（RVV10 代码需要更新的 intrinsic 面），
结论也一样：**这类包要在真机原生编，不要在容器里硬啃**。

## 5. 一个构建坑：NNUE 文件

`make` 的依赖链里有 `net` 目标 → `scripts/net.sh` → 需要 `wget` 或 `curl`。
容器里两个都没有，报 `Neither wget or curl is installed`。

而 `net.sh` 的校验逻辑很巧：文件名本身就是 sha256 前 12 位（`nn-bddd9d57eb87.nnue`），
所以**手工下载到源码目录后，`net` 会 validate 通过并跳过下载**，不需要容器里有 curl。

文件 138 MB，不要入库：已在 `.gitignore` 加 `src/src/*.nnue`。

另一个坑是目录结构：`scripts/net.sh` 在**仓库根的 `scripts/`**，不在 `src/scripts/`。
只打包 `src/` 传到真机会导致 `../scripts/net.sh: No such file`，要连 `scripts/` 一起传。

## 6. 复现

```bash
# 真机上，源码在 /root/sf/src
./scripts/stockfish-ab.sh /root/sf/src
DEPTH=8 ./scripts/stockfish-ab.sh /root/sf/src     # 快速版
```

判据两条同时成立：
1. 两侧 `Nodes searched` 完全相同；
2. on 侧 `Nodes/second` 显著更高。

## 7. 后续

- 本轮只做了 `bench 1 1 14`（单线程）。8 线程 depth 16 那组在 off 侧太慢（标量 8.4k nps，
  `bench 8 64 16` 跑了 15 分钟 CPU 仍未结束），已中止；要跑多线程数据得先把 off 侧的
  depth 调小。
- `ARCH=riscv64-universal`（运行时分发）没试，它是 A/B 之外的另一条路径。
- 下一步可以看 `nnue/layers/affine_transform.h:367` 的 RVV 分支是否还有按 VLEN 调 tile 宽度的空间。
