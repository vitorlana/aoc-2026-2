// =============================================================================
// takum_vec_alu.v — Unidade vetorial Zvtakum: vtadd.vv, vtsub.vv, vtmul.vv
// -----------------------------------------------------------------------------
// Projeto Integrador AOC 2026/02 — Entrega 1
//
// Aplica a operação elemento a elemento sobre um registrador vetorial de VLEN
// bits, com elementos de SEW = 8, 16 ou 32 bits (T8, T16, T32):
//
//   vd[i] = vs2[i] (op) vs1[i]     para i < vl
//   vd[i] = vd_old[i]              para i >= vl   (cauda inalterada)
//
//   sew  2'd0 = 8 bits, 2'd1 = 16 bits, 2'd2 = 32 bits
//   op   2'd0 = vtadd.vv, 2'd1 = vtsub.vv (vs2 - vs1), 2'd2 = vtmul.vv
//
// Há uma fileira de ALUs por largura (VLEN/8 de T8, VLEN/16 de T16, VLEN/32 de
// T32) e um multiplexador por SEW. É a forma mais simples e não a menor em área;
// máscaras (v0.t), LMUL e CSRs ficam para a integração com o modelo RVV.
// Elemento 0 nos bits menos significativos (little-endian), como no RVV.
// =============================================================================
`timescale 1ns/1ps

module takum_vec_alu #(
    parameter VLEN = 64
) (
    input  wire [VLEN-1:0] vs2,
    input  wire [VLEN-1:0] vs1,
    input  wire [VLEN-1:0] vd_old,
    input  wire [1:0]      op,
    input  wire [1:0]      sew,
    input  wire [7:0]      vl,        // nº de elementos ativos
    output wire [VLEN-1:0] vd
);
    wire [VLEN-1:0] r8, r16, r32;

    genvar i;
    generate
        for (i = 0; i < VLEN/8; i = i + 1) begin : g8
            takum_alu #(.N(8)) u (.a(vs2[8*i +: 8]), .b(vs1[8*i +: 8]), .op(op), .y(r8[8*i +: 8]));
        end
        for (i = 0; i < VLEN/16; i = i + 1) begin : g16
            takum_alu #(.N(16)) u (.a(vs2[16*i +: 16]), .b(vs1[16*i +: 16]), .op(op), .y(r16[16*i +: 16]));
        end
        for (i = 0; i < VLEN/32; i = i + 1) begin : g32
            takum_alu #(.N(32)) u (.a(vs2[32*i +: 32]), .b(vs1[32*i +: 32]), .op(op), .y(r32[32*i +: 32]));
        end
    endgenerate

    wire [VLEN-1:0] res = (sew == 2'd0) ? r8 : (sew == 2'd1) ? r16 : r32;

    // máscara de elementos ativos: i < vl
    reg [VLEN-1:0] act;
    integer k, w;
    always @* begin
        w = (sew == 2'd0) ? 8 : (sew == 2'd1) ? 16 : 32;
        for (k = 0; k < VLEN; k = k + 1)
            act[k] = ((k / w) < vl);
    end

    assign vd = (res & act) | (vd_old & ~act);
endmodule
