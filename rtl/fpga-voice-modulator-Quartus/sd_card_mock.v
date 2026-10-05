`timescale 1ns / 1ps

module sd_card_mock (
    input  wire sd_clk,
    inout  wire sd_cmd,
    inout  wire sd_dat0
);

    // Resistores de pull-up do barramento SD
    pullup(sd_cmd);
    pullup(sd_dat0);

    reg cmd_out = 1'b1;
    reg cmd_oe  = 1'b0;
    assign sd_cmd = cmd_oe ? cmd_out : 1'bz;

    reg dat_out = 1'b1;
    reg dat_oe  = 1'b0;
    assign sd_dat0 = dat_oe ? dat_out : 1'bz;

    reg [47:0] cmd_frame;
    reg [5:0]  cmd_idx;
    reg [31:0] cmd_arg;
    reg        app_cmd_flag = 1'b0;
    reg [15:0] rca = 16'h0001;

    integer file_fd;
    reg [7:0] sector_mem [0:511];
    integer i;

    initial begin
        // Busca o arquivo sd_image.img na pasta relativa ou nas pastas padrões
        file_fd = $fopen("sd_image.img", "rb");
        if (file_fd == 0) begin
            file_fd = $fopen("D:/LABIII/sd_image.img", "rb");
        end
        if (file_fd == 0) begin
            file_fd = $fopen("simulation/modelsim/sd_image.img", "rb");
        end

        if (file_fd == 0) begin
            $display("[SD MOCK ERRO] 'sd_image.img' nao encontrado!");
        end else begin
            $display("[SD MOCK OK] 'sd_image.img' carregado com sucesso.");
        end
    end

    // Tarefa de envio de respostas de 48 bits (R1, R3, R7)
    task send_response_48;
        input [47:0] resp;
        integer b;
        begin
            @(negedge sd_clk);
            cmd_oe = 1'b1;
            for (b = 47; b >= 0; b = b - 1) begin
                cmd_out = resp[b];
                @(negedge sd_clk);
            end
            cmd_oe = 1'b0;
            cmd_out = 1'b1;
        end
    endtask

    // Tarefa de transmissão sequencial do setor de 512 bytes no SD_DAT0
    task send_data_block;
        input [31:0] sector_addr;
        integer byte_idx, bit_idx;
        integer seek_status, read_count;
        begin
            if (file_fd != 0) begin
                seek_status = $fseek(file_fd, sector_addr * 512, 0);
                read_count  = $fread(sector_mem, file_fd);
            end

            // Tempo de espera do cartão (Nac)
            repeat (8) @(negedge sd_clk);
            dat_oe  = 1'b1;
            dat_out = 1'b0; // Start bit
            @(negedge sd_clk);

            // Envio serial dos 512 bytes
            for (byte_idx = 0; byte_idx < 512; byte_idx = byte_idx + 1) begin
                for (bit_idx = 7; bit_idx >= 0; bit_idx = bit_idx - 1) begin
                    dat_out = sector_mem[byte_idx][bit_idx];
                    @(negedge sd_clk);
                end
            end

            // 16 bits de CRC dummy
            repeat (16) begin
                dat_out = 1'b0;
                @(negedge sd_clk);
            end

            dat_out = 1'b1; // Stop bit
            @(negedge sd_clk);
            dat_oe  = 1'b0;
        end
    endtask

    // Receptor e decodificador de comandos do FPGA
    always begin
        @(posedge sd_clk);
        if (sd_cmd == 1'b0) begin
            cmd_frame[47] = 1'b0;
            for (i = 46; i >= 0; i = i - 1) begin
                @(posedge sd_clk);
                cmd_frame[i] = sd_cmd;
            end

            cmd_idx = cmd_frame[45:40];
            cmd_arg = cmd_frame[39:8];

            repeat (2) @(negedge sd_clk);

            case (cmd_idx)
                6'd0: begin
                    app_cmd_flag = 1'b0;
                end
                6'd8: begin
                    send_response_48({2'b00, 6'd8, 20'h0, 4'b0001, cmd_arg[7:0], 7'h01, 1'b1});
                end
                6'd55: begin
                    app_cmd_flag = 1'b1;
                    send_response_48({2'b00, 6'd55, 32'h00000120, 7'h01, 1'b1});
                end
                6'd41: begin
                    if (app_cmd_flag) begin
                        app_cmd_flag = 1'b0;
                        send_response_48({2'b00, 6'b111111, 32'hC0FF8000, 7'h7F, 1'b1});
                    end
                end
                6'd2: begin
                    send_response_48({2'b00, 6'd2, 32'h00000000, 7'h01, 1'b1});
                end
                6'd3: begin
                    send_response_48({2'b00, 6'd3, rca, 16'h0000, 7'h01, 1'b1});
                end
                6'd7: begin
                    send_response_48({2'b00, 6'd7, 32'h00000900, 7'h01, 1'b1});
                end
                6'd16: begin
                    send_response_48({2'b00, 6'd16, 32'h00000900, 7'h01, 1'b1});
                end
                6'd17, 6'd18: begin
                    $display("[SD MOCK @ %0t ns] Leitura do setor LBA = %0d solicitada", $time, cmd_arg);
                    send_response_48({2'b00, cmd_idx, 32'h00000900, 7'h01, 1'b1});
                    send_data_block(cmd_arg);
                end
                default: begin
                    send_response_48({2'b00, cmd_idx, 32'h00000900, 7'h01, 1'b1});
                end
            endcase
        end
    end

endmodule