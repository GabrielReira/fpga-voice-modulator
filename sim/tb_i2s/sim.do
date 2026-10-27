vlib work
vmap work work

# 1. Módulos I2S
vlog -work work i2s_clk_gen.v
vlog -work work i2s_serializer.v
vlog -work work i2s_tx.v

# 2. Buffer
vlog -work work wav_buffer.v

# 3. DSP
vlog -work work fir_rom.v
vlog -work work fir_mac.v
vlog -work work comb_filter.v
vlog -work work tanh_lut.v
vlog -work work dsp_core.v

# 4. Testbench com os dois canais paralelos
vlog -work work tb_i2s.v

# 5. Inicialização da simulação
vsim -t 1ps -lib work tb_integracao

# 6. Formas de Onda
add wave -divider "CLOCKS GERAIS & RESET"
add wave -color Yellow  /tb_integracao/clk
add wave -color Red     /tb_integracao/rst_n

add wave -divider "CANAL 1: HELIO"
add wave -color Orange  /tb_integracao/mclk_helio
add wave -color Cyan    /tb_integracao/can_read_h
add wave -color Green   /tb_integracao/playable_h
add wave -color Magenta /tb_integracao/req_h
add wave -color White -radix decimal /tb_integracao/dsp_y_h
add wave -color Yellow  /tb_integracao/bclk_h
add wave -color Blue    /tb_integracao/lrck_dh
add wave -color White   /tb_integracao/sdata_h

add wave -divider "CANAL 2: VADER"
add wave -color Orange  /tb_integracao/mclk_vader
add wave -color Cyan    /tb_integracao/can_read_v
add wave -color Green   /tb_integracao/playable_v
add wave -color Magenta /tb_integracao/req_v
add wave -color White -radix decimal /tb_integracao/dsp_y_v
add wave -color Yellow  /tb_integracao/bclk_v
add wave -color Blue    /tb_integracao/lrck_dv
add wave -color White   /tb_integracao/sdata_v

run -all
wave zoomfull