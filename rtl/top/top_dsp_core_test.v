// ==============================================================================
// Módulo   : top_dsp_core_test.v
// Projeto  : Modulador de Voz em FPGA (ENGG54 - UFBA)
// Função   : Teste em placa (DE2-115) do dsp_core, SEM SD e SEM I2S.
//
// O que faz:
//   1. Gera um estímulo interno a 44,1 kHz (50 MHz / SAMPLE_DIV):
//        - PREROLL  = 2048 amostras zero  (limpa x_mem do FIR e a linha de atraso do comb)
//        - 1 impulso 0x7FFF (~1.0 em Q15)
//        - POSTROLL = 1279 amostras zero
//      Total = 3328 amostras = 0x0D00.
//   2. Com impulso na entrada, y[k] = h[k]  (resposta ao impulso = coeficientes).
//      O próprio top confere a saída do dsp_core contra uma 2ª cópia da fir_rom.
//
//   Modo Hélio (SW0 = 0), tudo conferido automaticamente:
//        - y[k] == h_helio[k]  (±1 LSB) para k = 0..100
//        - y = 0 exato fora da janela do impulso
//        - ROM carregada (ao menos um |h| >= 256; ROM vazia = FALHA, não PASS falso)
//   Modo Vader (SW0 = 1):
//        - sinal(y[k]) == sinal(h_vader[k]) onde |h| >= 256 (FIR + tanh)
//        - eco do comb: y[k+1102] == 0.6 * y[k]  (±2 LSB), k = 0..100
//        - y = 0 exato fora das duas janelas
//   Ambos:
//        - 1 out_valid por amostra enviada, antes da próxima amostra
//        - dsp_core nunca ocupado (busy) quando uma nova amostra chega
//
// Uso:
//   SW0  = modo (0 Hélio, 1 Vader). Lido ao soltar KEY0.
//   KEY0 = reset / reinicia o teste (rode de novo após trocar SW0).
//   SW1  = o que os HEX mostram: 0 = amostras de saída recebidas, 1 = nº de erros.
//
//   LEDR[0] = dsp_core respondeu (viu ao menos 1 out_valid)
//   LEDR[1] = PASS    (teste concluído e 0 erros)             -> deve ACENDER
//   LEDR[2] = FAIL    (qualquer erro, pegajoso)               -> deve ficar APAGADO
//   LEDR[3] = DONE    (teste concluído)
//   LEDR[4] = erro de valor    (FIR/tanh/eco/zero/ROM vazia)
//   LEDR[5] = erro de contagem (saída faltando ou fora do total)
//   LEDR[6] = erro de protocolo (busy no início de amostra, out_valid espúrio)
//   LEDR[7] = modo em execução (0 Hélio, 1 Vader)
//   HEX3:HEX0 = SW1=0: nº de saídas (esperado final: 0D00)
//               SW1=1: nº de erros  (esperado final: 0000)
//
// Pinos que NÃO existiam nos tops anteriores (conferir no manual da DE2-115):
//   set_location_assignment PIN_AB28 -to SW0
//   set_location_assignment PIN_AC28 -to SW1
//   LEDR[4..7]: F18, E18, J19, H19
//   HEX2[0..6]: AA25 AA26 Y25 W26 Y26 W27 W28
//   HEX3[0..6]: V21  U21  AB20 AA21 AD24 AF23 Y19
//
// Arquivos do projeto Quartus: dsp_core, fir_rom, fir_mac, tanh_lut, comb_filter.
// Os caminhos dos .hex abaixo devem ser os mesmos que o dsp_core já usa.
// ==============================================================================

module top_dsp_core_test #(
    parameter SAMPLE_DIV = 1134,    // 50 MHz / 1134 = 44,09 kHz (o FIR leva ~105 ciclos)
    parameter FILE_HELIO = "../fpga-voice-modulator/rtl/rom/fir_helio.hex",
    parameter FILE_VADER = "../fpga-voice-modulator/rtl/rom/fir_vader.hex",
    parameter FILE_TANH  = "../fpga-voice-modulator/rtl/rom/tanh_lut.hex"
)(
    input  wire        CLOCK_50,
    input  wire        KEY0,
    input  wire        SW0,
    input  wire        SW1,
    output wire [7:0]  LEDR,
    output wire [6:0]  HEX0,
    output wire [6:0]  HEX1,
    output wire [6:0]  HEX2,
    output wire [6:0]  HEX3
);

