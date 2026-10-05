`timescale 1ns / 1ps

module tb_top_wav_sd;

    // Sinais de estímulo e controle
    reg        CLOCK_50;
    reg        KEY0;

    // Linhas físicas da interface SD
    wire       SD_CLK;
    wire       SD_CMD;
    wire       SD_DAT0;

    // Pull-ups necessários para protocolos SD/SPI (evita transições para Z/X)
    pullup(SD_CMD);
    pullup(SD_DAT0);

    // Diagnóstico visual
    wire [3:0] LEDR;
    wire [6:0] HEX0;
    wire [6:0] HEX1;

    // 1. Instanciação da UUT
    top_wav_sd uut (
        .CLOCK_50 (CLOCK_50),
        .KEY0     (KEY0),
        .SD_CLK   (SD_CLK),
        .SD_CMD   (SD_CMD),
        .SD_DAT0  (SD_DAT0),
        .LEDR     (LEDR),
        .HEX0     (HEX0),
        .HEX1     (HEX1)
    );

    // 2. Instanciação do modelo do cartão SD
    sd_card_mock u_sd_card (
        .sd_clk  (SD_CLK),
        .sd_cmd  (SD_CMD),
        .sd_dat0 (SD_DAT0)
    );

    // 3. Gerador de clock de 50 MHz (período de 20 ns)
    always #10 CLOCK_50 = ~CLOCK_50;

    // 4. Sequência principal de controle
    initial begin
        // Habilita dump para depuração visual
        $dumpfile("waveform.vcd");
        $dumpvars(0, tb_top_wav_sd);

        $display("=======================================================");
        $display("[SIMULACAO] Iniciando teste de leitura do SD Card...");
        $display("=======================================================");

        CLOCK_50 = 1'b0;

        // Pulso de reset estável (DE10-Lite: 0 = apertado/reset, 1 = solto/operando)
        KEY0 = 1'b0;
        #500;
        KEY0 = 1'b1;
        $display("[SIMULACAO @ %0t ns] Reset liberado com KEY0 = 1.", $time);

        // Tempo limite de execução (25 ms de tempo de hardware)
        #25000000;

        $display("=======================================================");
        $display("[SIMULACAO @ %0t ns] Fim do tempo programado.", $time);
        $display(" Status final dos LEDs: 4'b%b", LEDR);
        $display("=======================================================");
        $stop;
    end

    // 5. Monitores de diagnóstico em tempo real
    initial begin
        wait(LEDR[0] === 1'b1);
        $display("[SIMULACAO @ %0t ns] [SUCESSO] LEDR[0] = 1: Cartao SD inicializado!", $time);
    end

    initial begin
        wait(LEDR[1] === 1'b1);
        $display("[SIMULACAO @ %0t ns] [SUCESSO] LEDR[1] = 1: Arquivo voice.wav em leitura!", $time);
    end

    initial begin
        wait(LEDR[3] === 1'b1);
        $display("[SIMULACAO @ %0t ns] [ERRO] LEDR[3] = 1: Falha reportada pelo circuito!", $time);
        #1000;
        $finish; // Interrompe para economizar tempo de simulação
    end

endmodule