// top_wav_sd.v
// Top-level para teste de leitura WAV via SD card na DE2-115
//
// Hierarquia:
//   top_wav_sd
//   â””â”€â”€ sd_file_reader   (sd_file_reader.v)
//       â””â”€â”€ sd_reader    (sd_reader.v)
//           â””â”€â”€ sdcmd_ctrl (sdcmd_ctrl.v)
//   â””â”€â”€ wav_reader       (wav_reader.v)
//
// ANTES DE SINTETIZAR:
//   Alterar FILE_NAME e FILE_NAME_LEN para o nome do seu arquivo WAV.
//   Exemplo: "voice.wav" tem 9 caracteres -> FILE_NAME_LEN = 9
//   O nome eh case-insensitive (sd_file_reader converte para maiusculo).
//
// VERIFICAÃ‡AO via LEDs:
//   LEDR[0] = SD inicializado (card_stat chegou ao estado CMD17 = 4'd8)
//   LEDR[1] = arquivo WAV encontrado no cartao
//   LEDR[2] = toggle a cada amostra recebida (pisca durante leitura)
//   LEDR[3] = leitura completa (stream_done)
//
// VERIFICAÃ‡AO via HEX:
//   HEX1:HEX0 = 8 bits menos significativos do contador de amostras
//   Exemplo: para um WAV de 44100 Hz / 1 segundo -> contador chega a 0xAC44

module top_wav_sd #(
    // -------------------------------------------------------
    // ALTERE AQUI: nome do arquivo WAV no cartao SD
    // O arquivo deve estar na raiz do cartao (formatado em FAT32)
    // -------------------------------------------------------
    parameter            FILE_NAME_LEN = 9,
    parameter [52*8-1:0] FILE_NAME     = "voice.wav"
)(
    input  wire        CLOCK_50,
    input  wire        KEY0,       // Reset ativo-baixo (botao na DE2-115)

    // SD Card â€” SD mode (nao SPI)
    // SD_CMD eh bidirecional: FPGA envia comandos, cartao responde no mesmo fio
    output wire        SD_CLK,
    inout  wire        SD_CMD,
    input  wire        SD_DAT0,

    // LEDs de status (LEDR[3:0] na DE2-115)
    output wire [3:0]  LEDR,

    // Displays 7-segmentos (HEX0 e HEX1, common-anode, ativo-baixo)
    output wire [6:0]  HEX0,
    output wire [6:0]  HEX1
);

// -------------------------------------------------------
// Reset
// KEY0 na DE2-115 eh ativo-baixo (0 = pressionado = reset)
// -------------------------------------------------------
wire rst_n = KEY0;

// -------------------------------------------------------
// Sinais internos: sd_file_reader -> wav_reader
// -------------------------------------------------------
wire [3:0] card_stat;      // estado interno do sd_reader (4'd8 = pronto)
wire [1:0] card_type;      // tipo do cartao (2=SDv2, 3=SDHCv2)
wire [1:0] fs_type;        // filesystem (2=FAT16, 3=FAT32)
wire       file_found;     // 1 quando o arquivo WAV foi localizado
wire       outen;          // pulso: byte do arquivo disponivel
wire [7:0] outbyte;        // byte do conteudo do arquivo

// -------------------------------------------------------
// sd_file_reader
// CLK_DIV=3'd2 para clk entre 25~50 MHz (CLOCK_50 = 50 MHz)
// -------------------------------------------------------
sd_file_reader #(
    .FILE_NAME_LEN ( FILE_NAME_LEN ),
    .FILE_NAME     ( FILE_NAME     ),
    .CLK_DIV       ( 3'd2          ),
    .SIMULATE      ( 1             )
) u_sd_reader (
    .rstn            ( rst_n      ),
    .clk             ( CLOCK_50   ),
    .sdclk           ( SD_CLK     ),
    .sdcmd           ( SD_CMD     ),
    .sddat0          ( SD_DAT0    ),
    .card_stat       ( card_stat  ),
    .card_type       ( card_type  ),
    .filesystem_type ( fs_type    ),
    .file_found      ( file_found ),
    .outen           ( outen      ),
    .outbyte         ( outbyte    )
);

