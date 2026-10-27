// ==============================================================================
// Módulo   : i2s_tx.v
// Função   : Bloco 9 do diagrama pronto para instanciar no top:
//            reset sincronizado em mclk + i2s_clk_gen + i2s_serializer + sincronizador do
//            sample_req (mclk -> clk).
//
// Uso no top (domínio clk = CLOCK_50):
//   sample_req  -> wav_buffer.rd_en   (junto com playable && !finished)
//   wav_buffer.rd_valid/rd_data -> dsp_core.sample_valid/sample_in
//   dsp_core.sample_out (silenciado quando !playable || finished) -> sample_in
// ==============================================================================
`timescale 1ns / 1ps

module i2s_tx #(
    parameter RATIO = 256               // MCLK/fs: 256 ou 128
)(
    input  wire               clk,        // CLOCK_50
    input  wire               rst_n,
    input  wire               mclk,       // saída da PLL
    input  wire               pll_locked,
    input  wire signed [15:0] sample_in,  // saída do dsp_core
    output wire               sample_req, // pulso de 1 ciclo em clk

    output wire               AUD_BCLK,
    output wire               AUD_DACLRCK,
    output wire               AUD_ADCLRCK,
    output wire               AUD_DACDAT
);
    // Reset do domínio mclk: ativa assíncrono, libera síncrono
    wire rin = rst_n & pll_locked;
    reg [1:0] rs;
    always @(posedge mclk or negedge rin) begin
        if (!rin) rs <= 2'b00;
        else      rs <= {rs[0], 1'b1};
    end
    wire rst_m_n = rs[1];

    wire fall, lr_ev, right, req_m, lrck;

    i2s_clk_gen #(.RATIO(RATIO)) u_clkgen (
        .mclk(mclk), .rst_n(rst_m_n),
        .bclk(AUD_BCLK), .lrck(lrck),
        .fall(fall), .lr_ev(lr_ev), .right(right));

    i2s_serializer u_tx (
        .mclk(mclk), .rst_n(rst_m_n),
        .fall(fall), .lr_ev(lr_ev), .right(right),
        .sample_in(sample_in), .sample_req(req_m),
        .sdata(AUD_DACDAT));

    assign AUD_DACLRCK = lrck;
    assign AUD_ADCLRCK = lrck;          // ADC não usado, mas o pino precisa de LRCK

    // sample_req: mclk -> clk (2 FFs + detector de borda; pulso >= 49 ns > 20 ns)
    reg [2:0] rq;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) rq <= 3'b000;
        else        rq <= {rq[1:0], req_m};
    end
    assign sample_req = rq[1] & ~rq[2];
endmodule