// -------------------------------------------------------
// Constantes do teste
// -------------------------------------------------------
localparam NUM_TAPS  = 101;
localparam PREROLL   = 2048;
localparam POSTROLL  = 1280;
localparam TOTAL     = PREROLL + POSTROLL;    // 3328 = 16'h0D00
localparam ECHO_DLY  = 1102;                  // atraso do comb_filter
localparam INIT_WAIT = 4096;                  // espera após o reset
localparam signed [15:0] ECHO_Q15 = 16'sd19661; // 0.6 em Q15

// -------------------------------------------------------
// Reset: assert assíncrono, release síncrono (KEY0 ativo-baixo)
// -------------------------------------------------------
reg [1:0] rst_ff;
always @(posedge CLOCK_50 or negedge KEY0) begin
    if (!KEY0) rst_ff <= 2'b00;
    else       rst_ff <= {rst_ff[0], 1'b1};
end
wire rst_n = rst_ff[1];

// Chaves sincronizadas
reg [1:0] sw0_ff, sw1_ff;
always @(posedge CLOCK_50) begin
    sw0_ff <= {sw0_ff[0], SW0};
    sw1_ff <= {sw1_ff[0], SW1};
end

// -------------------------------------------------------
// Gerador de estímulo (FSM)
// -------------------------------------------------------
localparam S_INIT  = 2'd0;
localparam S_RUN   = 2'd1;
localparam S_DRAIN = 2'd2;
localparam S_DONE  = 2'd3;

reg [1:0]  state;
reg [15:0] div;
reg [15:0] n_in;          // amostras já enviadas
reg        mode_l;        // modo travado no início do teste
reg        dsp_valid;
reg signed [15:0] dsp_in;

wire        dsp_busy;
wire signed [15:0] dsp_out;
wire        dsp_out_valid;

reg [15:0] n_out;         // saídas já recebidas

wire tick = (state == S_RUN)   && (div == SAMPLE_DIV-1);
wire fin  = (state == S_DRAIN) && (div == SAMPLE_DIV-1);

always @(posedge CLOCK_50 or negedge rst_n) begin
    if (!rst_n) begin
        state     <= S_INIT;
        div       <= 16'd0;
        n_in      <= 16'd0;
        mode_l    <= 1'b0;
        dsp_valid <= 1'b0;
        dsp_in    <= 16'sd0;
    end else begin
        dsp_valid <= 1'b0;
        case (state)
            S_INIT: begin
                mode_l <= sw0_ff[1];
                if (div == INIT_WAIT-1) begin
                    div   <= 16'd0;
                    state <= S_RUN;
                end else
                    div <= div + 1'b1;
            end

            S_RUN: begin
                if (tick) begin
                    div       <= 16'd0;
                    dsp_valid <= 1'b1;
                    dsp_in    <= (n_in == PREROLL) ? 16'sh7FFF : 16'sh0000;
                    n_in      <= n_in + 1'b1;
                    if (n_in == TOTAL-1) state <= S_DRAIN;
                end else
                    div <= div + 1'b1;
            end

            S_DRAIN: begin
                if (fin) begin
                    div   <= 16'd0;
                    state <= S_DONE;
                end else
                    div <= div + 1'b1;
            end

            default: ; // S_DONE: mantém
        endcase
    end
end

// -------------------------------------------------------
// DUT
// -------------------------------------------------------
dsp_core #(
    .FILE_HELIO (FILE_HELIO),
    .FILE_VADER (FILE_VADER),
    .FILE_TANH  (FILE_TANH)
) u_dsp (
    .clk          (CLOCK_50),
    .rst_n        (rst_n),
    .sel_mode     (mode_l),
    .sample_in    (dsp_in),
    .sample_valid (dsp_valid),
    .busy         (dsp_busy),
    .sample_out   (dsp_out),
    .out_valid    (dsp_out_valid)
);

// -------------------------------------------------------
// Verificador - Estágio A: captura da saída e índice k
// -------------------------------------------------------
reg signed [15:0] y_a;
reg [15:0]        k_a;
reg               v_a;

