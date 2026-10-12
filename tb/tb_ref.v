// =============================================================================
// tb_ref.v — Testa o PRÓPRIO modelo de referência antes de usá-lo como gabarito
//   * valores conhecidos (revisão bibliográfica, livro de Gustafson §13.4)
//   * negação: valor(-t) == -valor(t)           (T8 e T16, todos os padrões)
//   * monotonicidade: valor cresce com o inteiro com sinal (T8 e T16)
// =============================================================================
`timescale 1ns/1ps
module tb_ref;
    `include "takum_ref.vh"

    integer errors = 0, checks = 0;

    task expect_val;
        input [31:0] t; input integer n; input real want;
        real got;
        begin
            got = ref_value(t, n); checks = checks + 1;
            if (got != want) begin
                errors = errors + 1;
                $display("ERRO ref_value(%h, n=%0d) = %e, esperado %e", t, n, got, want);
            end
        end
    endtask

    integer n, k, half;
    reg [31:0] t, tn;
    real v, vn, prev;
    initial begin
        // exemplos T8 (conferidos à mão e no livro)
        expect_val(32'h40,  8, 1.0);
        expect_val(32'h41,  8, 1.125);
        expect_val(32'h48,  8, 2.0);
        expect_val(32'h50,  8, 8.0);
        expect_val(32'h60,  8, 32768.0);
        expect_val(32'h3F,  8, 0.9375);
        expect_val(32'hC0,  8, -1.0);
        expect_val(32'hBF,  8, -1.125);
        expect_val(32'h7F,  8, $pow(2.0, 239));
        expect_val(32'h01,  8, $pow(2.0, -239));
        expect_val(32'h30,  8, 0.125);          // exercício b do guia
        expect_val(32'hB0,  8, -8.0);           // exercício c
        expect_val(32'h68,  8, $pow(2.0, 31));  // exercício d
        // T16
        expect_val(32'h4000, 16, 1.0);
        expect_val(32'h4A00, 16, 3.0);          // exercício e
        expect_val(32'h3400, 16, 0.25);         // exercício f
        expect_val(32'h7FFF, 16, (1.0 + 15.0/16.0) * $pow(2.0, 254));
        expect_val(32'h0001, 16, (1.0 + 1.0/16.0) * $pow(2.0, -255));
        // T32
        expect_val(32'h40000000, 32, 1.0);
        expect_val(32'hC0000000, 32, -1.0);

        // negação e monotonicidade, exaustivo em T8 e T16
        for (n = 8; n <= 16; n = n + 8) begin
            half = 1 << (n-1);
            prev = 0.0;
            for (k = -(half-1); k <= half-1; k = k + 1) begin
                t  = k & ((1 << n) - 1);
                tn = (-k) & ((1 << n) - 1);
                v  = ref_value(t, n);
                vn = ref_value(tn, n);
                checks = checks + 2;
                if (vn != -v) begin
                    errors = errors + 1;
                    if (errors < 20) $display("ERRO negação n=%0d t=%h: %e vs %e", n, t, v, vn);
                end
                if (k != -(half-1) && !(v > prev)) begin
                    errors = errors + 1;
                    if (errors < 20) $display("ERRO monotonia n=%0d t=%h: %e <= %e", n, t, v, prev);
                end
                prev = v;
            end
        end

        if (errors == 0) $display("PASS tb_ref: %0d verificações", checks);
        else             $display("FAIL tb_ref: %0d erros em %0d verificações", errors, checks);
        $finish;
    end
endmodule
