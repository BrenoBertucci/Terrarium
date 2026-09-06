# Combate dinâmico — concepts (telas flutuantes estilo Clair Obscur)

Gerados em 2026-08-30 via Meshy text-to-image (`nano-banana-pro`, 16:9). Direção:
a UI sai do rect GB 160x48 e vira painéis de vidro diegéticos, inclinados em
perspectiva DENTRO do diorama voxel, com câmera de batalha cinematográfica.

## Os 4 concepts e onde cada um encosta no código

### 01-arena-wide.png — layout geral da batalha — IMPLEMENTADO (lib/BattlePanelsXY.lua, 2026-08-30)
Painel de mensagem à esquerda + cluster FIGHT/BAG/POKEMON/RUN à direita, ambos
flutuando no mundo 3D; cápsulas de HP flutuam sobre cada mon, levemente rotacionadas
para a câmera.
- Hoje isso vive em `OverworldBattle.drawXYBlock` + `lib/BattleBoxXY.lua` (tudo
  dentro do rect do box) e `lib/BattleHudXY.lua` (cápsulas). O concept mantém a
  MESMA divisão msg/cluster do redesign compacto — só ancora no espaço 3D.
- Lembrete: o prompt "What will X do?" é desenhado pelo layout do engine
  (`WideBattle.drawWide`), não vem de `battle.current.text`.

### 02-move-cards.png — moveSelect em leque 3D — IMPLEMENTADO (lib/BattleFanXY.lua, 2026-08-30)
As 4 fileiras de golpes viram cartas em leque em perspectiva; card de info à
esquerda (descrição/categoria); carta selecionada avança e brilha.
- Dados já existem: `player.curMoves` `{id, pp, ppUps}`, `battle.data.moves[id]`
  → `{name, type, pp, power, category}`, `TypeChart.displayName` casa com os PNGs
  de `assets/battlexy/types/`.
- Regra que já custou caro: cor de tipo translúcida precisa de slab escuro por
  baixo, e texto branco sobre cor precisa de sombra.

### 03-attack-moment.png — câmera dinâmica no golpe — IMPLEMENTADO (lib/BattleShot.lua, 2026-08-30)
Câmera orbital baixa no momento do impacto, painel de dano flutuante, painéis
com parallax (inclinam "empurrados" pela ação), HP do alvo drenando.
- A câmera do diorama vive em `BattleScene.render()` (`lib/BattleScene.lua:334`).
  A receita para a câmera dinâmica está no doc da câmera do SM64
  (`~/Downloads/camera-super-mario-64.md`): duas camadas (alvo geométrico vs
  perseguidor com inércia), velocidades assimétricas (foco 0.8 / posição 0.3,
  convertidas por `k' = 1 - pow(1-k, dt*30)`), transições interpoladas em
  coordenadas esféricas (dist/pitch/yaw — a câmera arqueia, não corta caminho),
  shake como offset PÓS-suavização com decay, modo "boss fight" com segundo foco
  para enquadrar os dois mons.
- Parallax dos painéis = offset do painel em função da velocidade angular da
  câmera. Barato e vende o efeito inteiro.

### 04-turn-ribbon.png — ribbon de turnos — IMPLEMENTADO (lib/BattleRibbon.lua, 2026-08-31; o anel de timing segue fase 2, fora por tocar resolução de dano)
Fita de vidro em arco com medalhões de ordem de turno; anel luminoso de timing
(estilo parry do Clair Obscur) ao redor do mon ativo; mensagem em painel fino.
- Gen 1 decide ordem por speed na escolha simultânea — não há timeline real de
  vários turnos. O ribbon seria PREVISÃO (player/enemy alternando), presentational.
- O anel de timing é a parte mais invasiva (mexe em resolução de dano); tratar
  como fase 2 separada, atrás de toggle.

