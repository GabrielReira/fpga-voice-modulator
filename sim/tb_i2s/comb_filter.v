// ==============================================================================
// Módulo   : comb_filter.v
// Pasta    : rtl/dsp/
// Projeto  : Modulador de Voz em FPGA (ENGG54 - UFBA)
// Função   : Filtro pente com atraso de 1102 amostras (25 ms) e ganho de 0.6
//            Equação: y[n] = x[n] + 0.6 * x[n - 1102]
// Padrão   : Verilog-2001 (IEEE 1364-2001)
// ==============================================================================

`timescale 1ns / 1ps

module comb_filter #(
    parameter DELAY_SAMPLES = 1102, // 25 ms @ 44.1 kHz
    parameter ADDR_WIDTH    = 11    // 2^11 = 2048 amostras
)(
    input  wire        clk,
    input  wire        rst_n,

    input  wire signed [15:0] sample_in,
    input  wire               sample_valid,

    output reg  signed [15:0] sample_out,
    output reg                out_valid
);

    // Coeficiente 0.6 em Q15: 0.6 * 32768 = 19661
    localparam signed [15:0] ALPHA_Q15 = 16'sh4CCE;

    // Cálculo do offset inicial do ponteiro de leitura sem warning de largura
    localparam [ADDR_WIDTH-1:0] RD_INIT = (12'd2048 - DELAY_SAMPLES);

    // Buffer de Retardo em RAM interna (M9K)
    reg signed [15:0] delay_line [0:2047];

    reg [ADDR_WIDTH-1:0] wr_ptr;
    reg [ADDR_WIDTH-1:0] rd_ptr;

    integer i;
    initial begin
        for (i = 0; i < 2048; i = i + 1)
            delay_line[i] = 16'sh0000;
    end

    // Registradores do Pipeline
    reg signed [15:0] x_pipe;
    reg signed [15:0] delayed_sample;
    reg               pipe_valid;

    // Multiplicação do termo de atraso: 16b x 16b = 32b com sinal
    wire signed [31:0] scaled_delay;
    assign scaled_delay = delayed_sample * ALPHA_Q15;

    // Termo escalado alinhado em Q15 (+ arredondamento)
    wire signed [15:0] echo_term;
    assign echo_term = (scaled_delay + 32'sh0000_4000) >>> 15;

    // Soma do sinal original com o sinal atrasado
    wire signed [16:0] sum_extended;
    assign sum_extended = x_pipe + echo_term;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            wr_ptr         <= {ADDR_WIDTH{1'b0}};
            rd_ptr         <= RD_INIT;
            x_pipe         <= 16'sh0000;
            delayed_sample <= 16'sh0000;
            pipe_valid     <= 1'b0;
            sample_out     <= 16'sh0000;
            out_valid      <= 1'b0;
        end else begin
            pipe_valid <= sample_valid;

            // Estágio 1: Leitura do passado e gravação da amostra atual
            if (sample_valid) begin
                delayed_sample     <= delay_line[rd_ptr];
                delay_line[wr_ptr] <= sample_in;
                x_pipe             <= sample_in;

                wr_ptr <= wr_ptr + 1'b1;
                rd_ptr <= rd_ptr + 1'b1;
            end

            // Estágio 2: Soma e Saturação Aritmética
            if (pipe_valid) begin
                // Saturação positiva (> +32767)
                if (sum_extended > 17'sh07FFF)
                    sample_out <= 16'sh7FFF;
                // Saturação negativa (< -32768)
                else if (sum_extended < -17'sh08000)
                    sample_out <= 16'sh8000;
                else
                    sample_out <= sum_extended[15:0];
            end

            out_valid <= pipe_valid;
        end
    end

endmodule