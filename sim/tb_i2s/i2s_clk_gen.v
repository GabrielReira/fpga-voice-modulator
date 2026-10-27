// ==============================================================================
// Módulo   : i2s_clk_gen.v
// Função   : Gera BCLK/LRCK a partir do MCLK da PLL e os strobes de controle
//            usados pelo i2s_serializer.
//   RATIO = MCLK/fs = 256  -> BCLK = MCLK/4 , LRCK = MCLK/256
//   RATIO = 128            -> BCLK = MCLK/2 , LRCK = MCLK/128
//   (BCLK = 64*fs nos dois casos: 2 canais x slot de 32 bits)
//
// BCLK e LRCK saem de flops. LRCK muda na DESCIDA do BCLK (exigência do WM8731).
// Os strobes são combinacionais e valem no ciclo ANTERIOR à descida do BCLK, de
// modo que o i2s_serializer atualiza SDATA exatamente na mesma borda em que o BCLK desce
// (dado estável durante toda a subida do BCLK, mesmo com BCLK = MCLK/2).
// ==============================================================================
`timescale 1ns / 1ps

module i2s_clk_gen #(
    parameter RATIO = 256  // 256 ou 128
)(
    input  wire mclk,
    input  wire rst_n,
    output reg  bclk,
    output reg  lrck,
    output wire fall,      // este ciclo gera a descida do BCLK
    output wire lr_ev,     // ... e é o início de um canal (slot 0)
    output wire right      // canal que começa em lr_ev (0=esq, 1=dir)
);
    localparam BSH = (RATIO == 256) ? 2 : 1;  // BCLK = MCLK / 2**BSH
    localparam RB  = (RATIO == 256) ? 7 : 6;  // bit do contador que indica o canal

    reg [7:0] cnt;

    assign fall  = (cnt[BSH-1:0] == 0);
    assign right = cnt[RB];
    assign lr_ev = fall && (cnt[RB-1:BSH] == 0);

    always @(posedge mclk or negedge rst_n) begin
        if (!rst_n) begin
            cnt  <= 8'd0;
            bclk <= 1'b0;
            lrck <= 1'b1;
        end else begin
            cnt  <= (cnt == RATIO - 1) ? 8'd0 : cnt + 1'b1;
            bclk <= cnt[BSH-1];
            if (lr_ev) lrck <= right;
        end
    end
endmodule