// -------------------------------------------------------
// wav_reader
// Recebe o stream de bytes e extrai amostras INT16
// -------------------------------------------------------
wire [15:0] sample_out;
wire        sample_valid;
wire        stream_done;

wav_reader u_wav_reader (
    .clk          ( CLOCK_50   ),
    .rst_n        ( rst_n      ),
    .byte_in      ( outbyte    ),   // byte do arquivo
    .byte_valid   ( outen      ),   // byte disponivel
    .sample_out   ( sample_out   ),
    .sample_valid ( sample_valid ),
    .stream_done  ( stream_done  )
);

// -------------------------------------------------------
// Contador de amostras (32 bits)
// Incrementa a cada sample_valid â€” util para verificar
// que o numero de amostras bate com o esperado do arquivo
// -------------------------------------------------------
reg [31:0] sample_count;

always @(posedge CLOCK_50 or negedge rst_n) begin
    if (!rst_n)
        sample_count <= 0;
    else if (sample_valid)
        sample_count <= sample_count + 1;
end

// -------------------------------------------------------
// Toggle de LED: pisca a cada amostra recebida
// (visivel a olho nu mesmo a 44100 Hz pois o LED "some" como cinza)
// -------------------------------------------------------
reg led_toggle;
always @(posedge CLOCK_50 or negedge rst_n) begin
    if (!rst_n)
        led_toggle <= 0;
    else if (sample_valid)
        led_toggle <= ~led_toggle;
end

// -------------------------------------------------------
// Mapeamento dos LEDs
// card_stat == 4'd8 significa que o sd_reader chegou ao
// estado CMD17 (pronto para receber pedidos de leitura)
// -------------------------------------------------------
assign LEDR[0] = (card_stat >= 4'd8); // SD inicializado e pronto
assign LEDR[1] = file_found;           // arquivo WAV encontrado
assign LEDR[2] = led_toggle;           // pisca durante leitura
assign LEDR[3] = stream_done;          // leitura 100% concluida

// -------------------------------------------------------
// Display HEX: mostra os 8 bits baixos do sample_count
// HEX0 = nibble baixo (bits 3:0)
// HEX1 = nibble alto  (bits 7:4)
// -------------------------------------------------------
function [6:0] seg7;
    input [3:0] d;
    // Segmentos: gfedcba (ativo-baixo, common-anode)
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
        default: seg7 = 7'b1111111; // apagado
    endcase
endfunction

assign HEX0 = seg7(sample_count[3:0]);
assign HEX1 = seg7(sample_count[7:4]);

endmodule// top_wav_sd.v
// Top-level para teste de leitura de áudio WAV via SD card
//
// Hierarquia:
//   top_wav_sd
//   |-- sd_file_reader   (sd_file_reader.v)
//   |   |-- sd_reader    (sd_reader.v)
//   |       |-- sdcmd_ctrl (sdcmd_ctrl.v)
//   |-- wav_reader       (wav_reader.v)
//
// LEDs de diagnóstico:
//   LEDR[0] = SD inicializado (card_stat >= 4'd8)
//   LEDR[1] = Arquivo WAV encontrado no cartão
//   LEDR[2] = Inverte estado a cada amostra de áudio lida
//   LEDR[3] = Leitura 100% concluída (stream_done)

module top_wav_sd #(
    parameter             FILE_NAME_LEN = 9,
    parameter [52*8-1:0]  FILE_NAME     = "voice.wav",
    parameter             SIMULATION    = 1          // 1 = Simulação rápida (sem atraso de power-on), 0 = Gravação física na FPGA
)(
    input  wire        CLOCK_50,
    input  wire        KEY0,       // Reset ativo em nível baixo (0 = pressionado, 1 = solto)

    // Interface com o SD Card (modo nativo SD)
    output wire        SD_CLK,
    inout  wire        SD_CMD,
    input  wire        SD_DAT0,

    // LEDs de diagnóstico
    output wire [3:0]  LEDR,

    // Displays de 7 segmentos (ativo em nível baixo)
    output wire [6:0]  HEX0,
    output wire [6:0]  HEX1
);

