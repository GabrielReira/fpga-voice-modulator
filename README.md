# Modulador de voz baseado em FPGA com efeitos de alteração de tom

Este repositório contém a implementação de um sistema embarcado de processamento digital de sinais (PDS) para modulação de voz desenvolvido como projeto da disciplina Laboratório Integrado III-A.

O sistema lê arquivos de áudio `.wav` de um cartão SD, processa os dados em hardware dedicado e reproduz o som modificado através do codec de áudio da placa.

## Diagrama de fluxo

![](/docs/diagrama_fluxo.svg)

## FPGA SDcard File Reader
Créditos: https://github.com/WangXuan95/FPGA-SDcard-Reader

## Pinos FPGA

| Sinal | Pino DE2-115 | Direção |
| --- | --- | --- |
| SD_CLK | PIN_AE13 | output |
| SD_CMD | PIN_AD14 | inout |
| SD_DAT0 | PIN_AE14 | input |
| CLOCK_50 | PIN_Y2 | input |
| KEY0 | PIN_M23 | input |
| SW[0] | PIN_AB28 | input |
| SW[1] | PIN_AC28 | input |
| LEDR[0..3] | PIN_G19, F19, E19, F21 | output |
| LEDR[4..7] | PIN_F18, E18, J19, H19 | output |
| HEX0[0..6] | PIN_G18, F22, E17, L26, L25, J22, H22 | output |
| HEX1[0..6] | PIN_M24, Y22, W21, W22, W25, U23, U24 | output |
| HEX2[0..6] | PIN_AA25, AA26, Y25, W26, Y26, W27, W28 | output |
| HEX3[0..6] | PIN_V21, U21, AB20, AA21, AD24, AF23, Y19 | output |

## Pastas

```
voice-modulator/
├── README.md
├── .gitignore
├── docs/                    # diagramas, relatórios
│   └── diagrama_fluxo.svg
├── python/                  # modelo de referência e geração de arquivos
│   └── pipeline_pds.ipynb
├── audios/                  # WAVs de teste que vão para o cartão SD
├── rtl/                     # tudo que sintetiza
│   ├── top/                 # tops: top_wav_sd.v, top_wav_buf_test.v, depois top_voice_modulator.v
│   ├── sd/                  # sd_file_reader.v, sd_reader.v, sdcmd_ctrl.v
│   ├── wav/                 # wav_reader.v, wav_buffer.v
│   ├── dsp/                 # fir_mac.v, tanh_lut.v, comb_filter.v, effect_mux.v, dsp_core.v
│   ├── audio/               # i2s_tx.v, audio_clk_gen (PLL)
│   └── rom/                 # fir_helio.hex, fir_vader.hex, tanh_lut.hex (gerados pelo Python)
├── sim/
│   ├── tb/                  # tb_wav_buffer.v, tb_wav_chain.v, depois um tb por módulo
│   └── vectors/             # vetores de entrada/saída esperados (do Python)
├── quartus/                 # .qpf/.qsf, pinos da DE2-115, .sdc
└── nios/                    # sistema Platform Designer e software em C (I2C do WM8731)
```
