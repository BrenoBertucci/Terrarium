# Premium Building Kit — plano técnico

Decidido em sessão (2026-08-17), após grilling: o pior ofensor visual do mod são
os prédios (fachada chapada), o alvo é **diorama voxel rico**, com estas regras:

1. Paleta GB intocável na textura — riqueza vem de luz e geometria.
2. Geometria nova via **kit paramétrico** dirigido pelo band table.
3. B30 (Torre Pokémon) e B19 (Indigo Plateau) entram; B32 (navio) não.
4. PC pode pagar até ~10% de frame em efeitos por-frame; todo o resto é bake.
5. Mobile recebe o tier cozido (geometria + AO baked), nada por-frame.
6. Ordem de corte: sombra de beiral → janelas vivas → MEDIR → luz de porta → rim.
7. Aplicação global desde o dia 1, validada contra um set fixo de screenshots
   (Pallet, Lavender, Vermilion, Celadon) capturado ANTES de qualquer mudança.

## O que a leitura do código mudou no plano

**Três coisas já existem e barateiam tudo:**

- **Shadow map real** (`lib/ShadowMap.lua`): o terreno inteiro já projeta e
  recebe sombra — "sombra sobe parede, drapeja sobre telhado". Um beiral que
  EXISTIR em geometria já projeta sombra na fachada de graça. O custo dos 10%
  só entra se o sol se MOVER (hoje `KX=-0.85, KZ=-0.55` são constantes; sol
  fixo no sudeste).
- **Janelas já acendem à noite**: `GlassMask` marca texels de vidro por
  tileset; o shader em `lib/Voxel3D.lua` (~L1603-1642) levanta os panes com
  `glassNight` + cor de lampião + glint de viagem, e já agrupa texels em
  `paneId`. "Janelas vivas" é um upgrade de shader, não uma feature nova.
- **AO parcial + shade por canto já fluem de ponta a ponta**:
  `ChunkMesher.groundShades()` (AO de contato com o chão) e `sideShades()`
  (AO de vinco/flanco do terreno) já existem, e `q.shade` aceita **tabela de 4
  cantos** até o `VertexShade` do formato de vértice. O slot do AO cozido já
  está no formato — nenhum byte novo por vértice.

**Uma coisa custa mais do que parecia:** "sombra acompanhando o sol" exige
animar `KX/KZ`, o que (a) invalida o `FACE_SHADE` cozido por face, (b) força
re-render do shadow pass a cada passo do sol, e (c) briga com a razão KX/KZ
escolhida de propósito para a sombra do personagem não sumir atrás do próprio
slab do sprite. Vira a ÚLTIMA fase medida, não a primeira.

## Data flow (onde o kit se pendura)

```
data/voxel_heights.lua (template/band table)
  → Buildings.read()     sprite → silhueta (flood fill)
  → Buildings.measure()  top profile, recess panes, interior, shadeTexel
  → Buildings.model()    at(x,y,z) puro → índice de pixel do sprite   ← FASE 1 e 5
  → Buildings.emit()     shell cull + greedy merge, SHADE por face    ← FASE 2 (AO)
  → Buildings.stamp()    → S.objectQuads (q.own=true)
  → ChunkMesher (~L919)  push(quad, uv, groundShades(q, q.shade))     ← FASE 2 (compor)
  → Voxel3D.FORMAT       VertexShade (1 float, sinal = flag "up")
  → SHADER               glass block (janelas)                        ← FASE 4
ShadowMap.lua             sol, sombras reais                          ← FASE 6
Quality.lua               tiers (mobile herda daqui)
```

Modelos são cacheados por `tileset:index` e reusados por placement — o custo de
bake do kit é pago UMA vez por template, não 144 vezes. `BuildBudget.tick()`
já amortiza qualquer loop novo.

## Fases

### F0 — Baseline e probes (antes de qualquer pixel mudar)
- Set fixo de screenshots de referência: Pallet, Lavender, Vermilion, Celadon,
  em 3 horas do ciclo (manhã/meio-dia/noite), pelo rig A/B offscreen existente.
- Probe de perf no i3: frame time médio + p95 nas 4 cidades. O teto de 10% é
  medido contra ESTE número.
- `Buildings.stats()` dump (voxels/shell/quads por modelo) — o orçamento de
  crescimento de mesh das fases seguintes compara contra isto.
- `tools/building_voxels.py` (Stage 5 da metodologia) roda verde antes.

### F1 — Kit paramétrico de geometria (bake, custo runtime ~zero)
Campos novos OPCIONAIS no template + defaults globais aplicados a todos:
- `eaveOut` — beiral projeta N voxels nas LATERAIS e atrás (hoje só
  `frontEave` na frente). No `model()`: estender o sólido do telhado além de
  `x0d..x1d`/`rz0..rz1`, rim/fascia realocados para a borda estendida.
- `recessDepth` — janela afunda 2 voxels em vez de 1 (hoje `recess` só fura
  `z == D-1`). Cap pela espessura da parede.
- `sill` — peitoril: 1 voxel saliente na linha logo abaixo de cada região de
  recess detectada pelo `measure()`, vestindo `shadeTexel[DARK]`.
- `chimney = {x, z, w, h}` — caixa opcional sobre o telhado, paleta do
  próprio sprite via `shadeTexel`, por flag (nunca default).