// -------------------------------------------------------
// Reset
// KEY0 é ativo-baixo (0 = reset ativo, 1 = operação normal)
// -------------------------------------------------------
wire rst_n = KEY0;

// -------------------------------------------------------
// Sinais de comunicação entre sd_file_reader e wav_reader
// -------------------------------------------------------
wire [3:0] card_stat;      // Estado interno da FSM do SD
wire [1:0] card_type;      // Tipo do cartão (2=SDv2, 3=SDHCv2)
wire [1:0] fs_type;        // Sistema de arquivos (2=FAT16, 3=FAT32)
wire       file_found;     // 1 quando localiza o arquivo voice.wav
wire       outen;          // Pulso de 1 ciclo indicando byte válido
wire [7:0] outbyte;        // Byte lido do arquivo

// -------------------------------------------------------
// Leitor de arquivos FAT32
// SIMULATE configurado com a parameter SIMULATION (1 para teste rápido)
// -------------------------------------------------------
sd_file_reader #(
    .FILE_NAME_LEN ( FILE_NAME_LEN ),
    .FILE_NAME     ( FILE_NAME     ),
    .CLK_DIV       ( 3'd2          ),
    .SIMULATE      ( SIMULATION    )
) u_sd_reader (
    .rstn            ( rst_n       ),
    .clk             ( CLOCK_50    ),
    .sdclk           ( SD_CLK      ),
    .sdcmd           ( SD_CMD      ),
    .sddat0          ( SD_DAT0     ),
    .card_stat       ( card_stat   ),
    .card_type       ( card_type   ),
    .filesystem_type ( fs_type     ),
    .file_found      ( file_found  ),
    .outen           ( outen       ),
    .outbyte         ( outbyte     )
);

// -------------------------------------------------------
// Parser do cabeçalho WAV e extrator de amostras PCM
// -------------------------------------------------------
wire [15:0] sample_out;
wire        sample_valid;
wire        stream_done;

wav_reader u_wav_reader (
    .clk          ( CLOCK_50     ),
    .rst_n        ( rst_n        ),
    .byte_in      ( outbyte      ),
    .byte_valid   ( outen        ),
    .sample_out   ( sample_out   ),
    .sample_valid ( sample_valid ),
    .stream_done  ( stream_done  )
);

// -------------------------------------------------------
// Contador de amostras lidas (32 bits)
// -------------------------------------------------------
reg [31:0] sample_count;

always @(posedge CLOCK_50 or negedge rst_n) begin
    if (!rst_n)
        sample_count <= 32'd0;
    else if (sample_valid)
        sample_count <= sample_count + 32'd1;
end

// -------------------------------------------------------
// Alternador do LED de atividade
// -------------------------------------------------------
reg led_toggle;

always @(posedge CLOCK_50 or negedge rst_n) begin
    if (!rst_n)
        led_toggle <= 1'b0;
    else if (sample_valid)
        led_toggle <= ~led_toggle;
end

// -------------------------------------------------------
// Mapeamento dos LEDs de status
// -------------------------------------------------------
assign LEDR[0] = (card_stat >= 4'd8); // Cartão inicializado e pronto
assign LEDR[1] = file_found;          // Arquivo voice.wav localizado
assign LEDR[2] = led_toggle;          // Pisca durante a reprodução
assign LEDR[3] = stream_done;         // Fim do arquivo atingido

// -------------------------------------------------------
// Decodificador de 7 segmentos (catodo comum / ativo em baixo)
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

assign HEX0 = seg7(sample_count[3:0]);
assign HEX1 = seg7(sample_count[7:4]);

endmodule
