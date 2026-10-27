// ==============================================================================
// Módulo   : tanh_lut.v
// Pasta    : rtl/dsp/
// Projeto  : Modulador de Voz em FPGA (ENGG54 - UFBA)
// Função   : Saturação suave não-linear: y = 0.6 * tanh(2x) via Look-Up Table
// Padrão   : Verilog-2001 (IEEE 1364-2001)
// ==============================================================================

`timescale 1ns / 1ps

module tanh_lut #(
    parameter LUT_FILE = "../rtl/rom/tanh_lut.hex"
)(
    input  wire        clk,
    input  wire        rst_n,

    input  wire signed [15:0] sample_in,
    input  wire               sample_valid,

    output reg  signed [15:0] sample_out,
    output reg                out_valid
);

    // Memória ROM de 256 posições
    reg [15:0] lut_mem [0:255];

    initial begin
        $readmemh(LUT_FILE, lut_mem);
    end

    // Registradores de pipeline para balanceamento de temporização
    reg       is_negative;
    reg [7:0] lut_addr;
    reg       pipe_valid;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            is_negative <= 1'b0;
            lut_addr    <= 8'd0;
            pipe_valid  <= 1'b0;
            sample_out  <= 16'sh0000;
            out_valid   <= 1'b0;
        end else begin
            pipe_valid <= sample_valid;

            // Estágio 1: Extração de Magnitude e Endereço
            if (sample_valid) begin
                if (sample_in < 0) begin
                    is_negative <= 1'b1;
                    if (sample_in == 16'sh8000)
                        lut_addr <= 8'd255;
                    else
                        lut_addr <= (-sample_in) >> 7; // Bits [14:7] da magnitude
                end else begin
                    is_negative <= 1'b0;
                    lut_addr    <= sample_in >> 7;
                end
            end

            // Estágio 2: Leitura da ROM e Restauração de Sinal
            if (pipe_valid) begin
                if (is_negative) begin
                    sample_out <= -lut_mem[lut_addr];
                end else begin
                    sample_out <= lut_mem[lut_addr];
                end
            end

            out_valid <= pipe_valid;
        end
    end

endmodule