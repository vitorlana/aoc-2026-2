// tb_vec.v - validacao da alu vetorial contra vetores de teste
// Formato de cada linha: vs2 vs1 vd_old op vl vd (hexadecimal)

`timescale 1ns/1ps
module tb_vec;
    parameter SEW = 8;
    parameter NV = 1;
    parameter FILE = "vec.hex";

    reg  [63:0] vs2, vs1, old;
    reg  [1:0]  op;
    reg  [7:0]  vl;
    wire [63:0] vd;
    takum_vec_alu #(.VLEN(64)) dut (.vs2(vs2), .vs1(vs1), .vd_old(old), .op(op),
                                    .sew(SEW == 8 ? 2'd0 : SEW == 16 ? 2'd1 : 2'd2), .vl(vl), .vd(vd));

    integer fd, rc, n, errors;
    reg [63:0] x2, x1, xo, xd;
    reg [31:0] xop, xvl;

    initial begin
        errors = 0; n = 0;
        fd = $fopen(FILE, "r");
        if (fd == 0) begin $display("ERRO: não abriu %0s", FILE); $finish; end
        while (!$feof(fd) && n < NV) begin
            rc = $fscanf(fd, "%h %h %h %h %h %h\n", x2, x1, xo, xop, xvl, xd);
            if (rc == 6) begin
                vs2 = x2; vs1 = x1; old = xo; op = xop; vl = xvl;
                #1;
                if (vd !== xd) begin
                    errors = errors + 1;
                    if (errors <= 10)
                        $display("ERRO vec SEW=%0d: vs2=%h vs1=%h op=%0d vl=%0d obtido=%h esperado=%h",
                                 SEW, vs2, vs1, op, vl, vd, xd);
                end
                n = n + 1;
            end
        end
        $fclose(fd);
        if (errors == 0) $display("PASS vec SEW=%0d: %0d vetores", SEW, n);
        else             $display("FAIL vec SEW=%0d: %0d divergências em %0d vetores", SEW, errors, n);
        $finish;
    end
endmodule