always @(posedge CLOCK_50 or negedge rst_n) begin
    if (!rst_n) begin
        y_a   <= 16'sd0;
        k_a   <= 16'd0;
        v_a   <= 1'b0;
        n_out <= 16'd0;
    end else begin
        v_a <= dsp_out_valid;
        if (dsp_out_valid) begin
            y_a   <= dsp_out;
            k_a   <= n_out;
            n_out <= n_out + 1'b1;
        end
    end
end

// Janelas (índice da saída em relação ao impulso)
wire [15:0] k_rel   = k_a - PREROLL;
wire [15:0] k_echo  = k_a - PREROLL - ECHO_DLY;
wire in_fir  = (k_a >= PREROLL) && (k_a < PREROLL + NUM_TAPS);
wire in_echo = (k_a >= PREROLL + ECHO_DLY) && (k_a < PREROLL + ECHO_DLY + NUM_TAPS);
// Onde a saída deve ser exatamente zero
wire expect_zero = mode_l ? ((k_a >= PREROLL + NUM_TAPS) && !in_echo)
                          : ((k_a >= 128) && !in_fir);

// 2ª cópia da ROM: referência independente da que está dentro do dsp_core
wire signed [15:0] h_ref;
fir_rom #(
    .NUM_TAPS   (NUM_TAPS),
    .ADDR_WIDTH (7),
    .FILE_HELIO (FILE_HELIO),
    .FILE_VADER (FILE_VADER)
) u_rom_ref (
    .addr       (k_rel[6:0]),
    .sel_filter (mode_l),
    .coeff_data (h_ref)
);

// Memória com a resposta c[k] do Vader na 1ª janela (para conferir o eco)
reg signed [15:0] cmem [0:127];
reg signed [15:0] c_b;
always @(posedge CLOCK_50) begin
    if (v_a && in_fir && mode_l)
        cmem[k_rel[6:0]] <= y_a;
    c_b <= cmem[k_echo[6:0]];
end

// -------------------------------------------------------
// Estágio B: referências registradas
// -------------------------------------------------------
reg               v_b, fir_b, echo_b, zero_b;
reg signed [15:0] y_b, h_b;

always @(posedge CLOCK_50 or negedge rst_n) begin
    if (!rst_n) begin
        v_b <= 1'b0; fir_b <= 1'b0; echo_b <= 1'b0; zero_b <= 1'b0;
        y_b <= 16'sd0; h_b <= 16'sd0;
    end else begin
        v_b    <= v_a;
        y_b    <= y_a;
        h_b    <= h_ref;
        fir_b  <= in_fir;
        echo_b <= in_echo;
        zero_b <= expect_zero;
    end
end

// -------------------------------------------------------
// Estágio C: diferenças e produto do eco (registrados)
// -------------------------------------------------------
reg               v_c, fir_c, echo_c, zero_c;
reg signed [15:0] y_c;
reg signed [16:0] dh_c;       // y - h
reg signed [31:0] prod_c;     // c * 0.6 (Q30)
reg               h_big_c, h_neg_c, y_zero_c, y_neg_c, c_big_c;

