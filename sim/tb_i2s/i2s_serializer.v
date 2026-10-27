// ==============================================================================
// Módulo   : i2s_serializer.v
// Função   : Serializa 1 amostra int16 (mono, L = R) em I2S Philips, 16 bits
//            num slot de 32, guiado pelos strobes do i2s_clk_gen (domínio mclk).
//
// A cada início de frame (início do canal esquerdo) o módulo:
//   1) captura sample_in = resposta ao sample_req do frame ANTERIOR
//      (o dsp_core teve um frame inteiro para calcular);
//   2) emite um novo pulso sample_req (1 ciclo de mclk).
//
// sample_in vem do dsp_core (domínio clk) e só muda ~2 us após um pedido,
// ficando estável o resto do frame -> caminho quase estático (false path/grupo
// assíncrono no SDC). sample_req (domínio mclk) deve ser sincronizado para clk:
// o i2s_tx já faz isso.
// ==============================================================================
`timescale 1ns / 1ps

module i2s_serializer (
    input  wire               mclk,
    input  wire               rst_n,
    input  wire               fall,        // do i2s_clk_gen
    input  wire               lr_ev,
    input  wire               right,
    input  wire signed [15:0] sample_in,   // saída do dsp_core
    output reg                sample_req,  // pulso: pede a amostra do próximo frame
    output reg                sdata        // -> AUD_DACDAT
);
    reg [15:0] cur, sh;
    reg [4:0]  cnt;                        // posição do bit no slot (0..31)

    always @(posedge mclk or negedge rst_n) begin
        if (!rst_n) begin
            cur <= 16'd0; sh <= 16'd0; cnt <= 5'd0;
            sdata <= 1'b0; sample_req <= 1'b0;
        end else begin
            sample_req <= 1'b0;
            if (fall) begin
                if (lr_ev) begin
                    cnt   <= 5'd1;
                    sdata <= 1'b0;                 // slot de atraso do I2S
                    if (!right) begin              // início do frame (esquerdo)
                        cur <= sample_in;
                        sh  <= sample_in;
                        sample_req <= 1'b1;
                    end else begin                 // direito: repete a amostra
                        sh  <= cur;
                    end
                end else begin
                    if (cnt <= 5'd16) begin        // bits 15..0
                        sdata <= sh[15];
                        sh    <= {sh[14:0], 1'b0};
                    end else
                        sdata <= 1'b0;             // preenchimento até 32 bits
                    if (cnt != 5'd31) cnt <= cnt + 1'b1;
                end
            end
        end
    end
endmodule
