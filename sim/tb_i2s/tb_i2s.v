// ==============================================================================
// Testbench de Integração Completo: Hélio & Darth Vader em Paralelo
// Valida: SD Falso -> wav_buffer -> dsp_core -> i2s_tx -> Receptor I2S
// ==============================================================================
`timescale 1ns / 1ps

module tb_integracao;
    parameter NSAMP = 1500; // Amostras de teste (> 1102 p/ exercitar o atraso do Comb)

    // Clocks e Reset
    reg clk = 0;
    reg mclk_helio = 0;
    reg mclk_vader = 0;
    reg rst_n = 0;

    always #10.000 clk        = ~clk;        // 50 MHz (Período: 20 ns)
    always #49.210 mclk_helio = ~mclk_helio; // ~10.16 MHz (fs = 79.38 kHz c/ Ratio 128)
    always #50.400 mclk_vader = ~mclk_vader; // ~9.92 MHz  (fs = 38.76 kHz c/ Ratio 256)

    // Função geradora de sinal composto (16 bits signed)
    function integer xval; input integer i; real r;
        begin
            r = 12000.0 * $sin(6.283185307 * i / 53.0) + 6000.0 * $sin(6.283185307 * i / 11.0);
            xval = $rtoi(r);
        end
    endfunction

    // ==========================================================================
    // CANAL 1: MODO HÉLIO (MODE = 0, RATIO = 128)
    // ==========================================================================
    reg  [15:0] wr_data_h = 0;
    reg         wr_en_h = 0, eos_h = 0;
    wire        can_read_h, rd_valid_h, playable_h, finished_h, ov_h, un_h;
    wire [15:0] rd_data_h;
    wire [10:0] level_h;
    wire        req_h;
    wire        rd_en_h = req_h & playable_h & ~finished_h;

    wav_buffer #(.ADDR_W(10), .SECTOR_SAMPLES(256), .PRIME_SAMPLES(256)) u_buf_h (
        .clk(clk), .rst_n(rst_n), .wr_data(wr_data_h), .wr_en(wr_en_h), .eos(eos_h),
        .can_read(can_read_h), .rd_en(rd_en_h), .rd_data(rd_data_h), .rd_valid(rd_valid_h),
        .playable(playable_h), .finished(finished_h), .level(level_h),
        .overrun(ov_h), .underrun(un_h)
    );

    wire signed [15:0] dsp_y_h;
    wire               dsp_ov_h, dsp_busy_h;
    dsp_core #(
        .FILE_HELIO("fir_helio.hex"),
        .FILE_VADER("fir_vader.hex"),
        .FILE_TANH ("tanh_lut.hex")
    ) u_dsp_h (
        .clk(clk), .rst_n(rst_n), .sel_mode(1'b0),
        .sample_in(rd_data_h), .sample_valid(rd_valid_h),
        .busy(dsp_busy_h), .sample_out(dsp_y_h), .out_valid(dsp_ov_h)
    );

    wire signed [15:0] i2s_in_h = (playable_h & ~finished_h) ? dsp_y_h : 16'sd0;
    wire bclk_h, lrck_dh, lrck_ah, sdata_h;
    i2s_tx #(.RATIO(128)) u_tx_h (
        .clk(clk), .rst_n(rst_n), .mclk(mclk_helio), .pll_locked(1'b1),
        .sample_in(i2s_in_h), .sample_req(req_h),
        .AUD_BCLK(bclk_h), .AUD_DACLRCK(lrck_dh), .AUD_ADCLRCK(lrck_ah), .AUD_DACDAT(sdata_h)
    );

    // ==========================================================================
    // CANAL 2: MODO DARTH VADER (MODE = 1, RATIO = 256)
    // ==========================================================================
    reg  [15:0] wr_data_v = 0;
    reg         wr_en_v = 0, eos_v = 0;
    wire        can_read_v, rd_valid_v, playable_v, finished_v, ov_v, un_v;
    wire [15:0] rd_data_v;
    wire [10:0] level_v;
    wire        req_v;
    wire        rd_en_v = req_v & playable_v & ~finished_v;

    wav_buffer #(.ADDR_W(10), .SECTOR_SAMPLES(256), .PRIME_SAMPLES(256)) u_buf_v (
        .clk(clk), .rst_n(rst_n), .wr_data(wr_data_v), .wr_en(wr_en_v), .eos(eos_v),
        .can_read(can_read_v), .rd_en(rd_en_v), .rd_data(rd_data_v), .rd_valid(rd_valid_v),
        .playable(playable_v), .finished(finished_v), .level(level_v),
        .overrun(ov_v), .underrun(un_v)
    );

    wire signed [15:0] dsp_y_v;
    wire               dsp_ov_v, dsp_busy_v;
    dsp_core #(
        .FILE_HELIO("fir_helio.hex"),
        .FILE_VADER("fir_vader.hex"),
        .FILE_TANH ("tanh_lut.hex")
    ) u_dsp_v (
        .clk(clk), .rst_n(rst_n), .sel_mode(1'b1),
        .sample_in(rd_data_v), .sample_valid(rd_valid_v),
        .busy(dsp_busy_v), .sample_out(dsp_y_v), .out_valid(dsp_ov_v)
    );

    wire signed [15:0] i2s_in_v = (playable_v & ~finished_v) ? dsp_y_v : 16'sd0;
    wire bclk_v, lrck_dv, lrck_av, sdata_v;
    i2s_tx #(.RATIO(256)) u_tx_v (
        .clk(clk), .rst_n(rst_n), .mclk(mclk_vader), .pll_locked(1'b1),
        .sample_in(i2s_in_v), .sample_req(req_v),
        .AUD_BCLK(bclk_v), .AUD_DACLRCK(lrck_dv), .AUD_ADCLRCK(lrck_av), .AUD_DACDAT(sdata_v)
    );

    // ==========================================================================
    // ESTIMULOS: SD FALSO INDEPENDENTE PARA CADA CANAL
    // ==========================================================================
    integer wcnt_h = 0, burst_h = 0, gap_h = 0;
    always @(posedge clk) begin
        wr_en_h <= 1'b0;
        if (rst_n) begin
            if (burst_h > 0) begin
                wr_en_h <= 1'b1; wr_data_h <= xval(wcnt_h);
                wcnt_h <= wcnt_h + 1; burst_h <= burst_h - 1; gap_h <= 30;
                if (wcnt_h == NSAMP-1) eos_h <= 1'b1;
            end else if (gap_h > 0) gap_h <= gap_h - 1;
            else if (can_read_h && wcnt_h < NSAMP)
                burst_h <= (NSAMP - wcnt_h >= 256) ? 256 : (NSAMP - wcnt_h);
        end
    end

    integer wcnt_v = 0, burst_v = 0, gap_v = 0;
    always @(posedge clk) begin
        wr_en_v <= 1'b0;
        if (rst_n) begin
            if (burst_v > 0) begin
                wr_en_v <= 1'b1; wr_data_v <= xval(wcnt_v);
                wcnt_v <= wcnt_v + 1; burst_v <= burst_v - 1; gap_v <= 30;
                if (wcnt_v == NSAMP-1) eos_v <= 1'b1;
            end else if (gap_v > 0) gap_v <= gap_v - 1;
            else if (can_read_v && wcnt_v < NSAMP)
                burst_v <= (NSAMP - wcnt_v >= 256) ? 256 : (NSAMP - wcnt_v);
        end
    end

    // ==========================================================================
    // ARMAZENAMENTO DAS REFERÊNCIAS GERADAS PELO DSP
    // ==========================================================================
    integer nref_h = 0; integer ref_h [0:4095];
    always @(posedge clk) if (dsp_ov_h) begin ref_h[nref_h] = $signed(dsp_y_h); nref_h = nref_h + 1; end

    integer nref_v = 0; integer ref_v [0:4095];
    always @(posedge clk) if (dsp_ov_v) begin ref_v[nref_v] = $signed(dsp_y_v); nref_v = nref_v + 1; end

    // ==========================================================================
    // RECEPTORES I2S INDEPENDENTES (DECODIFICADORES)
    // ==========================================================================
    // Receptor Hélio
    reg lrck_qh = 1; integer bitcnt_h = 0, nl_h = 0, nr_h = 0;
    reg [15:0] acc_h = 0; integer rx_lh [0:4095]; integer rx_rh [0:4095];
    always @(posedge bclk_h) begin
        if (lrck_dh != lrck_qh) begin
            if (bitcnt_h >= 16) begin
                if (lrck_qh == 1'b0) begin rx_lh[nl_h] = $signed(acc_h); nl_h = nl_h + 1; end
                else                 begin rx_rh[nr_h] = $signed(acc_h); nr_h = nr_h + 1; end
            end
            bitcnt_h = 0; acc_h = 0;
        end else begin
            if (bitcnt_h < 16) acc_h = {acc_h[14:0], sdata_h};
            bitcnt_h = bitcnt_h + 1;
        end
        lrck_qh = lrck_dh;
    end

    // Receptor Vader
    reg lrck_qv = 1; integer bitcnt_v = 0, nl_v = 0, nr_v = 0;
    reg [15:0] acc_v = 0; integer rx_lv [0:4095]; integer rx_rv [0:4095];
    always @(posedge bclk_v) begin
        if (lrck_dv != lrck_qv) begin
            if (bitcnt_v >= 16) begin
                if (lrck_qv == 1'b0) begin rx_lv[nl_v] = $signed(acc_v); nl_v = nl_v + 1; end
                else                 begin rx_rv[nr_v] = $signed(acc_v); nr_v = nr_v + 1; end
            end
            bitcnt_v = 0; acc_v = 0;
        end else begin
            if (bitcnt_v < 16) acc_v = {acc_v[14:0], sdata_v};
            bitcnt_v = bitcnt_v + 1;
        end
        lrck_qv = lrck_dv;
    end

    // ==========================================================================
    // VERIFICAÇÃO DE TEMPORIZAÇÃO (MUDANÇA APENAS NA DESCIDA DO BCLK)
    // ==========================================================================
    realtime t_fall_h = -1; integer viol_h = 0;
    always @(negedge bclk_h) t_fall_h = $realtime;
    always @(sdata_h or lrck_dh) begin : chk_h
        realtime tc; tc = $realtime; #0.001;
        if (nl_h > 0 && t_fall_h != tc) viol_h = viol_h + 1;
    end

    realtime t_fall_v = -1; integer viol_v = 0;
    always @(negedge bclk_v) t_fall_v = $realtime;
    always @(sdata_v or lrck_dv) begin : chk_v
        realtime tc; tc = $realtime; #0.001;
        if (nl_v > 0 && t_fall_v != tc) viol_v = viol_v + 1;
    end

    // ==========================================================================
    // ANÁLISE DE RESULTADOS E RELATÓRIO FORMATADO
    // ==========================================================================
    integer err_h = 0, best_h = -1, nz_h = 0;
    integer err_v = 0, best_v = -1, nz_v = 0;
    integer f0, k, mm, ncmp;

    initial begin
        repeat (20) @(posedge clk);
        rst_n = 1;

        // Aguarda os dois canais terminarem a reprodução
        wait (finished_h && finished_v);
        repeat (100) @(posedge clk);
        #(256 * 2.0 * 50.400 * 50); // Esvaziamento final dos frames I2S

        ncmp = NSAMP - 5;

        // ---- Análise Hélio ----
        for (f0 = 0; f0 < 60 && best_h < 0; f0 = f0 + 1) begin
            mm = 0;
            for (k = 0; k < ncmp; k = k + 1) if (rx_lh[f0+k] !== ref_h[k]) mm = mm + 1;
            if (mm == 0) best_h = f0;
        end
        if (best_h < 0) err_h = err_h + 1;
        for (k = 0; k < ncmp; k = k + 1) begin
            if (best_h >= 0 && rx_rh[best_h+k] !== rx_lh[best_h+k]) err_h = err_h + 1;
            if (ref_h[k] != 0) nz_h = nz_h + 1;
        end
        if (nref_h < NSAMP-1) err_h = err_h + 1;
        if (ov_h || un_h)     err_h = err_h + 1;
        if (viol_h != 0)      err_h = err_h + 1;
        if (nz_h < ncmp/2)    err_h = err_h + 1;

        // ---- Análise Vader ----
        for (f0 = 0; f0 < 60 && best_v < 0; f0 = f0 + 1) begin
            mm = 0;
            for (k = 0; k < ncmp; k = k + 1) if (rx_lv[f0+k] !== ref_v[k]) mm = mm + 1;
            if (mm == 0) best_v = f0;
        end
        if (best_v < 0) err_v = err_v + 1;
        for (k = 0; k < ncmp; k = k + 1) begin
            if (best_v >= 0 && rx_rv[best_v+k] !== rx_lv[best_v+k]) err_v = err_v + 1;
            if (ref_v[k] != 0) nz_v = nz_v + 1;
        end
        if (nref_v < NSAMP-1) err_v = err_v + 1;
        if (ov_v || un_v)     err_v = err_v + 1;
        if (viol_v != 0)      err_v = err_v + 1;
        if (nz_v < ncmp/2)    err_v = err_v + 1;

        // ======================================================================
        // RELATÓRIO VISUAL DETALHADO NO TRANSCRIPT
        // ======================================================================
        $display("\n================================================================================");
     
        $display(" [1] CANAL HELIO (Voz Aguda / Pitch-Up):");
        $display("     - Frequencia de Amostragem (fs) : 79.38 kHz (Ratio MCLK/fs: 128)");
        $display("     - Amostras Calculadas no DSP    : %0d (%0d nao-nulas)", nref_h, nz_h);
        $display("     - Quadros I2S Recebidos         : L=%0d | R=%0d (Canal L == R)", nl_h, nr_h);
        $display("     - Latencia de Serializacao      : %0d amostras de atraso", best_h);
        $display("     - Violacoes de Timing no BCLK   : %0d falhas", viol_h);
        $display("     - Overrun / Underrun do Buffer  : %0b / %0b", ov_h, un_h);
        if (err_h == 0)
            $display("     --> STATUS: [ PASS ] - Validado com sucesso!");
        else
            $display("     --> STATUS: [ FAIL ] - Encontrados %0d erros neste canal", err_h);

        $display("--------------------------------------------------------------------------------");
        $display(" [2] CANAL DARTH VADER (Voz Grave + Comb Filter / Eco):");
        $display("     - Frequencia de Amostragem (fs) : 38.76 kHz (Ratio MCLK/fs: 256)");
        $display("     - Amostras Calculadas no DSP    : %0d (%0d nao-nulas)", nref_v, nz_v);
        $display("     - Quadros I2S Recebidos         : L=%0d | R=%0d (Canal L == R)", nl_v, nr_v);
        $display("     - Latencia de Serializacao      : %0d amostras de atraso", best_v);
        $display("     - Violacoes de Timing no BCLK   : %0d falhas", viol_v);
        $display("     - Overrun / Underrun do Buffer  : %0b / %0b", ov_v, un_v);
        if (err_v == 0)
            $display("     --> STATUS: [ PASS ] - Validado com sucesso!");
        else
            $display("     --> STATUS: [ FAIL ] - Encontrados %0d erros neste canal", err_v);

        $display("================================================================================");
        if ((err_h + err_v) == 0)
            $display(" Resultado Final: Pass");
        else
            $display(" Resultado Final: Fail (%0d erros no total)", err_h + err_v);
        $display("================================================================================\n");

        $stop;
    end

    initial begin #1_500_000_000; $display("TIMEOUT: Simulacao excedeu o limite de tempo"); $finish; end
endmodule