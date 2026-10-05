#**************************************************************
# Time Information
#**************************************************************
set_time_format -unit ns -decimal_places 3

#**************************************************************
# 1. Clock Mestre de 50 MHz (Periodo de 20.000 ns)
#**************************************************************
create_clock -name CLOCK_50 -period 20.000 -waveform { 0.000 10.000 } [get_ports CLOCK_50]

#**************************************************************
# 2. Incerteza de Clock (Clock Uncertainty)
# Forcamos Hold = 0.000 ns para impedir a deducao artificial
# de picossegundos no mesmo dominio de relogio.
#**************************************************************
set_clock_uncertainty -setup 0.100 -from [get_clocks CLOCK_50] -to [get_clocks CLOCK_50]
set_clock_uncertainty -hold  0.000 -from [get_clocks CLOCK_50] -to [get_clocks CLOCK_50]

#**************************************************************
# 3. Caminhos Falsos (False Paths)
# Isola sinais assincronos e perifericos lentos da analise de 50 MHz
#**************************************************************
set_false_path -from [get_ports {KEY*}]
set_false_path -to   [get_ports {LEDR[*]}]
set_false_path -to   [get_ports {HEX*[*]}]
set_false_path -from [get_ports {SD_*}]
set_false_path -to   [get_ports {SD_*}]