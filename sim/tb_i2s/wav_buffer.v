// wav_buffer.v
// FIFO circular de amostras INT16 entre o wav_reader (produtor, em rajadas)
// e o DSP / I2S (consumidor, ritmo constante ditado pelo LRCK).
//
//   wav_reader ──(wr_data, wr_en)──►  [ wav_buffer ]  ──(rd_en / rd_data, rd_valid)──► dsp_core
//   sd_file_reader ◄──(can_read)────────────┘
//
// Ideia:
//  * O SD entrega ~0,5 MB/s, o consumo eh ~88 kB/s (44,1 kHz, mono, 16 bits).
//    Sem controle de fluxo o buffer estouraria; por isso can_read so' fica em 1
//    quando ha espaco para 1 setor inteiro (SECTOR_SAMPLES = 256 amostras).
//  * can_read eh avaliado pelo sd_file_reader ANTES de iniciar cada setor, e
//    todas as amostras de um setor ja foram escritas quando o proximo eh
//    pedido (o sd_reader ainda gasta ~64 ciclos de sdclk no "tail"). Logo,
//    nunca ha mais de 1 setor em transito e o buffer nao estoura.
//  * Leitura com 1 ciclo de latencia: rd_en em T -> rd_valid/rd_data em T+1.
//    Se rd_en vier com o buffer vazio, rd_data = 0 (silencio) e o flag
//    "underrun" fica em 1 (pegajoso, serve de LED de depuracao).
//  * playable: sobe quando ha PRIME_SAMPLES amostras (ou o arquivo acabou) e
//    nao desce mais. O consumidor so' deve comecar a puxar depois dele,
//    para nao dar underrun no inicio.
//  * finished: eos recebido e buffer vazio (todo o arquivo foi tocado).
//
// Memoria: DEPTH x 16 bits (ADDR_W=10 -> 1024 amostras -> 2 blocos M9K).

module wav_buffer #(
    parameter ADDR_W         = 10,    // DEPTH = 2**ADDR_W amostras
    parameter SECTOR_SAMPLES = 256,   // 512 bytes / 2
    parameter PRIME_SAMPLES  = 256    // enchimento minimo antes de liberar a reproducao
)(
    input  wire              clk,
    input  wire              rst_n,

    // ---- lado de escrita (wav_reader) ----
    input  wire [15:0]       wr_data,
    input  wire              wr_en,      // = sample_valid
    input  wire              eos,        // = stream_done (pode ficar em 1)

    // ---- controle de fluxo para o sd_file_reader ----
    output reg               can_read,

    // ---- lado de leitura (dsp_core / i2s) ----
    input  wire              rd_en,      // pulso de 1 ciclo: "quero 1 amostra"
    output wire [15:0]       rd_data,
    output reg               rd_valid,   // rd_data valido (1 ciclo apos rd_en)

    // ---- status ----
    output reg               playable,
    output wire              finished,
    output wire [ADDR_W:0]   level,      // amostras armazenadas agora
    output reg               overrun,    // escrita com buffer cheio (amostra perdida)
    output reg               underrun    // leitura com buffer vazio (silencio inserido)
);

localparam DEPTH = 1 << ADDR_W;

// ---------------------------------------------------------------
// Memoria (inferida como M9K na Cyclone IV)
// ---------------------------------------------------------------
(* ramstyle = "M9K" *) reg [15:0] mem [0:DEPTH-1];

reg [ADDR_W-1:0] wr_ptr;
reg [ADDR_W-1:0] rd_ptr;
reg [ADDR_W:0]   count;
reg              eos_l;
reg              rd_ok;     // a leitura anterior foi valida (buffer nao estava vazio)
reg [15:0]       rd_q;

wire full  = (count == DEPTH);
wire empty = (count == 0);

wire do_wr = wr_en && !full;
wire do_rd = rd_en && !empty;

assign level    = count;
assign rd_data  = rd_ok ? rd_q : 16'd0;
assign finished = eos_l && empty;

// escrita e leitura sincronas (sem reset, para inferir RAM)
always @(posedge clk) begin
    if (do_wr)
        mem[wr_ptr] <= wr_data;
    rd_q <= mem[rd_ptr];
end

always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        wr_ptr   <= 0;
        rd_ptr   <= 0;
        count    <= 0;
        eos_l    <= 1'b0;
        rd_ok    <= 1'b0;
        rd_valid <= 1'b0;
        playable <= 1'b0;
        overrun  <= 1'b0;
        underrun <= 1'b0;
        can_read <= 1'b0;
    end else begin
        // ponteiros e contador
        if (do_wr) wr_ptr <= wr_ptr + 1'b1;
        if (do_rd) rd_ptr <= rd_ptr + 1'b1;
        count <= count + (do_wr ? 1 : 0) - (do_rd ? 1 : 0);

        // leitura: resposta no ciclo seguinte
        rd_valid <= rd_en;
        rd_ok    <= do_rd;

        // fim do arquivo
        if (eos) eos_l <= 1'b1;

        // flags de depuracao (pegajosos)
        if (wr_en && full)  overrun  <= 1'b1;
        if (rd_en && empty) underrun <= 1'b1;

        // libera a reproducao quando ha dados suficientes (ou o arquivo acabou)
        if (count >= PRIME_SAMPLES || eos_l)
            playable <= 1'b1;

        // ha espaco para mais 1 setor?
        can_read <= (count <= DEPTH - SECTOR_SAMPLES);
    end
end

endmodule
