# Gen 1 Modern — UI pack

Prancha visual de interface para Terrarium, inspirada nos RPGs de captura de monstros da primeira geração, com painéis marfim, contornos escuros e detalhes verde-sálvia.

## Conteúdo

- Dois painéis de status.
- Caixa de diálogo e menu de comandos 2 × 2.
- Botões normal, selecionado, pressionado e desabilitado.
- Barras de HP vazio, alto, médio e crítico; barra de XP.
- Cursores, indicadores de carga, marcadores de equipe e seis ícones elementais.

## Estado da entrega

`ui-pack.png` é um atlas de 1536 × 1024 pixels com transparência, integrado em `lib/BattleHudXY.lua` por quads e nine-slice, sem duplicação de texturas. O tema é usado nos status, barras de HP/XP, carga, mensagens, comandos e cartas de ataque. Os demais sprites permanecem disponíveis no atlas.

`BattleFanXY.lua` organiza cada carta em faixas para tipo, título, categoria/precisão, poder/custo e PP. A seleção usa marcador e elevação moderada. Estados sem PP, desabilitado e sem carga têm avisos textuais; poder variável usa `VAR` em vez do valor sentinela 1 do motor.

As animações usam `BattleCardFX.drawModern`: sprites existentes em escala pequena, ciclos defasados por carta e transições suaves, sem brilho aditivo cobrindo a face. Elétrico tem descargas curtas, água tem ondas e respingos, fogo tem pequenas chamas, planta tem folhas, gelo tem cristais; os 15 tipos da geração 1 têm tratamento próprio. Cartas não selecionadas ficam discretas; cartas desabilitadas ficam estáticas. O compositor restaura as faixas de leitura depois dos efeitos, preservando os pixels dos textos e medidores. Cada carta reutiliza seu canvas.

Verificação no build de PC: `tests/gen1_ui_probe.lua`, executado por `POKEPORT_DRIVER`, com resultados e capturas em `probe_out_gen1_ui`. A fonte de verdade continua na pasta do mod; os quatro módulos alterados e este atlas também são copiados para `mods/TERRARIUM` no build de PC.

## Direção de integração

Renderizar textos dinamicamente: nome no alto à esquerda, nível à direita, HP na linha seguinte e carga abaixo. Usar texto escuro sobre marfim. Conservar margens internas generosas. Usar números de HP além da cor. Reservar verde, amarelo e vermelho para estados. Preferir filtro nearest-neighbor e escala inteira após ajuste das peças à resolução lógica do jogo. Painéis devem ser preparados para nine-slice para evitar distorção das bordas.

## Geração

Ferramenta: image_gen integrada, sem CLI. Os prompts completos estão em `prompts.txt`.
