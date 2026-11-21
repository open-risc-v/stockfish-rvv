// RVV 内核：NNUE 全连接层（int8 权重 * uint8 输入 -> int32 累加）。
// 逐元素乘 + 整数累加，整数加法可结合，改变累加顺序不改变结果，故与标量实现位精确。
#ifndef SF_AFFINE_RVV_H
#define SF_AFFINE_RVV_H
#include <riscv_vector.h>

template<int InputDimensions, int PaddedInputDimensions, int OutputDimensions>
inline void rvv_affine_transform(int32_t* output, const int8_t* weights, const int32_t* biases, const uint8_t* input)
{
    for (int i = 0; i < OutputDimensions; ++i)
    {
        const int8_t* row = weights + i * PaddedInputDimensions;
        vint32m4_t acc = __riscv_vmv_v_x_i32m4(0, __riscv_vsetvlmax_e32m4());
        int k = 0;
        while (k < InputDimensions)
        {
            size_t vl = __riscv_vsetvl_e8m1((size_t)(InputDimensions - k));
            vint8m1_t  w8 = __riscv_vle8_v_i8m1(row + k, vl);
            vuint8m1_t x8 = __riscv_vle8_v_u8m1(input + k, vl);
            vint16m2_t w16 = __riscv_vwadd_vx_i16m2(w8, 0, vl);
            vuint16m2_t x16u = __riscv_vwaddu_vx_u16m2(x8, 0u, vl);
            vint16m2_t  x16  = __riscv_vreinterpret_v_u16m2_i16m2(x16u);
            vint32m4_t prod = __riscv_vwmul_vv_i32m4(w16, x16, vl);
            acc = __riscv_vadd_vv_i32m4(acc, prod, vl);
            k += (int)vl;
        }
        vint32m1_t sum = __riscv_vredsum_vs_i32m4_i32m1(acc, __riscv_vmv_v_x_i32m1(0, 1), __riscv_vsetvlmax_e32m4());
        output[i] = (int32_t)__riscv_vmv_x_s_i32m1_i32(sum) + biases[i];
    }
}
#endif
