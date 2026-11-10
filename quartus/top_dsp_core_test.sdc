#**************************************************************
# Time Information
#**************************************************************
set_time_format -unit ns -decimal_places 3

#**************************************************************
# 1. Clock Mestre de 50 MHz da DE2-115 (Pino Y2, periodo 20.000 ns)
#**************************************************************
create_clock -name CLOCK_50 -period 20.000 -waveform { 0.000 10.000 } [get_ports CLOCK_50]

#**************************************************************
# 2. Incerteza de Clock
# Setup: 100 ps de margem. Hold: 0.000 ns (mesmo dominio de relogio).
#**************************************************************
set_clock_uncertainty -setup 0.100 -from [get_clocks CLOCK_50] -to [get_clocks CLOCK_50]
set_clock_uncertainty -hold  0.000 -from [get_clocks CLOCK_50] -to [get_clocks CLOCK_50]

#**************************************************************
# 3. Caminhos Falsos (False Paths)
# Botoes/chaves (assincronos, ja sincronizados no top) e LEDs/HEX (saidas lentas)
#**************************************************************
set_false_path -from [get_ports {KEY*}]
set_false_path -from [get_ports {SW*}]
set_false_path -to   [get_ports {LEDR[*]}]
set_false_path -to   [get_ports {HEX*[*]}]
