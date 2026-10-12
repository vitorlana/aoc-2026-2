// =============================================================================
// tb_encoder.v — Verifica takum_encoder por PROPRIEDADES (sem codificador de
// referência), usando só ref_value do modelo:
//   1. resultado positivo nunca é 0 nem NaR (saturação)
//   2. trocar o sinal da entrada dá o complemento de 2 da saída
//   3. acima do maior / abaixo do menor positivo -> satura no maior / menor
//   4. x fica entre os vizinhos (t-1, t+1) da saída
//   5. a saída é o vizinho mais próximo (região de arredondamento aritmético;
//      em T8 só para 2^-15 <= |x| < 2^16, veja o guia §7.5)
//   6. empates exatos vão para o padrão par (RNE na palavra)
//   + casos dirigidos (zero, NaR, faixa de expoente)
//   Opções: +NENC=<quantidade aleatória por tamanho> (padrão 100000)
// =============================================================================
`timescale 1ns/1ps
module enc_check #(parameter N = 16, parameter SEED = 1) ();
    `include "takum_ref.vh"

    localparam NF = N - 3;                           // bits de frac na entrada
    localparam [N-1:0] MAXPOS = {1'b0, {(N-1){1'b1}}};
    localparam [N-1:0] MINPOS = {{(N-1){1'b0}}, 1'b1};
    localparam [N-1:0] NAR    = {1'b1, {(N-1){1'b0}}};

    reg               is_zero, is_nar, sticky;
    reg signed [10:0] exp;
    reg [NF-1:0]      frac;
    wire [N-1:0]      t_pos, t_neg;

    takum_encoder #(.N(N)) e_pos (.is_zero(is_zero), .is_nar(is_nar), .sign(1'b0),
                                  .exp(exp), .frac(frac), .sticky(sticky), .t(t_pos));
    takum_encoder #(.N(N)) e_neg (.is_zero(is_zero), .is_nar(is_nar), .sign(1'b1),
                                  .exp(exp), .frac(frac), .sticky(sticky), .t(t_neg));

    integer errors = 0, checks = 0;
    reg done = 0;

    task fail;
        input [8*40-1:0] what;
        real xr;
        begin
            errors = errors + 1;
            if (errors <= 20)
                $display("ERRO T%0d %0s: exp=%0d frac=%h sticky=%b -> t=%h (%e)",
                         N, what, exp, frac, sticky, t_pos, ref_value(t_pos, N));
        end
    endtask

    // valor exato da entrada (sticky = "um pouco" abaixo do bit round)
    function real input_value;
        input integer e; input [NF-1:0] fr; input st;
        real f;
        begin
            f = fr;
            input_value = (1.0 + (f + (st ? 0.5 : 0.0)) / $pow(2.0, NF)) * $pow(2.0, e);
        end
    endfunction

    real vmax, vmin, x, v, vlo, vhi;
    integer i, count, seed, e_int;
    reg arith;

    task check_props;
        begin
            #1; checks = checks + 1;
            x = input_value(exp, frac, sticky);
            // 1. nunca 0 nem NaR, sempre positivo
            if (t_pos == 0 || t_pos[N-1]) fail("saida invalida");
            // 2. simetria de sinal
            if (t_neg !== (~t_pos + 1'b1)) fail("simetria de sinal");
            // 3. saturação
            if (x >= vmax) begin
                if (t_pos !== MAXPOS) fail("saturacao no maior");
            end else if (x <= vmin) begin
                if (t_pos !== MINPOS) fail("saturacao no menor");
            end else begin
                v   = ref_value(t_pos, N);
                vlo = (t_pos == MINPOS) ? 0.0  : ref_value(t_pos - 1'b1, N);
                vhi = (t_pos == MAXPOS) ? vmax : ref_value(t_pos + 1'b1, N);
                // 4. x entre os vizinhos
                if (x < vlo || x > vhi) fail("fora da vizinhanca");
                // 5. vizinho mais próximo (região aritmética)
                e_int = exp;
                arith = (N > 8) || (e_int >= -15 && e_int <= 15);
                if (arith) begin
                    if ((v - x) * (v - x) > (vlo - x) * (vlo - x) ||
                        (v - x) * (v - x) > (vhi - x) * (vhi - x)) fail("nao e o mais proximo");
                end
            end
        end
    endtask

    integer s_, d_, r_, c_, p_, k;
    reg [31:0] fb_;
    reg [N-1:0] t0;
    reg [31:0] rnd;
    initial begin
        seed = SEED;
        vmax = ref_value(MAXPOS, N);
        vmin = ref_value(MINPOS, N);
        is_zero = 0; is_nar = 0; sticky = 0; exp = 0; frac = 0;

        // ---- casos especiais ----
        is_zero = 1; #1; checks = checks + 1;
        if (t_pos !== 0 || t_neg !== 0) fail("zero");
        is_zero = 0; is_nar = 1; #1; checks = checks + 1;
        if (t_pos !== NAR || t_neg !== NAR) fail("NaR");
        is_nar = 0;

        // ---- faixa de expoente (dirigidos) ----
        exp =  11'sd400; frac = 0;          sticky = 0; check_props;
        exp =  11'sd255; frac = 0;          sticky = 0; check_props;
        exp =  11'sd254; frac = {NF{1'b1}}; sticky = 1; check_props;
        exp = -11'sd255; frac = 0;          sticky = 0; check_props;
        exp = -11'sd256; frac = 0;          sticky = 0; check_props;
        exp = -11'sd400; frac = 0;          sticky = 0; check_props;
        exp =  11'sd0;   frac = 0;          sticky = 0; check_props;  // 1.0

        // ---- aleatórios ----
        if (!$value$plusargs("NENC=%d", count)) count = 100000;
        for (i = 0; i < count; i = i + 1) begin
            exp    = $random(seed) % 271;          // -270 .. 270
            rnd    = $random(seed);
            frac   = rnd[NF-1:0];
            sticky = $random(seed);
            check_props;
        end

        // ---- empates exatos: ponto médio entre t0 e t0+1 ----
        sticky = 0;
        for (i = 0; i < count / 10; i = i + 1) begin
            rnd = $random(seed);
            t0  = rnd[N-1:0] & MAXPOS;              // positivo
            if (t0 != 0 && t0 != MAXPOS) begin
                ref_fields(t0, N, s_, d_, r_, c_, p_, fb_);
                // ref_fields conta os ghost bits quando N < 12; aqui queremos
                // só os bits de fração que existem na palavra de N bits
                if (N < 12) begin
                    p_  = p_ - (12 - N);
                    fb_ = fb_ >> (12 - N);
                end
                // só onde o próximo padrão está a 2^(c-p) (região aritmética)
                if (p_ >= 1 && (N > 8 || r_ <= 2)) begin
                    exp  = c_;
                    frac = (fb_ << (NF - p_)) | ({{(NF-1){1'b0}}, 1'b1} << (NF - p_ - 1));
                    #1; checks = checks + 1;
                    if (t_pos !== (t0[0] ? t0 + 1'b1 : t0)) begin
                        errors = errors + 1;
                        if (errors <= 20)
                            $display("ERRO T%0d empate t0=%h: obtido %h", N, t0, t_pos);
                    end
                end
            end
        end

        if (errors == 0) $display("PASS encoder T%0d: %0d verificações", N, checks);
        else             $display("FAIL encoder T%0d: %0d erros em %0d verificações", N, errors, checks);
        done = 1;
    end
endmodule

module tb_encoder;
    enc_check #(.N(8),  .SEED(7))  c8  ();
    enc_check #(.N(16), .SEED(8))  c16 ();
    enc_check #(.N(32), .SEED(9))  c32 ();
    initial begin
        wait (c8.done && c16.done && c32.done);
        $finish;
    end
endmodule
