// takum_ref.vh — Modelo de referência do takum LINEAR (SÓ PARA TESTBENCH)
// -----------------------------------------------------------------------------
// Escrito de um jeito diferentte do RTL,  usando a Definição 8 de Hunhold (2024), para que um confira o outro:
//   * não nega a palavra: usa a fórmula do artigo também para negativos,
//       e = (-1)^S (c + S),  valor = ((1 - 3S) + f) * 2^e
//   * calcula c com 2^r - 1 + C e -2^(r+1) + 1 + C (o RTL usa {1,C}-1 e -{1,~C})
//   * usa real, $pow e inteiros: nada disto é sintetizável.
//
// Um real é um double (53 bits de fração, expoente até ±1023). Todo takum de até 32 bits (≤ 27 bits de fração, expoente -255..254) cabe nele com exatidão,
// então comparações com == são legítimas.
// =============================================================================

// 1 se t (n bits) é NaR (100...0)
function ref_is_nar;
    input [31:0] t;
    input integer n;
    begin
        ref_is_nar = (t == (32'd1 << (n-1)));
    end
endfunction

// Campos de um takum de n bits (n <= 32). Para 0 e NaR o resultado não importa.
//   r: nº de bits de característica ; c: característica ; p: nº de bits de fração
//   fbits: os p bits de fração (inteiro)
task ref_fields;
    input  [31:0] t;
    input  integer n;
    output integer s, d, r, c, p;
    output [31:0] fbits;
    integer nn, rr, cc;
    reg [31:0] pad;
    begin
        nn  = (n < 12) ? 12 : n;
        pad = t << (nn - n);                 // ghost bits: completa com zeros
        s   = pad[nn-1];
        d   = pad[nn-2];
        rr  = (pad >> (nn-5)) & 7;
        r   = d ? rr : 7 - rr;
        cc  = (pad >> (nn-5-r)) & ((1 << r) - 1);
        if (d) c = (1 << r) - 1 + cc;
        else   c = -(1 << (r+1)) + 1 + cc;
        p     = nn - 5 - r;
        fbits = pad & ((32'd1 << p) - 1);
    end
endtask

// Valor real de um takum de n bits (0.0 para zero e para NaR: use ref_is_nar)
function real ref_value;
    input [31:0] t;
    input integer n;
    integer nn, s, d, rr, r, cc, c, p, e;
    reg [31:0] pad;
    real f, fbr;
    begin
        if (t == 32'd0 || ref_is_nar(t, n)) begin
            ref_value = 0.0;
        end else begin
            nn  = (n < 12) ? 12 : n;
            pad = t << (nn - n);
            s   = pad[nn-1];
            d   = pad[nn-2];
            rr  = (pad >> (nn-5)) & 7;
            r   = d ? rr : 7 - rr;
            cc  = (pad >> (nn-5-r)) & ((1 << r) - 1);
            if (d) c = (1 << r) - 1 + cc;
            else   c = -(1 << (r+1)) + 1 + cc;
            p   = nn - 5 - r;
            fbr = pad & ((32'd1 << p) - 1);
            f   = fbr / $pow(2.0, p);
            e   = s ? -(c + 1) : c;
            ref_value = ((1 - 3*s) + f) * $pow(2.0, e);
        end
    end
endfunction

// Valor real do FORMATO INTERNO: (-1)^sign * (1 + frac / 2^nf) * 2^exp
function real unpacked_value;
    input        sign;
    input integer exp;
    input [31:0] frac;
    input integer nf;
    real fr;
    begin
        fr = frac;
        unpacked_value = (sign ? -1.0 : 1.0) * (1.0 + fr / $pow(2.0, nf)) * $pow(2.0, exp);
    end
endfunction
