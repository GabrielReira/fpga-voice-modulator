// ==============================================================================
// Módulo   : fir_mac.v
// Projeto  : Modulador de Voz em FPGA (ENGG54 - UFBA)
// Função   : Unidade MAC sequencial para filtro FIR de 101 coeficientes (Q15).
// Correção : Pipeline alinhado; zeramento de acc em IDLE; sem perda do tap[0].
// ==============================================================================

`timescale 1ns / 1ps

module fir_mac #(
    parameter NUM_TAPS   = 101, // Número de coeficientes (101 taps)
    parameter ADDR_WIDTH = 7    // 2^7 = 128 endereços
)(
    input  wire        clk,
    input  wire        rst_n,

    // --- Interface de Entrada de Áudio ---
    input  wire signed [15:0] sample_in,        // Amostra x[n] em Q15
    input  wire               sample_valid,     // Pulso: nova amostra pronta

    // --- Interface com a ROM de Coeficientes ---
    output reg  [ADDR_WIDTH-1:0] coeff_addr,    // Endereço k (0 a 100)
    input  wire signed [15:0]    coeff_data,    // Coeficiente h[k] em Q15

    // --- Interface de Saída de Áudio Filtrado ---
    output reg  signed [15:0] sample_out,       // Amostra y[n] em Q15
    output reg                out_valid,        // Pulso: y[n] calculada
    output reg                busy              // 1 enquanto calcula
);

    // --------------------------------------------------------------------------
    // 1. Buffer Circular de Histórico (x[n-k])
    // --------------------------------------------------------------------------
    reg signed [15:0] x_mem [0:127];
    reg [ADDR_WIDTH-1:0] wr_ptr;
    reg [ADDR_WIDTH-1:0] rd_ptr;

    integer i;
    initial begin
        for (i = 0; i < 128; i = i + 1)
            x_mem[i] = 16'd0;
    end

    // --------------------------------------------------------------------------
    // 2. Estados da FSM e Registradores de Pipeline
    // --------------------------------------------------------------------------
    localparam ST_IDLE  = 2'd0;
    localparam ST_CALC  = 2'd1;
    localparam ST_ROUND = 2'd2;
    localparam ST_DONE  = 2'd3;

    reg [1:0] state;
    reg [ADDR_WIDTH-1:0] k_cnt;

    reg signed [15:0] sample_pipe;
    reg signed [15:0] coeff_pipe;
    reg               pipe_valid;

    // Multiplicação: 16b x 16b com sinal = 32b com sinal (Q30)
    wire signed [31:0] mult_result;
    assign mult_result = sample_pipe * coeff_pipe;

    // Acumulador de 40 bits
    reg signed [39:0] acc;

    // --------------------------------------------------------------------------
    // 3. Controle da FSM e Pipeline Aritmético
    // --------------------------------------------------------------------------
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state        <= ST_IDLE;
            wr_ptr       <= 7'd0;
            rd_ptr       <= 7'd0;
            k_cnt        <= 7'd0;
            coeff_addr   <= 7'd0;
            sample_pipe  <= 16'd0;
            coeff_pipe   <= 16'd0;
            pipe_valid   <= 1'b0;
            acc          <= 40'd0;
            sample_out   <= 16'd0;
            out_valid    <= 1'b0;
            busy         <= 1'b0;
        end else begin
            out_valid <= 1'b0;

            case (state)
                // --------------------------------------------------------------
                // IDLE: Espera nova amostra e prepara acumulador zerado
                // --------------------------------------------------------------
                ST_IDLE: begin
                    busy       <= 1'b0;
                    pipe_valid <= 1'b0;
                    k_cnt      <= 7'd0;

                    if (sample_valid) begin
                        busy          <= 1'b1;
                        acc           <= 40'd0; // Zera o acumulador no início
                        x_mem[wr_ptr] <= sample_in;
                        coeff_addr    <= 7'd0;  // Busca h[0]
                        rd_ptr        <= wr_ptr;// Busca x[n]
                        wr_ptr        <= wr_ptr + 1'b1;
                        state         <= ST_CALC;
                    end
                end

                // --------------------------------------------------------------
                // CALC: Itera taps de 0 a 100 somando continuamente
                // --------------------------------------------------------------
                ST_CALC: begin
                    sample_pipe <= x_mem[rd_ptr];
                    coeff_pipe  <= coeff_data;
                    pipe_valid  <= 1'b1;

                    // Acumula produtos a partir do momento em que o pipeline enche
                    if (pipe_valid) begin
                        acc <= acc + mult_result;
                    end

                    // Avança os ponteiros enquanto não atingir o último tap (100)
                    if (k_cnt < (NUM_TAPS - 1)) begin
                        k_cnt      <= k_cnt + 1'b1;
                        coeff_addr <= coeff_addr + 1'b1;
                        rd_ptr     <= rd_ptr - 1'b1;
                    end else begin
                        // Todos os 101 taps foram solicitados; avança para drenar o pipeline
                        state <= ST_ROUND;
                    end
                end

                // --------------------------------------------------------------
                // ROUND: Soma o 101º produto (tap 100) pendente no pipeline
                // --------------------------------------------------------------
                ST_ROUND: begin
                    acc   <= acc + mult_result;
                    state <= ST_DONE;
                end

                // --------------------------------------------------------------
                // DONE: Arredondamento simétrico (+0.5 LSB) e Saturação Q15
                // --------------------------------------------------------------
                ST_DONE: begin
                    busy      <= 1'b0;
                    out_valid <= 1'b1;

                    begin : SATURATION_BLOCK
                        reg signed [39:0] acc_rounded;
                        acc_rounded = acc + 40'sh00_0000_4000;

                        // Saturação positiva (> +32767)
                        if (!acc_rounded[39] && (|acc_rounded[38:30])) begin
                            sample_out <= 16'sh7FFF;
                        // Saturação negativa (< -32768)
                        end else if (acc_rounded[39] && (!(&acc_rounded[38:30]))) begin
                            sample_out <= 16'sh8000;
                        // Normal Q15
                        end else begin
                            sample_out <= acc_rounded[30:15];
                        end
                    end

                    state <= ST_IDLE;
                end

                default: state <= ST_IDLE;
            endcase
        end
    end

endmodule