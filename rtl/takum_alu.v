// =============================================================================
// takum_alu.v — ALU takum linear de N bits: soma, subtração e multiplicação
// -----------------------------------------------------------------------------
// Projeto Integrador AOC 2026/02 — Entrega 1
//
//   op = 2'd0  y = a + b
//   op = 2'd1  y = a - b
//   op = 2'd2  y = a * b
//
// Combinacional: takum_decoder (a, b) -> núcleo aritmético -> takum_encoder.
// O resultado é o arredondamento correto (vizinho mais próximo, empate para o
// par, na palavra) do valor exato, com saturação: nunca vira 0 nem NaR por
// estouro. NaR é absorvente em qualquer operação (inclusive 0 * NaR).
//
// Núcleo da multiplicação:  sinal = sa ^ sb ; exp = ea + eb ;
//   significandos {1,fa} * {1,fb} (2(N-4) bits), normaliza se >= 2.
//
// Núcleo da soma: ordena por magnitude, alinha o menor com guard/round/sticky
//   (o que sai do alinhamento vira um único bit sticky), soma ou subtrai,
//   normaliza (contador de zeros à esquerda) e entrega ao encoder.
//
// Parâmetro: N >= 8 (testado com 8, 16 e 32).
// =============================================================================
`timescale 1ns/1ps

module takum_alu #(
    parameter N = 16
) (
    input  wire [N-1:0] a,
    input  wire [N-1:0] b,
    input  wire [1:0]   op,
    output wire [N-1:0] y
);
    localparam W  = N - 4;           // largura do significando {1, frac}
    localparam EW = 11;              // largura do expoente que vai ao encoder
    localparam AW = W + 3;           // significando + guard, round, sticky
    localparam [9:0] AW10 = AW;
    localparam [5:0] AW6  = AW;

    wire [N-1:0] NAR = {1'b1, {(N-1){1'b0}}};

    // ---- decodificação --------------------------------------------------------
    wire              za, na, sa, zb, nb, sb_raw;
    wire signed [8:0] ea, eb;
    wire [N-6:0]      fa, fb;
    takum_decoder #(.N(N)) u_da (.t(a), .is_zero(za), .is_nar(na), .sign(sa),     .exp(ea), .frac(fa));
    takum_decoder #(.N(N)) u_db (.t(b), .is_zero(zb), .is_nar(nb), .sign(sb_raw), .exp(eb), .frac(fb));

    wire is_mul = (op == 2'd2);
    wire sb     = sb_raw ^ (op == 2'd1);          // subtração = soma com sinal de b invertido
    wire [W-1:0] ma = {1'b1, fa};
    wire [W-1:0] mb = {1'b1, fb};

    // ---- multiplicação ----------------------------------------------------------
    wire [2*W-1:0] prod   = ma * mb;
    wire           p_hi   = prod[2*W-1];          // produto >= 2
    wire [2*W-1:0] p_norm  = p_hi ? prod : (prod << 1);   // bit 1 na posição 2W-1
    wire signed [EW-1:0] m_exp = $signed({{2{ea[8]}}, ea}) + $signed({{2{eb[8]}}, eb}) + (p_hi ? 11'sd1 : 11'sd0);
    wire [N-4:0]   m_frac   = p_norm[2*W-2 -: N-3];
    wire           m_stk    = |p_norm[2*W-2-(N-3):0];
    wire           m_sign   = sa ^ sb_raw;

    // ---- soma / subtração ---------------------------------------------------------
    // ordem por magnitude: expoente e depois fração (ambos já normalizados)
    wire a_ge_b = ({~ea[8], ea[7:0], fa} >= {~eb[8], eb[7:0], fb});   // expoente com sinal: inverte o MSB
    wire signed [8:0] e_big   = a_ge_b ? ea : eb;
    wire signed [8:0] e_small = a_ge_b ? eb : ea;
    wire [W-1:0]      m_big   = a_ge_b ? ma : mb;
    wire [W-1:0]      m_small = a_ge_b ? mb : ma;
    wire              s_big   = a_ge_b ? sa : sb;
    wire              s_small = a_ge_b ? sb : sa;

    wire [9:0] dist = e_big - e_small;                       // 0 .. 509
    wire [9:0] dist_c = (dist > AW) ? AW10 : dist;

    wire [AW-1:0]   a_ext  = {m_big, 3'b000};
    wire [AW-1:0]   b_ext  = {m_small, 3'b000};
    wire [2*AW-1:0] b_wide = {b_ext, {AW{1'b0}}} >> dist_c;
    wire [AW-1:0]   b_al   = b_wide[2*AW-1:AW];
    wire            b_stk  = |b_wide[AW-1:0];                // bits que saíram do alinhamento
    wire [AW-1:0]   b_jam  = {b_al[AW-1:1], b_al[0] | b_stk};

    wire            sub    = s_big ^ s_small;
    wire [AW:0]     sum    = sub ? ({1'b0, a_ext} - {1'b0, b_jam}) : ({1'b0, a_ext} + {1'b0, b_jam});

    // contador de zeros à esquerda (priority encoder sobre AW+1 = N bits)
    reg [5:0] lz;
    integer i;
    always @* begin
        lz = AW6 + 6'd1;                                // sum == 0
        for (i = 0; i <= AW; i = i + 1)
            if (sum[i]) lz = AW6 - i[5:0];
    end
    wire [AW:0]   s_norm  = sum << lz;                       // bit 1 em AW
    wire signed [EW-1:0] a_exp = $signed({{2{e_big[8]}}, e_big}) + 11'sd1 - $signed({5'b0, lz});
    wire [N-4:0]  a_frac  = s_norm[AW-1 -: N-3];
    wire          a_stk   = |s_norm[AW-1-(N-3):0];
    wire          a_zero  = (sum == 0);

    // ---- encoder ---------------------------------------------------------------------
    wire              enc_zero = is_mul ? 1'b0 : a_zero;
    wire              enc_sign = is_mul ? m_sign : s_big;
    wire signed [EW-1:0] enc_exp = is_mul ? m_exp : a_exp;
    wire [N-4:0]      enc_frac = is_mul ? m_frac : a_frac;
    wire              enc_stk  = is_mul ? m_stk  : a_stk;
    wire [N-1:0]      y_core;
    takum_encoder #(.N(N)) u_enc (.is_zero(enc_zero), .is_nar(1'b0), .sign(enc_sign),
                                  .exp(enc_exp), .frac(enc_frac), .sticky(enc_stk), .t(y_core));

    // ---- casos especiais ------------------------------------------------------------------
    wire [N-1:0] b_signed = (op == 2'd1) ? (~b + 1'b1) : b;   // -b, em complemento de 2
    assign y = (na | nb)  ? NAR :
               is_mul     ? ((za | zb) ? {N{1'b0}} : y_core) :
               za         ? (zb ? {N{1'b0}} : b_signed) :
               zb         ? a :
                            y_core;
endmodule