### 05/06/07 — redesign dos painéis (2026-08-30, segunda rodada)
A primeira implementação dos painéis ficou feia (laje preta opaca com espaço
morto; chips de meia-cápsula boiando em slab cinza sem borda). Os concepts
05 (menu in-scene), 06 (mensagem in-scene) e 07 (**folha de UI kit — o spec
acionável**) corrigem a linguagem:
- Painel de mensagem: vidro fosco CLARO (mundo aparece atrás), **justo no
  texto** (auto-size, sem área morta), borda luminosa fina + cantoneiras
  douradas, acento de sublinhado dourado, texto maior.
- Botões: cápsulas INTEIRAS com o rótulo dentro (abandonar a arte de
  meia-cápsula do pack), vidro tintado + rim luminoso na cor do comando;
  selecionado = rim dourado + bloom + brilho interno; apagado = rim fino
  cinza e cor dessaturada.
- Mesmo raio de canto e tratamento de borda em painel, chips e cartas.

### 08/09/10 — redesign das cápsulas de HP — IMPLEMENTADO (lib/BattleCapsule.lua + bake Blender, 2026-08-31; vidro realocado: frost real na caixa de diálogo, barras como luz)
As cápsulas de nome/Lv/HP ainda eram os frames cinza do pack 5X, com a
barra de XP órfã boiando solta. Os concepts 08 (in-scene), 09 (close-up do
painel do jogador) e 10 (**folha de kit com estados**) trazem o HUD para a
mesma linguagem de vidro dos 05-07:
- Painel de vidro claro com borda luminosa + cantoneiras douradas; nome em
  pixel branco com outline; **Lv. em dourado** (o acento único do kit).
- **HP = líquido luminoso num tubo de vidro** (trough) com ticks gravados
  em 1/2 e 1/4; verde → âmbar → vermelho, o vermelho com pulso de glow;
  dígitos 97/97 em pixel sobre/ao lado da barra.
- **XP = filamento âmbar fino INTEGRADO à base do painel** com cap "EXP" —
  mata de vez a barra azul órfã.
- Status (PSN/PAR/SLP/BRN/FRZ) = tags redondas de vidro colorido clipadas
  na borda do painel.
- Inimigo = variante compacta sem dígitos. In-scene: os painéis flutuam
  inclinados perto de cada mon (ancoragem via rig, como o resto do kit).

## Rodada de 2026-09-02 — o golpe chega no ambiente e no vidro (SEM concepts novos)
O Breno pediu para não gastar Meshy nesta rodada; a referência continua o 03
(attack-moment: painel de dano flutuante, painéis empurrados pela ação) e o
que foi implementado direto no código:
- **Ambiente** (`lib/BattleHitFX.lua`): holofote no atacante durante o golpe
  (cantos escurecem), flash na cor do tipo no defensor (chão incluso),
  cubos de voxel arrancados do chão, e MARCA no piso por tipo (queimado /
  poça / gelo / cratera / poeira) desenhada dentro do passe 3D, sob os pés.
- **Número de dano**: o "38" dourado do concept 03 — lido da própria barra
  (`shownHP` do frame anterior menos `hp`), sobe do ombro do defensor.
- **Vidro** (`lib/BattleGlassFX.lua`): os painéis GIRAM com o empurrão (yaw),
  a frente da onda deixa rachaduras (físico) ou anéis na cor (elemental) no
  ponto mais próximo do golpe, e cada painel projeta sombra de contato no chão.
- Lição de timing que valeu a rodada: o engine grava o HP novo ~1 s ANTES da
  animação; o tell do impacto agora é o FIM da animação com drain pendente.

### 11/12 — caixa de diálogo e menu em vidro FUMÊ (2026-09-02, +18 créditos)
O Breno reprovou a caixa clara ("muito feia"); as cápsulas de nome/HP/EXP
(B2W2) ficam como estão. O 11 (in-scene) e o **12 (folha de kit com estados —
o spec acionável)** trazem caixa e chips para a linguagem escura das cápsulas:
- Caixa: vidro fumê escuro, gloss diagonal no topo, rim fino claro, cantoneiras
  douradas em L, sublinhado dourado, texto branco pixel sem outline; estado
  "typing" = caret dourado.
