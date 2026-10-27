// ==============================================================================
// Módulo   : fir_rom.v
// Pasta    : rtl/dsp/
// Função   : Armazena os 101 coeficientes Q15 dos filtros Hélio e Darth Vader.
// ==============================================================================

`timescale 1ns / 1ps

module fir_rom #(
    parameter NUM_TAPS    = 101,
    parameter ADDR_WIDTH  = 7,
    // Caminhos padrão configuráveis (podem ser ajustados no testbench ou no Quartus)
    parameter FILE_HELIO  = "../../rtl/rom/fir_helio.hex",
    parameter FILE_VADER  = "../../rtl/rom/fir_vader.hex"
)(
    input  wire [ADDR_WIDTH-1:0] addr,       // Endereço 0 a 100
    input  wire                  sel_filter, // 0 = Hélio, 1 = Vader
    output wire signed [15:0]    coeff_data  // Coeficiente h[k] em Q15
);

    reg signed [15:0] rom_helio [0:127];
    reg signed [15:0] rom_vader [0:127];

    integer i;
    initial begin
        // Inicializa com zeros
        for (i = 0; i < 128; i = i + 1) begin
            rom_helio[i] = 16'sh0000;
            rom_vader[i] = 16'sh0000;
        end

        // Carrega os coeficientes gerados pelo Python
        $readmemh(FILE_HELIO, rom_helio);
        $readmemh(FILE_VADER, rom_vader);
    end

    // Leitura combinacional: entrega o coeficiente no mesmo ciclo do endereço
    assign coeff_data = (sel_filter == 1'b0) ? rom_helio[addr] : rom_vader[addr];

endmodule