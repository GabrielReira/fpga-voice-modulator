// ==============================================================================
// Módulo   : dsp_core.v
// Pasta    : rtl/dsp/
// Projeto  : Modulador de Voz em FPGA (ENGG54 - UFBA)
// Função   : Núcleo DSP Integrado (FIR + tanh + comb + seletor SW0)
// Padrão   : Verilog-2001 (IEEE 1364-2001)
// ==============================================================================

`timescale 1ns / 1ps

module dsp_core #(
    // Caminhos dos arquivos .hex apontando para a pasta do repositório
    parameter FILE_HELIO = "../fpga-voice-modulator/rtl/rom/fir_helio.hex",
    parameter FILE_VADER = "../fpga-voice-modulator/rtl/rom/fir_vader.hex",
    parameter FILE_TANH  = "../fpga-voice-modulator/rtl/rom/tanh_lut.hex"
)(
    input  wire        clk,
    input  wire        rst_n,

    // Seleção de Modo (0 = Hélio, 1 = Darth Vader)
    input  wire        sel_mode,

    // Entrada (vinda do wav_buffer a cada pulso de sample_req)
    input  wire signed [15:0] sample_in,
    input  wire               sample_valid,

    // Sinalização de ocupado (1 enquanto o FIR estiver processando os 101 taps)
    output wire               busy,

    // Saída processada (pronta para o i2s_tx)
    output wire signed [15:0] sample_out,
    output wire               out_valid
);

    // --------------------------------------------------------------------------
    // 1. Instanciação da ROM de Coeficientes do FIR
    // --------------------------------------------------------------------------
    wire [6:0]         fir_coeff_addr;
    wire signed [15:0] fir_coeff_data;

    fir_rom #(
        .NUM_TAPS   (101),
        .ADDR_WIDTH (7),
        .FILE_HELIO (FILE_HELIO),
        .FILE_VADER (FILE_VADER)
    ) u_fir_rom (
        .addr       (fir_coeff_addr),
        .sel_filter (sel_mode),
        .coeff_data (fir_coeff_data)
    );

    // --------------------------------------------------------------------------
    // 2. Instanciação do Motor de Filtragem FIR (Bloco 5)
    // --------------------------------------------------------------------------
    wire signed [15:0] fir_sample_out;
    wire               fir_out_valid;

    fir_mac #(
        .NUM_TAPS   (101),
        .ADDR_WIDTH (7)
    ) u_fir_mac (
        .clk          (clk),
        .rst_n        (rst_n),
        .sample_in    (sample_in),
        .sample_valid (sample_valid),
        .coeff_addr   (fir_coeff_addr),
        .coeff_data   (fir_coeff_data),
        .sample_out   (fir_sample_out),
        .out_valid    (fir_out_valid),
        .busy         (busy)
    );

    // --------------------------------------------------------------------------
    // 3. Instanciação da Saturação Não-Linear (Bloco 6 - Ativo apenas no Vader)
    // --------------------------------------------------------------------------
    wire signed [15:0] sat_sample_out;
    wire               sat_out_valid;

    tanh_lut #(
        .LUT_FILE (FILE_TANH)
    ) u_tanh (
        .clk          (clk),
        .rst_n        (rst_n),
        .sample_in    (fir_sample_out),
        .sample_valid (fir_out_valid & sel_mode), // Aciona apenas se sel_mode == 1
        .sample_out   (sat_sample_out),
        .out_valid    (sat_out_valid)
    );

    // --------------------------------------------------------------------------
    // 4. Instanciação do Filtro Pente (Bloco 7 - Ativo apenas no Vader)
    // --------------------------------------------------------------------------
    wire signed [15:0] comb_sample_out;
    wire               comb_out_valid;

    comb_filter #(
        .DELAY_SAMPLES (1102),
        .ADDR_WIDTH    (11)
    ) u_comb (
        .clk          (clk),
        .rst_n        (rst_n),
        .sample_in    (sat_sample_out),
        .sample_valid (sat_out_valid),
        .sample_out   (comb_sample_out),
        .out_valid    (comb_out_valid)
    );

    // --------------------------------------------------------------------------
    // 5. Multiplexador de Saída (Bloco 8)
    // --------------------------------------------------------------------------
    // sel_mode = 0 (Hélio): sinal sai direto do FIR
    // sel_mode = 1 (Vader): sinal sai do comb_filter após passar pelo FIR e tanh
    assign sample_out = (sel_mode == 1'b0) ? fir_sample_out : comb_sample_out;
    assign out_valid  = (sel_mode == 1'b0) ? fir_out_valid  : comb_out_valid;

endmodule