- Chips: cápsulas inteiras de vidro tintado (vermelho LUTAR; âmbar ITENS, azul
  FUGIR, verde PKMN), rim dourado + glow no selecionado; apagado = mesma cor
  bem escurecida, rim fino, sem brilho.
- A caixa já foi refeita nesse espírito (`BattlePanelsXY.drawMsgFace`); os
  chips ainda estão no kit claro 05-07 — o 12 é o alvo para eles.
- O 11 alucinou um quinto botão ("FTHAR"): ignorar; o cluster tem 4.

### 13/14 — a mesma caixa e menu, "mais ala Pokémon" (2026-09-02, +18 créditos)
A pedido, o kit fumê ganhou identidade Pokémon sem virar cópia do Game Boy:
- **Caixa (13 e 14)**: borda DUPLA do text box de Gen 1 reinterpretada como
  dois traços finos claros no vidro fumê; emblema de Poké Ball no canto
  superior esquerdo; a seta "▼" de avançar no canto inferior direito no lugar
  do caret (typing = a seta pisca junto ao fim do texto).
- **Chips (13)**: cápsulas como Poké Ball vista de lado — metade de cima na
  cor do comando, metade de baixo escura, linha de divisa; selecionado =
  rim dourado + glow + Poké Ball pixel como cursor à esquerda.
- **Chips (14, variação)**: cápsula escura com uma Poké Ball tintada na cor
  do comando como ícone à esquerda do rótulo — a mais legível das duas e a
  mais fácil de desenhar (o pack já tem a bola; `BattleNav.draw` já anima o
  hop dela como cursor).
- **APLICADO (2026-09-02): caixa do 13 + chips do 14** em
  `BattlePanelsXY.drawMsgFace` / `drawButtonFace` (Poké Ball e seta ▼ por
  primitivas: `pokeBall`, `advanceArrow`). Cápsulas de HP intocadas.

### 15/16 — o card de golpe vestindo FOGO e ÁGUA, três intensidades (2026-09-02, +18)
Depois de duas rodadas de código reprovadas (primitivas "quadradas"; sheets do
Pimen em grade "too much"), o Breno pediu concepts. Cada folha tem o MESMO card
fumê em SUBTLE / MEDIUM / FULL, texto legível nos três:
- **Fogo (15)**: subtle = brasas flutuando + glow quente atrás do vidro;
  medium = chamas pixel lambendo as bordas por dentro do rim laranja, o
  centro limpo; full = labaredas subindo do pé até o topo, calor no fundo.
- **Água (16)**: subtle = gotas escorrendo no vidro + glow azul; medium = o
  card como tanque de vidro meio cheio, linha d'água, bolhas, cáusticas;
  full = água até o topo com respingos no rim.
- **APLICADO MEDIUM nos dois** (`lib/BattleCardFX.lua`, TYPES.FIRE / WATER):
  fogo = franja de 21 chamas pequenas encadeadas (9 no pé, 6 em cada lateral
  afinando até meia altura, alternadas espelhadas) dentro de um rim laranja
  incandescente (`rim`), sem rajadas; água = `fill` a 56% com linha d'água,
  7 bolhas subindo, 3 arcos de cáustica no fundo e respingo ocasional.
  Centro do card livre nos dois.

## Regras de geração aprendidas (para próximas rodadas)
- `aspect_ratio: "16:9"` é aceito pelo endpoint text-to-image.
- Texto de UI que deve aparecer na imagem: escrever ENTRE ASPAS o texto exato,
  senão o modelo renderiza a descrição literal ("Slim floating message panel").
- Nunca pedir "screenshot mockup" — gera moldura preta. Pedir "full-bleed, no
  border, no letterboxing".
- MCP do Meshy segue caindo (timeout); a rota confiável é REST
  (`POST api.meshy.ai/openapi/v1/text-to-image`, poll em `/{id}`, 9 créditos/img).