always @(posedge CLOCK_50 or negedge rst_n) begin
    if (!rst_n) begin
        v_c <= 1'b0; fir_c <= 1'b0; echo_c <= 1'b0; zero_c <= 1'b0;
        y_c <= 16'sd0; dh_c <= 17'sd0; prod_c <= 32'sd0;
        h_big_c <= 1'b0; h_neg_c <= 1'b0; y_zero_c <= 1'b0; y_neg_c <= 1'b0; c_big_c <= 1'b0;
    end else begin
        v_c      <= v_b;
        fir_c    <= fir_b;
        echo_c   <= echo_b;
        zero_c   <= zero_b;
        y_c      <= y_b;
        dh_c     <= y_b - h_b;
        prod_c   <= c_b * ECHO_Q15;
        h_big_c  <= (h_b >= 16'sd256) || (h_b <= -16'sd256);
        h_neg_c  <= h_b[15];
        y_zero_c <= (y_b == 16'sd0);
        y_neg_c  <= y_b[15];
        c_big_c  <= (c_b >= 16'sd256) || (c_b <= -16'sd256);
    end
end

// -------------------------------------------------------
// Estágio D: comparações
// -------------------------------------------------------
wire signed [31:0] ep       = prod_c + 32'sd16384;       // arredondamento
wire signed [15:0] exp_echo = ep >>> 15;
wire signed [16:0] de       = y_c - exp_echo;

wire fir_bad  = fir_c  && !mode_l && ((dh_c > 17'sd1) || (dh_c < -17'sd1));
wire sgn_bad  = fir_c  &&  mode_l && h_big_c && (y_zero_c || (y_neg_c != h_neg_c));
wire echo_bad = echo_c &&  mode_l && ((de > 17'sd2) || (de < -17'sd2));
wire zero_bad = zero_c && !y_zero_c;
wire val_bad  = v_c && (fir_bad || sgn_bad || echo_bad || zero_bad);

// -------------------------------------------------------
// Flags de erro, contador de erros e "viu a janela"
// -------------------------------------------------------
reg        err_val, err_cnt, err_proto, any_out;
reg        fir_seen, echo_seen;
reg [15:0] n_err;

wire ev_proto = (tick && dsp_busy) || (dsp_out_valid && (n_out >= n_in));
wire ev_cnt   = (tick && (n_out != n_in)) || (fin && (n_out != TOTAL));
wire ev_val   = val_bad || (fin && (!fir_seen || (mode_l && !echo_seen)));

always @(posedge CLOCK_50 or negedge rst_n) begin
    if (!rst_n) begin
        err_val <= 1'b0; err_cnt <= 1'b0; err_proto <= 1'b0; any_out <= 1'b0;
        fir_seen <= 1'b0; echo_seen <= 1'b0; n_err <= 16'd0;
    end else begin
        if (ev_val)   err_val   <= 1'b1;
        if (ev_cnt)   err_cnt   <= 1'b1;
        if (ev_proto) err_proto <= 1'b1;
        if ((ev_val || ev_cnt || ev_proto) && (n_err != 16'hFFFF))
            n_err <= n_err + 1'b1;

        if (dsp_out_valid)                    any_out   <= 1'b1;
        if (v_c && fir_c  && h_big_c)         fir_seen  <= 1'b1;
        if (v_c && echo_c && c_big_c)         echo_seen <= 1'b1;
    end
end

// DONE atrasado 1 ciclo para os flags da última verificação já estarem registrados
reg done_r;
always @(posedge CLOCK_50 or negedge rst_n) begin
    if (!rst_n) done_r <= 1'b0;
    else        done_r <= (state == S_DONE);
end

// -------------------------------------------------------
// LEDs
// -------------------------------------------------------
assign LEDR[0] = any_out;
assign LEDR[1] = done_r && (n_err == 16'd0);
assign LEDR[2] = err_val | err_cnt | err_proto;
assign LEDR[3] = done_r;
assign LEDR[4] = err_val;
assign LEDR[5] = err_cnt;
assign LEDR[6] = err_proto;
assign LEDR[7] = mode_l;

// -------------------------------------------------------
// Displays HEX (ativo-baixo)
// -------------------------------------------------------
function [6:0] seg7;
    input [3:0] d;
    case (d)
        4'h0: seg7 = 7'b1000000;
        4'h1: seg7 = 7'b1111001;
        4'h2: seg7 = 7'b0100100;
        4'h3: seg7 = 7'b0110000;
        4'h4: seg7 = 7'b0011001;
        4'h5: seg7 = 7'b0010010;
        4'h6: seg7 = 7'b0000010;
        4'h7: seg7 = 7'b1111000;
        4'h8: seg7 = 7'b0000000;
        4'h9: seg7 = 7'b0010000;
        4'hA: seg7 = 7'b0001000;
        4'hB: seg7 = 7'b0000011;
        4'hC: seg7 = 7'b1000110;
        4'hD: seg7 = 7'b0100001;
        4'hE: seg7 = 7'b0000110;
        4'hF: seg7 = 7'b0001110;
        default: seg7 = 7'b1111111;
    endcase
endfunction

wire [15:0] disp = sw1_ff[1] ? n_err : n_out;

assign HEX0 = seg7(disp[3:0]);
assign HEX1 = seg7(disp[7:4]);
assign HEX2 = seg7(disp[11:8]);
assign HEX3 = seg7(disp[15:12]);

endmodule