Tudo entra como cláusulas novas no `at()` — função pura, `emit()` não muda
(shell cull digere qualquer forma).
**Risco nomeado:** `eaveOut` × edge keep-rules do mesher. Precedente: o
`frontEave` já causou o bug do "ring scrap" e foi resolvido com `q.own` —
laterais herdam a mesma isenção.
**Probe:** contagem de quads por modelo (orçamento: crescer ≤ ~30%);
screenshot A/B das 4 cidades.

### F2 — AO cozido nos prédios (bake)
- No `emit()`, PÓS-merge: para cada canto de quad mesclado, amostrar os 3
  vizinhos de voxel via `m.at()` (AO voxel clássico) → `shade` vira tabela de
  4 cantos. Beiral escurece a fachada sob ele, vincos e pés de parede assentam.
- **Armadilha 1 (por que pós-merge):** o greedy merge só colapsa runs de shade
  IGUAL; AO por canto computado antes do merge fragmentaria a malha. Nos
  cantos do quad JÁ mesclado, o custo é ~4 lookups × #quads e a malha não
  cresce um quad.
- **Armadilha 2:** `groundShades()` faz early-return quando `q.shade` já é
  tabela — o AO de contato com o chão seria PERDIDO nos prédios. Compor:
  multiplicar o fator de chão dentro da tabela em vez de retornar cedo (sem
  quebrar os props que hoje dependem do early-return).
- Atualizar expectativas do `tools/building_voxels.py`.
**Probe:** A/B com AO on/off; verificação de que mobile renderiza idêntico
(é tudo vertex data).

### F3 — Sombra de beiral, componente ESTÁTICO (grátis)
Nada a codar: com `eaveOut` da F1, o shadow map existente projeta a sombra do
beiral na fachada sozinho. Esta fase é só o probe que PROVA isso (screenshot
com beiral vs sem, mesma hora) — e é o gate da F6: se a sombra estática já
vende o volume, o sol móvel pode nem ser necessário.

### F4 — Janelas vivas (shader, custo ~zero)
No glass block do shader de `Voxel3D.lua`:
- hash de `paneId` → ~30% das janelas ficam apagadas à noite (varia por prédio
  porque o paneId é derivado do atlas + posição);
- intensidade do lampião varia ±20% por pane;
- flicker raro (hash temporal lento, nunca estroboscópico).
Poucos ALU ops num branch que já executa. Mobile herda de graça.
**Probe:** contagem de panes acesos/apagados numa screenshot noturna; A/B.

### F5 — B30 Torre Pokémon + B19 Indigo Plateau
- **B30**: silhueta não-fechada (37% fill, 126 pedaços, sem outline no
  boundary) → campo `synthOutline` que sela o boundary da caixa (generaliza o
  `seal` existente) antes do flood fill; telhado nunca desenhado → campo
  `roofCap` (coroa sintética escalonada com paleta via `shadeTexel` — o
  mesmo mecanismo do `chimney` da F1). A infra `claimOnly`/`topRows` do
  ROUTE_10 já existe e fica como está.
- **B19**: "duas estruturas num desenho" → campo `parts = { {rows, xspan},
  ... }`: `measure()`+`model()` rodam por parte e o `at()` final é a união.
  É exatamente o "a parede para aqui" que o REMAINING.md diz que falta.
**Probe:** silhouette test das duas passa a 1 peça efetiva; screenshot de
Lavender com a torre em pé nas 3 horas do ciclo.

### F6 — Sol móvel (o item que gasta os ~10%; MEDIR antes)
Só entra se F3 provar que a sombra estática não basta E o orçamento medido em
F0 tiver folga:
- Animar o BEARING de `KX/KZ` num arco de ±35° em torno do sudeste ao longo
  do dia (20 min), elevação ~fixa — o arco é limitado de propósito: a razão
  KX/KZ atual existe para a sombra do personagem não morrer atrás do slab do
  sprite, e o arco não pode cruzar essa zona.
- Re-fit/re-render do shadow pass por PASSO de sol (a cada game-minute), não
  por frame.
- `FACE_SHADE` continua cozido (ângulo fixo) — aceito: a paleta GB domina a
  leitura e as sombras CAST são o que o olho rastreia.
- Atrás de flag no `Quality` (mobile: off).
**Probe:** custo de frame do re-render medido no i3 contra o baseline F0;
estouro do teto → a fase morre e o sol volta a ser fixo.

### F7 — Stretch (só com orçamento sobrando e F6 resolvida)
- Luz de porta no chão à noite (armadilha conhecida: decal de chão não vai no
  overlay — rota tem que ser via GroundFX).
- Rim/specular de telhado (armadilha conhecida: rim do ANIME já acendeu piso
  inteiro — probe obrigatório antes de ligar globalmente).

## Contratos transversais
- Toda fase fecha com: probe headless verde + screenshot A/B aprovada + perf
  ≤ teto + `building_voxels.py` verde. Feature visual nunca é declarada
  pronta sem probe de screenshot (lição registrada do projeto).
- Mobile: nada de F6/F7; F1+F2+F4+F5 chegam de graça (vertex data e shader
  já compartilhados), gates existentes em `Quality`.
- Ordem de corte em vigor: F7 morre primeiro, depois F6.
