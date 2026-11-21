# 上游接入：stockfish（自带 Makefile，不走 CMake）。两侧各从自己的 SRC_DIR 编一份，
# 产物落到 <build>/tools/stockfish，用例按 $BIN/tools/stockfish 调用。
if(NOT DEFINED PKG_PREFIX)
  add_custom_target(pkg ALL
    COMMAND "${CMAKE_CURRENT_SOURCE_DIR}/cmake/pkg-build.sh" "${SRC_DIR}" "${CMAKE_BINARY_DIR}" "${RVV_MARCH}" "$<IF:$<BOOL:${RVV_KERNELS}>,1,0>"
    COMMENT "构建上游 stockfish（${SRC_DIR}）"
    VERBATIM)
  set(HAVE_PKG_TARGET TRUE)
endif()
