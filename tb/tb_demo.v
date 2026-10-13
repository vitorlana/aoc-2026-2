// =============================================================================
// tb_demo.v — Demonstração para VER AS ONDAS (GTKWave)
// -----------------------------------------------------------------------------
// Não é um teste de aprovação: percorre casos escolhidos a dedo, um a cada
// 10 ns, e grava build/demo.vcd.
//
//   Parte 1 (0–110 ns):   T8  t -> decoder -> encoder -> t_back
//   Parte 2 (120–200 ns): T8  encoder sozinho, mostrando arredondamento,
//                             empate para o par, vai-um entre regimes e saturação
//
// O sinal "caso" é um texto (abra em GTKWave com formato ASCII) que diz o que
// está sendo mostrado em cada intervalo.
//
//   make waves        gera build/demo.vcd e abre no GTKWave com tb/demo.tcl
// =============================================================================
`timescale 1ns/1ps
module tb_demo;
    localparam N = 8;

    reg [8*24:1] caso;                      // texto de até 24 caracteres

    // ---------------- Parte 1: decoder -> encoder ----------------
    reg  [N-1:0]      t;
    wire              is_zero, is_nar, sign;
    wire signed [8:0] exp;
    wire [N-6:0]      frac;
    wire [N-1:0]      t_back;

    takum_decoder #(.N(N)) dec (.t(t), .is_zero(is_zero), .is_nar(is_nar),
                                .sign(sign), .exp(exp), .frac(frac));
    takum_encoder #(.N(N)) enc (.is_zero(is_zero), .is_nar(is_nar), .sign(sign),
                                .exp({{2{exp[8]}}, exp}), .frac({frac, 2'b00}),
                                .sticky(1'b0), .t(t_back));

    // sinais internos do cabeçalho, para ver na onda
    wire [2:0]  r = dec.r;                  // nº de bits de característica
    wire [11:0] h = dec.h;                  // cabeçalho de 12 bits (com ghost bits)

    // ---------------- Parte 2: encoder com arredondamento ----------------
    reg               e_sign, e_sticky;
    reg signed [10:0] e_exp;
    reg [N-4:0]       e_frac;               // 3 bits de fração + guard + round
    wire [N-1:0]      e_t;

    takum_encoder #(.N(N)) enc_r (.is_zero(1'b0), .is_nar(1'b0), .sign(e_sign),
                                  .exp(e_exp), .frac(e_frac), .sticky(e_sticky), .t(e_t));
    wire guard = enc_r.guard;               // bit guard visto pelo encoder
    wire rnd   = enc_r.rnd;                 // 1 = somou 1 na palavra

    task show_dec; input [8*24:1] s; input [N-1:0] x;
        begin caso = s; t = x; #10; end
    endtask
    task show_enc; input [8*24:1] s; input sg; input integer e; input [N-4:0] f; input st;
        begin caso = s; e_sign = sg; e_exp = e; e_frac = f; e_sticky = st; #10; end
    endtask

    initial begin
        $dumpfile("build/demo.vcd");
        $dumpvars(0, tb_demo);
        t = 0; e_sign = 0; e_exp = 0; e_frac = 0; e_sticky = 0;

        // Parte 1
        show_dec("1",              8'h40);
        show_dec("1,125",          8'h41);
        show_dec("2",              8'h48);
        show_dec("8",              8'h50);
        show_dec("2^15",           8'h60);
        show_dec("0,9375",         8'h3F);
        show_dec("-1 (neg)",       8'hC0);
        show_dec("maior 2^239",    8'h7F);
        show_dec("menor 2^-239",   8'h01);
        show_dec("zero",           8'h00);
        show_dec("NaR",            8'h80);
        caso = "---"; t = 8'h40; #10;

        // Parte 2: frac = {3 bits de fração, guard, round}
        show_enc("1,0 exato",          0,    0, 5'b000_00, 0);
        show_enc("1,0625 empate->par", 0,    0, 5'b000_10, 0);   // fica 1,0
        show_enc("1,1875 empate->par", 0,    0, 5'b001_10, 0);   // sobe p/ 1,25
        show_enc("1,0625+sticky ->up", 0,    0, 5'b000_10, 1);   // sobe p/ 1,125
        show_enc("1,96 vai-um ->2",    0,    0, 5'b111_11, 0);   // muda regime
        show_enc("-1,1875 sinal",      1,    0, 5'b001_10, 0);
        show_enc("exp 300 satura",     0,  300, 5'b000_00, 0);
        show_enc("exp -300 satura",    0, -300, 5'b000_00, 0);
        caso = "fim"; #10;
        $finish;
    end
endmodule
