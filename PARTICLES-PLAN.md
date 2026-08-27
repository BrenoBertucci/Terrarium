# Particles — plano e handoff

Trabalho iniciado em 2026-08-21. Este arquivo é a fonte de verdade do escopo
e do estado; se algo aqui divergir de uma conversa, este arquivo ganha.

Escrito para ser retomado **frio**. Leia na ordem: COMECE AQUI → quadro de
tarefas → armadilhas. O histórico detalhado está no fim e só é preciso se
você for mexer naquela tarefa específica.

---

## COMECE AQUI — a próxima coisa a fazer

**T7 e T8 FECHARAM em 2026-08-23 — a fundação física está completa.**
O ar tem estrutura (turbulência pré-computada em `Wind.turbAt`, um campo
só para solver + chuva + motes do Weather) e a partícula tem material:
a velocidade é ESTADO que converge pro alvo do ar com
`tau = Particles.TAU · mass/area` — a folha (τ 8ms) dança cada eddy, o
dash (τ 0.21s) desliza a mesma viagem alisada. Em ar estável todo τ
converge pro MESMO alvo, então o baseline não mudou; massa aparece só
nos transientes (rajada, eddy, meandro), que é onde material se lê.

Portões (`run_turb.cmd` + `run_mass.cmd`, todos PASS): lei de relaxação
exata (τ ajustado = configurado a 0.0%), identidade de regime 0.00% nos
7 tipos, aceleração lateral folha/dash ×1.85, vizinhos divergem
26.2%@8px / 48.9%@16px, par 2px → ×5.05 em 4s, transporte <4°,
divergência nodal 0.0000, alocação de regime zero. A T8 reformou o
espectro da T7 (k 1..10, amp k^-0.5 — energia em eddy de 50-100px) e os
portões da T7 foram re-rodados e MELHORARAM. Evidência visual:
`probe_out_mass/mass_traces.png` (trajetórias pareadas no mesmo ar).

**Pendência de olho (agora tripla):** o balé do campo + o shiver da
chuva + a leitura de material em movimento — uma sessão de GALE olhando
paga tudo.

**T10 (emissor de passo) FECHOU em 2026-08-23** — `lib/StepFX.lua`, o
primeiro emissor de conteúdo: cada 8px andados por QUALQUER walker
(jogador, Pikachu, NPCs em alcance) soltam um grão denso chutado pra
trás (velocidade inicial que a T8 gasta com o τ do grão) e um puff leve
que toma o ar. Campo próprio do solver — WindFX limpa o dele quando o
vento cai do FLOOR, e passo faz poeira em calmaria — world-pass only,
mesmos sprites (`WindFX.pack()`), mesmo ar (mesma forma de ctx). Gates:
outdoor/voxel/topo + por-passada `GroundFX.wetness() ≥ 0.45` mata
(lama), `cover() ≥ 0.35` abafa (neve), taxa × `Quality.particles()`.
Portão (`run_step.cmd`, duas rodadas): 1.50 e 1.60 emissões/passada
contra 1.55 esperado, kick médio vx −5.9 andando pro leste, ar parado
com WindFX gated e StepFX vivo, settle = só o fundo dos NPCs, lama/neve
/interior = 0 exato, zero erros. Crop: `probe_out_step/step_dust_crop.png`.

**T11 (emissor: vegetação) FECHOU em 2026-08-23** — `lib/VegFX.lua`: a
vegetação virou FONTE. Folha solta da copa de uma árvore real, semente
de uma touceira real, pétala de um canteiro real — sítios escaneados por
`TileShape.at` (cylinder/canopy/grass/flower) uma vez por mapa, emissão
AMOSTRADA (O(tentativas), não O(floresta)), rajada de `Wind.gust()`
despindo árvores em burst. **No campo do WindFX** via `WindFX.emit`
(API nova) — o FLOOR decidiu: nada rasga de planta em calmaria, então o
clear abaixo do FLOOR é contrato correto aqui (o inverso do StepFX).
Folhas genéricas do pickKind continuam (ar de vendaval carrega folhagem
de fora da tela); as do VegFX levam marcador `veg`. Portão
(`run_veg.cmd`): 124 árvores + 104 touceiras + 52 canteiros na Route 1,
19+19+6 sheds em 10s de GALE, **origem provada** (17 folhas jovens a
≤9.8px de uma copa real, zero violações), FLOOR limpo, zero erros.
Crop: `probe_out_veg/veg_crop.png` (motes anelados).

**T12 (emissor: água) FECHOU em 2026-08-23** — `lib/SprayFX.lua`: vento
sobre água arranca borrifo da faixa de margem (célula d'água com vizinho
de terra), no campo do WindFX via `emit` (borrifo sem vento não existe —
mesmo contrato de FLOOR da T11). A peça nova é a LEI DO TAMANHO:
`WaterBody.sizeAt` amostrado **4 células mar adentro** é a probabilidade
de emissão — mar da Route 19 a 21-22/10s, lagoa de Viridian a 3-4/10s
(**≥7×**), sem nenhum tuning por mapa. Origem provada (motes jovens a
≤9px de margem real, zero violações), FLOOR limpo, zero erros. Cachoeira
DESCOPADA com motivo (nenhuma classe de tile/flag/módulo sabe o que é
cachoeira; grep zero). Crop: `probe_out_spray/spray_crop.png`.

A próxima tarefa é escolher entre:

- **T13 (emissor: fogo e casa)** — recomendada: fecha o quarteto de
  emissores. Fumaça de chaminé dos telhados (os boxes flatTop que o scan
  da T11 já sabe achar) — atenção: fumaça sobe em calmaria, então é o
  molde do StepFX (campo próprio), não o da T11/T12.
- **T14 (Vfx semeia o solver)** — o clarão de batalha passa a soltar
  detrito real.
- **T9 (tumble sheets via Meshy/Blender)** — sessão pesada de tooling;
  melhora a arte da folha que a T11 já solta.
- **T6 (projetar sombra)** — cards no passe do sol, limiar já decidido.

T5 (luz) fechou no mesmo dia — histórico na seção T5. Runners:
`run_lampcard.cmd`, `run_sunshadow2.cmd`, `run_turb.cmd`, `run_mass.cmd`,
`run_step.cmd`, `run_veg.cmd`, `run_spray.cmd`.

O que fechou o T3-AmbientLife (histórico completo na seção T3 no fim):

- **"firefly e sparrow não põem pixel" era mentira do probe, não bug do
  draw.** O `shot()` antigo cedia 2 yields e seguia em frente — mas yield é
  UPDATE, e a SPEED=4 são ~4 updates por frame apresentado. Na fase azarada
  do ciclo a captura ainda estava pendente quando o probe chamava
  `pinNone()`, e o "world.png" fotografava o quadro seguinte, já sem o
  critter. Qual tipo "falhava" era decidido pelo slot da iteração
  (`tests/ambient_kindorder_probe.lua`: a falha seguiu o slot, não o tipo —
  butterfly num slot azarado deu os mesmos 0 px).
- **O `overlay→3D = 0` da tabela antiga também era artefato**: nos slots
  "sortudos" a captura do overlay atrasava até depois do flip de
  `WORLD_PASS` e comparava o passe 3D com ele mesmo. Zero era autocomparação.
- Com o shot honesto (espera o callback), os cinco tipos pintam no 3D com
  centroide ≤1px do overlay e bbox casando. Byte-idêntico **não é** o
  critério: o shader sombreia o card (tinta da hora) e o pós dá o mesmo
  halo de borda que dá a toda geometria — o que tem que bater é posição,
  tamanho e orientação.
- Dois consertos reais saíram da comparação nítida: a folha 3D não
  espelhava no meio-giro (`flip < 0` → swap de U no card; no overlay era o
  sxScale negativo) e `pinOne` ganhou `size` opcional (folha pinada em
  size 1 tem 2px na tela — imedível, não quebrada).
- Smoke com população REAL (`tests/run_amb_smoke.cmd`, ROUTE_1 dia+noite,
  vagalumes vivos com glow): zero throws, pipeline vivo (WindFX e Weather
  ticks == ok), 11-15 batches por render.

Rodar: `tests/run_amb.cmd` (fixtures) e `tests/run_amb_smoke.cmd` (default).

---

## Quadro de tarefas

| # | tarefa | estado |
|---|---|---|
| T0 | fechar a dívida de chuva | **FEITA** — e consertou o pós-chuva |
| T1 | `lib/Particles.lua`, o solver | **FEITA** — paridade provada; não ficou mais rápido |
| T2 | row PFX e orçamento por rung | **FEITA** — três critérios PASS |
| T3 | migração pro passe 3D | **FEITA** — WindFX, Weather e AmbientLife 5/5; flock fica no overlay por decisão |
| T4 | oclusão validada | coberta por T3 (WindFX e Weather) |
| T5 | receber luz (shadow map) | **FEITA** — pontuais, tinta e shadow map medidos; relâmpago por arquitetura; zero mudança de lib |
| T6 | projetar sombra | não começada |
| T7 | campo de turbulência | **FEITA** — curl-noise pré-computado em Wind, um ar pra solver+chuva; espectro v2 (T8): 26.2%@8px, par ×5.05, transporte <4° |
| T8 | massa e arrasto reais | **FEITA** — τ = TAU·mass/area no solver; lei exata, identidade 0.00%, aceleração folha/dash ×1.85 |
| T9 | Meshy → Blender → tumble sheets | não começada |
| T10 | emissor: passo do jogador/NPC | **FEITA** — StepFX com campo próprio; 1.5-1.6/passada vs 1.55, kick que a T8 gasta, gates de lama/neve/interior exatos |
| T11 | emissor: vegetação | **FEITA** — VegFX no campo do WindFX via emit(); origem provada (folha ≤10px da copa), 3 classes de sítio |
| T12 | emissor: água | **FEITA** — SprayFX no campo do WindFX; lei do tamanho via sizeAt 4 células mar adentro (mar ≥7× lagoa) |
| T13 | emissor: fogo e casa | não começada |
| T14 | Vfx semeia o solver | não começada |
| T15 | varredura de custo e rungs | não começada |

Ordem escolhida: fundação primeiro — e a fundação acabou (T0-T5, T7, T8).
O que resta é conteúdo (T9-T13 emissores, T14 batalha), polimento (T6) e o
fechamento de custo (T15). Ver COMECE AQUI para a recomendação da vez.

---

## Decisões fechadas

| decisão | escolha |
|---|---|
| Escopo | tudo que emite partícula: ar, chuva, bicho, batalha |
| Registro | física real, **look cel mantido** — muda o comportamento, não a silhueta |
| Meshy | só tumble sheets, via Blender. Nada de PBR |
| Custo | sem teto. O piso de 30 FPS foi **REMOVIDO a pedido** — tempo de quadro nesta máquina não é repetível (ver armadilha 5). Rungs se calibram por **múltiplo do orçamento medido** |
| Arquitetura | `lib/Particles.lua`: solver comum só pro ar. AmbientLife e Vfx fora dele |
| Oclusão | WindFX e AmbientLife viram **geometria** no passe 3D; Weather usa **depth test no shader** (ver por quê em T3-Weather) |
| Ficam no overlay | streaks screen-space da chuva, Vfx, Interiors, HiddenItems, e o bando de pássaros |
| Transparência | dois baldes: cutout com `discard` + depth write / punhado blendado sem write |
| Luz | receber tinta, pontuais, relâmpago e shadow map; projetar sombra só acima de um limiar de tamanho |
| Emissores novos | passo, vegetação, água, fogo/casa — os quatro |
| Batalha | a sheet continua desenhando o clarão, mas semeia o solver com detrito real |
| Menu | row **PFX** — LOW / ON / HIGH / MAX, desacoplada do RES |
| Gold (Gen 2) | **fora desta rodada.** Dívida assumida |
| Cadência | portão em cada tarefa: implemento → build → probe → número + crop → aprovação |
| Evidência | sempre probe numérico **e** crop de screenshot |

Decisões de implementação tomadas sem consulta: turbulência será campo
pré-computado (não ruído analítico por partícula); pool com swap-remove; a
row se chama `PFX`.

---

## Como trabalhar aqui

**Fonte:** `C:\Users\breno\Downloads\GBA\Terrarium`
**Build:** `C:\Users\breno\Downloads\GBA\Quiver-Windows-x64\Apps\PokemonRedBlueYellow-Gen1RecompProject-Recomp\mods\TERRARIUM`

Toda edição tem que ser copiada pro build antes de rodar probe. Conferir com
`diff -rq lib <build>/lib`.

**Checar sintaxe Lua sem abrir o jogo** — use o próprio `lua51.dll` do build
via ctypes (o script fica no scratchpad da sessão; são ~20 linhas:
`luaL_newstate` + `luaL_loadfile` + `lua_tolstring`). **Lua 5.1: não existe
`goto`.**

**Rodar um probe:** os `.cmd` em `tests/` são o padrão —
`POKEPORT_VERSION=yellow`, `DS_PROBE_DIR=<saída>`, `POKEPORT_DRIVER=<caminho
absoluto do probe no BUILD>`, `POKEPORT_SPEED=4`, e `start /wait gen1recomp.exe
--console`. Runners prontos: `run_amb.cmd`, `run_amb_smoke.cmd`,
`run_amb2.cmd`, `run_lampcard.cmd`, `run_sunshadow2.cmd`, `run_grid.cmd`,
`run_turb.cmd`, `run_mass.cmd`, `run_step.cmd`, `run_veg.cmd`, `run_spray.cmd`, `run_rainland.cmd`, `run_pfx.cmd`, `run_occl.cmd`, `run_rainoccl.cmd`,
`run_t0_*.cmd`.
Screenshot em probe novo: copie o `shot()` do `ambient_occlusion_probe.lua`
— o que espera o callback (armadilha 7). Se o probe precisa LER pixels,
copie o `shotData()` do `sun_shadow_card2_probe.lua`.

**O que o `options.lua` do build guarda** (importa mais do que parece):
`renderScale = 1` (RES **FULL**, não o padrão 1/2), `terrarium_tiltshift = 3`
(T-SHIFT **ligado**), `terrarium_voxel = 5`, `autofarm = "off"`.

---

## Armadilhas que já custaram tempo

Leia isto antes de escrever probe ou de duvidar de uma medição.

### 1. Um throw num DRAW mata cinco sistemas, em silêncio

`main.lua` roda toda a cadeia de partículas de **um único hook de pipeline**
(`render_pipelines:register(PIPE_VOXEL, { update = ... })`, linha ~232), na
ordem: AmbientLife → Vfx → Weather → GroundFX → WindFX → AmbientSound. O
engine chama esse hook dentro de um pcall. **Um erro em qualquer draw derruba
o pipeline e com ele o tick de tudo abaixo** — sem crash, sem log, com o jogo
rodando e o overworld no topo da pilha.

Aconteceu duas vezes, as duas por bug meu. Custou horas na primeira.

Por isso `AmbientLife.update`, `AmbientLife.draw` e `AmbientLife.drawWorld`
estão embrulhados em pcall e registram em `AmbientLife.lastError` /
`AmbientLife.drawError`. **Mantenha assim.**

Instrumentos permanentes para diagnosticar isso: `Weather.ticks`,
`Weather.ticksOk`, `Weather.failState()`, `WindFX.ticks`, `WindFX.ticksLive`,
`WindFX.lastGate`, `AmbientLife.drawCalls/drawSeen/drawPainted`.

### 2. Local declarado abaixo de quem o chama vira global nil

Aconteceu **quatro vezes** neste projeto, três delas em `Weather.lua`, que é
grande. Um local declarado depois do seu próprio caller é um global no ponto
de chamada, o global é nil, e chamar estoura. **O arquivo compila.**

Varra depois de toda inserção: para cada local novo, ache a linha de
declaração e todas as linhas de uso, e confirme que nenhum uso vem antes.

Variante da mesma coisa: uma **closure** que captura nomes que depois viram
locais de um escopo interno. Passe por parâmetro.

### 3. `and`/`or` colapsam retorno múltiplo

`local sx, sy, ps = cond and project(x,y,z) or nil` devolve **um** valor.
`sy` e `ps` vêm nil. Foi isso que derrubou o pipeline na primeira vez. Use
`if cond then sx, sy, ps = project(...) end`.

### 4. Medir partícula é mais difícil do que consertar

Erros de medição cometidos, todos corrigidos, todos plausíveis na hora:

- Subtrair um quadro **WIND OFF** para isolar o campo — WIND OFF também para
  a grama, e 95% do quadro veio "aceso".
- Contar "pixels de chuva" como diferença entre dois quadros do mesmo estado
  — credita grama e NPC ao clima. **Piso de ruído medido: 72%** do que estava
  sendo contado. Use um estado de controle.
- Comparar duas capturas e ler `diferença 0` como "nada foi desenhado". Pode
  ser "as duas rotas desenham igual", que é o resultado desejado. **Precisa
  de um terceiro quadro em branco** para desambiguar.
- Fixture branco contra parede branca. Use magenta (`WindFX.pinOne` faz isso)
  ou ponha contra o céu.
- Projetar o fixture **antes** das capturas: a câmera muda. Projete no mesmo
  resume da corrotina em que o `captureScreenshot` é agendado.
- Deixar 40 frames entre as duas capturas de um par: **o jogador anda sozinho
  depois de `setMap`** e leva a câmera. Bata o par em poucos frames e recorte
  cada imagem nas coordenadas dela.
- Janela de amostragem curta: `shotAt` cede 2 frames e o `drawBody` roda a
  cada ~2-4, então `calls 0` parecia "nunca chamado". Use ~8.
- `contagem de motes` **não é** prova de pixel. Lição do THE INK.
- **Altura de classe não é geometria.** `groundAt` devolve a altura de
  CLASSE da célula; árvore (`cylinder`) e cerca (`post`) são ROUND_ART —
  casco recortado da arte, majoritariamente ar na altura de classe. Um
  ray-walk sobre essas alturas "provou" um card na sombra que media
  ensolarado (T5-v1). Colocação relativa a sombra/oclusão se verifica com
  o RENDERER como oráculo: toggle da feature + leitura de pixel
  (`captureScreenshot` entrega ImageData; `getPixel` em pontos projetados
  no mesmo resume da captura).
- **Card sobre sombra listrada mede diluído.** A média do cluster mistura
  fragmentos na listra com fragmentos ao sol e reporta 14-19% onde o
  efeito por fragmento é inteiro. A prova é o delta PAREADO por pixel
  (câmera e card estáticos entre os dois estados do toggle), com a
  mudança do próprio fundo descontada pelos blanks por estado.
- **Critério de física de quadro-negro reprova feature saudável.** O
  portão da turbulência exigiu crescimento exponencial de separação de
  par (estimativa de Lyapunov) e leu ×1.2 duas vezes — porque o mote
  atravessa o eddy em <1s (o strain gira e o esticamento vira passeio
  aleatório) e porque poeira vive 1-5s (o horizonte assintótico não
  existe no jogo). O portão certo afirma a frase que o DESIGN promete,
  em escala e horizonte que o jogo mostra; a assíntota fica como
  diagnóstico reportado, sem veredito.
- **Warmup de pool lê como leak, e GC de controle mente.** Campos novos
  em tabelas pooladas rehasheiam cada tabela UMA vez (T8: ~5 KB por 60
  motes) — medido como "alocação por step" vira vazamento falso; e
  deltas de `collectgarbage("count")` entre coletas parciais chegam a
  dar negativo. Aqueça até as formas assentarem, colete, e meça o
  crescimento em REGIME.
- **Deriva bruta não separa material; aceleração separa.** Velocidade
  lateral de leve vs pesado num campo dominado por eddy grande deu
  ×1.22 (os dois seguem o eddy lento — e devem). O que o olho chama de
  "treme vs desliza" é alta frequência: a aceleração lateral pondera o
  espectro por f, onde o filtro do pesado morde, e deu ×1.85.
- **O elenco anda junto — atribuição por-jogador infla 3×.** Em Yellow o
  Pikachu pisa cada passo do jogador, e NPCs vagueiam perto; dividir
  emissões pela distância SÓ do jogador leu 5.1/passada onde a lei era
  1.55. Meça a lei pelo somatório de distância de TODOS os walkers em
  alcance (o mesmo contorno que o emissor usa) — e o fundo dos NPCs com
  o jogador parado vira o PASS do caminho de NPC, não ruído.
- **Encontro selvagem derruba caminhada de probe.** Andar 300 ticks na
  Route 1 tem chance real de batalha ("overworld not on top" no meio da
  janela). `game.save.repelSteps = 9999` antes de andar bloqueia pelo
  mecanismo do próprio jogo.
- **Flor é coisa de TILE, não de cell.** O Structures posiciona canteiro
  em `tx*8` em qualquer um dos quatro tiles 8px do cell; um scan que só
  lê o tile de colisão (canto inferior-esquerdo, o que todo leitor de
  altura usa) acha ZERO flores num mapa cheio delas. Pergunte aos quatro
  tiles quando a classe de arte for de tile.
- **O número comparado tem que PODER variar entre os fixtures.** O
  primeiro gate da lei do tamanho comparou `sizeAt` NA margem — e o fetch
  do WaterBody morre em toda beira POR DESIGN (`fetch01 = células/10`):
  mar e lagoa leem ~0.1 iguais, e a lei "reprovou" sem ter sido testada.
  A 1.5 células mar adentro ainda leem iguais (~0.2). A pergunta que
  separa é a 4 células — onde mar tem fetch e lagoa já virou terra calma.
- **Sortear no conjunto inteiro e filtrar por alcance depois enviesa a
  taxa.** O pick do borrifo sorteava entre TODAS as margens do mapa e
  descartava as longe: na Route 19 (48 de 128 em alcance) 62% das
  tentativas morriam no sorteio e o mar emitia como lagoa. A taxa perto
  do jogador não pode depender de quanta margem existe LONGE dele —
  reconstrua a lista em alcance por pulso e sorteie nela.
- **A câmera olha do sul: água ao sul do jogador é água ATRÁS dela.** A
  caçada de flagra na Route 19 emitia 13/10s e fotografava zero — todas
  as margens fora do frustum. Para fotografar água, fique ao SUL dela
  (prefira margem com normal nz > 0.5 ao re-locar).
- **Decal deitado na superfície que escreveu o depth é empate — e bias
  constante não cobre.** Depth de dispositivo é não-linear: folga que
  perdoa o empate longe começa a perdoar geometria de verdade perto.
  Erga o decal em espaço de MUNDO (2px bastam e somem sob a espessura do
  desenho). E o corolário de processo: um gate que valida a feature NOVA
  de um buffer (oclusão de streak) tem que re-olhar as features VELHAS
  do mesmo buffer (impactos, validados antes do teste existir) — a
  regressão ficou dois dias invisível até o jogador jogar na chuva.
- **Foto de partícula baixa dentro de grama alta mostra nada — e está
  CERTA.** O casco da touceira tem 16 de altura e o depth test esconde
  poeira de y≤9 atrás dele; o flagra tem que ser em piso aberto. Ler
  "não aparece na foto" como "não desenha" aqui seria a armadilha do
  terceiro quadro de novo.

### 5. Tempo de quadro nesta máquina não é repetível

Duas rodadas do mesmo probe discordaram em 5 a 7 fps, com todas as linhas
marcadas como "ainda assentando" (duas leituras secas da mesma linha
chegaram a diferir 27,9 ms). O assentamento é monotônico e domina.

Consequência: **não defina critério em FPS absoluto.** O que é repetível é
contagem e alocação. Se precisar de custo, use delta intercalado (A-B-A-B).

### 6. `GroundFX.SOAK = 55 s`

São 55 segundos de aguaceiro para saturar o chão. Um teste de chuva curto
deixa `wet = 0.065` e nenhuma poça, e aí "o pós-chuva não deixa nada" é
falso — nunca choveu. Encharque 70 s.

### 7. Screenshot agendado não é screenshot tirado — espere o callback

A que custou uma sessão inteira de conclusão errada ("firefly e sparrow
não põem pixel"), e a mais traiçoeira até agora porque **falseia por fase**:
metade dos slots sai certa e a outra metade sai consistentemente errada, o
que parece um bug determinístico do código medido.

O mecanismo: `love.graphics.captureScreenshot` executa no **present**
seguinte, e um `coroutine.yield()` do driver avança um **update** — a
SPEED=4 são ~4 updates por present. Um `shot()` que cede um número fixo de
yields e segue em frente pode retornar com a captura ainda pendente; o
probe muda o estado (`pinNone`, flip de flag), e o PNG fotografa o quadro
seguinte, com o estado novo. O "world.png" era um blank; o "overlay.png"
dos slots sortudos era o passe 3D (capturado depois do flip), e o
`overlay→3D = 0` que parecia validação pixel-perfeita era autocomparação.

Regra: **o callback da captura seta uma flag e o probe espera a flag**,
nunca um número de yields. E qualquer leitura antiga cujo shot era
"agenda + 2 yields" é suspeita — `tests/particles_occlusion_probe.lua`,
`tests/rain_occlusion_probe.lua` e `tests/t0_baseline_probe.lua` ainda
usam o padrão antigo; as conclusões deles bateram com medições
independentes (contadores), mas se um deles um dia der um zero estranho,
este é o primeiro suspeito.

Diagnóstico que fecha a questão em uma rodada: repetir o mesmo sujeito em
slots de paridade oposta (`tests/ambient_kindorder_probe.lua`). Falha que
segue o slot é do probe; falha que segue o sujeito é do código.

---

## Linha de base medida

Tudo em RES FULL (o que o `options.lua` guarda), PALLET_TOWN ou ROUTE_1.

**Chuva pinada 0.85, PALLET_TOWN:** 703 shafts · 559 splashes · 144 ejecta ·
47,6 drips · 23 células de poça. `impactMix` sem `"ground"` (o guard funciona).

**Custo, ROUTE_1, RES FULL:** piso seco 26,50 ms · lente +7,43 ms · impactos
**+7,95 ms** · clima inteiro +10,86 ms. (Números de uma rodada; ver armadilha 5.)

**Alocação, 600 frames, 101 motes, coletor parado:** 96,6 KB/frame — e o pool
do T1 **não mudou isso** (96,585 antes, 96,688 depois).

**Orçamentos por rung PFX, com o RES parado:**

| rung | mul | vento | shafts | splashes | drips | vento vivo | shafts vivos |
|---|---|---|---|---|---|---|---|
| LOW | 0,40 | 44 | 312 | 120 | 28 | 36 | 281 |
| ON | 1,00 | 110 | 780 | 300 | 72 | 102 | 703 |
| HIGH | 2,00 | 220 | 1560 | 600 | 144 | 212 | 1407 |
| MAX | 4,00 | 440 | 3120 | 1200 | 288 | 369 | 2815 |

---

## Histórico por tarefa

### T0 — dívida de chuva (FEITA)

Fonte e build já estavam sincronizados; os dois consertos que a memória dava
como pendentes já estavam presentes. Critérios: `"ground"` ausente do
`impactMix` OK; impactos +7,95 ms ≤ 9 ms OK; água viva e proporcional OK.

**Consertou o pós-chuva**, que não desenhava nada. Duas causas:

1. `Weather.setting:sync("rain")` no setup dos probes mantém a row em RAIN;
   `tick()` repõe `state.kind` e [Weather.lua:1977](lib/Weather.lua:1977)
   zera `after.untilAbs`. **Toda leitura de pós-chuva já feita era chuva
   caindo** — inclusive o "18,1 drips" que o projeto registrou como validação.
2. A taxa do beiral foi dimensionada como *suplemento*. Durante a chuva os
   drips vêm dos impactos de telhado (`EAVE_CHANCE` sobre ~194 splashes) mais
   o dardo a 26/s. Sem chuva a primeira fonte some e o dardo sozinho dá ~3.

Correção: `Weather.EAVE_RATE_AFTER = 190` só para o regime de pós-chuva.
Resultado: drips 5 → **21**, splashes de pouso 1 → **17**, sinal/ruído de
pixel 1,0x → **3,5x**.

### T1 — `lib/Particles.lua` (FEITA)

251 linhas. Pool com swap-remove e freelist, integrador, `Wind.flowAt` como
campo único, parâmetros por tipo em `WindFX.KINDS` (a velocidade pode ser
**função**, que é o que a folha precisa). `mass` e `area` gravados e lidos por
nada — são a entrada da T8.

Paridade verificada por `tests/particles_parity_probe.lua`, que imprime o
próprio piso de ruído. Duas rodadas pós-portagem: 8 de 9 estatísticas dentro
do piso, e a nona é **outra a cada rodada** — assinatura de ruído, não de
mudança. `meanSpin` tem prova de código: o solver **nunca escreve `spin`**.

**Não ficou mais rápido**, e isso está medido (ver linha de base). O motivo de
fazer nunca foram os milissegundos, foi ter T3/T7/T8 como uma mudança em vez
de duas.

### T2 — row PFX (FEITA)

`Quality.particleSetting` (LOW/ON/HIGH/MAX), registrada no menu em `main.lua`.
É um **multiplicador** sobre os orçamentos existentes, não um substituto: ON =
1,00 reproduz exatamente os números de hoje em qualquer rung de RES. Passa por
`Quality.windStreaks`, `shaftBudget`, `splashCap`, `flakeCap`, `dripCap`.

Três critérios PASS (ver tabela na linha de base). `RES never moved` — o
desacoplamento é real.

### T3 — WindFX no passe 3D (FEITO)

`lib/ParticleMesh.lua` + `Voxel3D.drawParticles` + `WindFX.drawWorld`, chamado
de dentro do `VoxelScene.render` (require preguiçoso, como o Trees3D).
`WindFX.WORLD_PASS` alterna os dois caminhos no mesmo build.

O billboard não é look-at: neste engine todo card "olha pro sul e só deita pelo
pitch", então a rotação é assada nos vértices — 8 multiply-adds por vértice,
nenhuma matriz por partícula. Tamanho passou a ser em unidades de mundo.

Oclusão provada com mote fixo magenta (`WindFX.pinOne` + `WindFX.HOLD`):

| onde | overlay | passe 3D |
|---|---|---|
| dentro da casa | 355 px | **1 px** |
| em campo aberto | 974 px | **1691 px** |

O controle em campo aberto é o que impede que um desenho quebrado passe por
oclusão bem-sucedida. Piso de falso positivo: **zero**.

**Não verificado:** se o campo de 100 motes *parece* o mesmo. A poeira é
pequena demais para separar do dither do tileset nas capturas.

### T3 — Weather ocludido (FEITO, por outra rota)

Os impactos do Weather **não podem** virar geometria: são quads procedurais de
espaço de tela com shader próprio (a lente de refração lê o quadro atrás).
Converter significaria reescrever `pushImpact` e perder a lente.

Em vez disso: `RAIN_FMT` ganhou `RainDepth`, alimentado por
`Voxel3D.projectDepth`; os dois caminhos de desenho descartam fragmento mais
fundo que `Voxel3D.sceneDepthTex()`. `Voxel3D.wantDepth` permite um segundo
pedinte do buffer legível (antes só o RayFX pedia).

| estado | px de chuva |
|---|---|
| teste desligado | 30.742 (100%) |
| teste ligado | 15.793 (51%) |
| tudo descartado (checagem de fiação) | 0 |

**49% dos fragmentos estavam sendo desenhados na frente do que estava na
frente deles**, incluindo chuva atravessando o próprio chão.

Duas correções de raciocínio pelo caminho: suprimir o teste sob T-SHIFT estava
**errado** (blur não move geometria; e como o `options.lua` daqui tem T-SHIFT
em 3, o teste armava em zero frames) — a condição real é a **grade da canvas**
bater com a do buffer. E a metade "shafts em geometria" do híbrido é
**redundante**: shafts e impactos passam pelo mesmo `rainPush`, então o shader
já cobre os dois. Só compraria independência do buffer legível.

**Adendo 2026-08-25 — a regressão que o teste de profundidade escondeu.**
O jogador reportou "os pingos não atingem o chão e não integram com as
casas". A mecânica estava perfeita (703 shafts, zero abaixo da própria
superfície, impactMix com 200+ splashes de TELHADO vivos) — mas nenhum
impacto pintava: anel, burst, ejecta e tinta deitam NA superfície que
escreveu o depth, o empate descartava tudo, e o DEPTH_BIAS de 0.0012
(que existe exatamente para esse caso, diz o próprio comentário do
shader) não cobria. O gate da T3 mediu oclusão de STREAK e nunca re-olhou
os impactos no mesmo buffer — a T0 os validou ANTES do teste existir.
Conserto: `Weather.SPLASH_RAISE = 2.0` px de MUNDO em todo pouso que não
é água (bias intocado — subir o bias global perdoaria geometria perto de
verdade; o raise de mundo projeta a folga certa em toda distância; a
tinta d'água nunca foi comida e fica onde está). Prova: A-B-A de tinta
com normalização pelo céu, |efeito| 0.119 vs |drift| 0.024 (5×), oclusão
de streak seguindo armada (ON ≪ OFF). Probe: `tests/rain_land_probe.lua`
(runner `run_rainland.cmd`), crop `probe_out_rainland/rain_fixed_crop.png`.

### T3 — AmbientLife (FEITO, 2026-08-23)

`WORLD_PASS = true` por default. Os cinco tipos validados por
`tests/ambient_occlusion_probe.lua` (com T-SHIFT desligado no setup — o
fixture cai na banda de blur e vira borrão): centroide do critter no passe
3D a ≤1px do overlay, bbox casando, orientação certa (pardal de peito pra
baixo, asas no alto; libélula com asas no topo do corpo; glow do vagalume
em volta do core). Smoke com população natural e default ligado:
`tests/run_amb_smoke.cmd`, dia+noite em ROUTE_1, zero throws, canários
vivos.

**A sessão anterior fechou "3 de 5" com dois tipos quebrados — os dois
eram fantasma do probe** (armadilha 7): o shot de 2 yields fotografava,
nos slots de fase azarada, o quadro pós-`pinNone`. O experimento que
desfez o nó foi `tests/ambient_kindorder_probe.lua` — os mesmos tipos em
slots de paridade oposta: a falha seguiu o slot, não o tipo (butterfly
"quebrou" num slot azarado com os mesmos 0 px exatos; sparrow passou num
sortudo). Assinatura no dado antigo, visível a posteriori: nos slots
azarados `overlay→3D == vazio→overlay` **exato** (o world.png ERA um
blank), e nos sortudos `overlay→3D = 0` porque a captura "overlay"
atrasava até depois do flip e comparava o 3D consigo mesmo.

Critério de aceitação corrigido junto: byte-idêntico ao overlay é
impossível E indesejado — o shader da cena sombreia o card (tinta da
hora, shadow map) e o pós desenha o mesmo halo de borda que desenha em
toda geometria. O que se exige é posição, tamanho e orientação.

Consertos reais que a comparação nítida achou:

- **A folha 3D não virava**: o overlay espelha com `sxScale` negativo
  quando `sin(ang/2) * c.flip < 0`; o card agora troca u0↔u1 na mesma
  condição. Sem isso a folha "orbitava" em vez de tombar.
- **`pinOne` ganhou `size` opcional** (probe-only): folha pinada em size 1
  é card de 2px — some em qualquer threshold e lê como "descartada".
  O probe pina a folha em 4.
- Instrumentos novos e permanentes: `AmbientLife.worldCalls` (renders de
  cena que chegaram ao módulo) e `worldTrace` (batches por render, os
  últimos ~16) — juntos respondem "o frame capturado construiu geometria?"

Bugs da rodada anterior, que continuam valendo como lição:

- **`tint` tem dois significados**: para a borboleta é um índice em
  `BUTTERFLY_TINTS`; para a folha é a tabela de cor. O fixture setava `1` para
  todos, o que estourava no ramo da folha — e como throw em draw derruba o
  pipeline, congelava as leituras dos três tipos seguintes e lia como "quatro
  de cinco quebrados". Não estavam.
- **Reset obsoleto no `buildCards`**: resetava contagens percorrendo o `order`
  do frame anterior; lote cuja chave não estivesse naquela lista guardava
  contagem obsoleta, e o teste de "já está neste frame" era `n == 0`, que
  contagem obsoleta reprova. Trocado por **selo de build**.
- Também: vagalume parado em `t=5` cai na metade apagada do próprio blink e
  não desenha. O fixture agora pina na fase acesa (`t = 0.714`).

### T5 — receber luz (FEITA, 2026-08-23)

Verificação, não implementação: **zero linhas de lib mudaram.** O shader
da cena soma as oito poças de lampião em `light` antes de sombrear
qualquer material, os uniforms `lamp0..7` são enviados uma vez por cena e
continuam de pé quando `drawParticles` roda no fim do passe — então um
card na poça esquenta como uma parede. O probe confirmou a teoria.

**Rig** (`tests/lamp_card_probe.lua`, runner `run_lampcard.cmd`): mote
magenta do `WindFX.pinOne` dentro da poça do poste mais próximo de
VIRIDIAN_CITY (raio 12.8 do flame, noite DEEP, hora assentada), câmera
parada (777,265 nos sete shots). O A/B é o toggle
`StreetLamps.setting:sync(on/off)` — mesma câmera, mesmo card, três
estados (ON/OFF/ON2, o terceiro é o controle de deriva) — mais o mesmo
trio pelo overlay (controle negativo: aquele caminho não vê o shader) e
um par de blanks por estado para descontar o vazamento do alpha 0.75
(`mote_true = (obs − 0.25·bg) / 0.75`).

| captura | mote_true (R,G,B) |
|---|---|
| world ON | (99.2, 2.3, 136.5) |
| world OFF | (42.3, 1.3, 108.1) |
| world ON2 | (100.0, 2.4, 137.6) |
| overlay ON | (172.6, 8.0, 172.4) |
| overlay OFF | (169.7, 3.4, 170.9) |

Leitura: R +135% e B +26% com o toggle — a assimetria exata de um âmbar
(lampColor tem mais R que B) somando num card magenta; G fica em ~2
porque o card não tem verde e a poça multiplica o material em vez de
pintá-lo ("adds light BEFORE the material is shaded"). ON2 == ON a <1%.
Overlay imune a <2%. E o world OFF contra o overlay é a medida da TINTA:
(42,1,108) vs (170,3,171) — o card noturno esmagado e azulado pelo
`skyTint`, que o overlay nunca vê.

Detalhe de shader que importa pro futuro: cards escrevem shade **+1**, e
`vUp = step(VertexShade, 0)` lê isso como flanco — o Lambert do lampião
usa `length(L.xz)` (a parcela horizontal, com piso de bounce 0.20). Um
mote EXATAMENTE embaixo do flame recebe só o bounce; ao lado, recebe
quase cheio. É o comportamento de parede, e para poeira está certo.

**Relâmpago dispensa trabalho por decisão de arquitetura**: `Weather.flash()`
vira `flashAmt` no shader do CÉU e uma placa screen-space sobre o quadro
composto (`paintPlate`) — não há termo de flash no shader da cena, logo
não há nada por-card a receber; a placa cobre os cards como cobre o
terreno.

**O shadow map do sol (fechado em seguida, mesmo dia).** Três rodadas até
a prova limpa, e as duas primeiras ensinaram mais que a terceira:

- **v1 morreu por confiar em altura de classe.** O probe verificava a
  colocação com um ray-walk sobre `WindFX.groundAt` — que devolve a
  altura de CLASSE da célula. Pallet é 16 em tudo que é alto, mas árvore
  de borda é `cylinder` e cerca é `post` (ROUND_ART): casco recortado da
  arte, majoritariamente AR na altura de classe. O card ficou "verificado
  bloqueado" pelos 4 cantos e mediu ensolarado; e o blank largo mostrou
  que ao meio-dia Pallet quase não tem sombra sólida visível — o lab não
  registra faixa profunda no chão.
- **v2 acha a sombra com o próprio renderer como oráculo**: captura a
  cidade com sombras HIGH/OFF/HIGH sem mote, lê os frames de volta
  (`captureScreenshot` entrega o ImageData) numa grade de 833 pontos de
  chão projetados, e exige escurecimento consistente nos dois HIGH — NPC
  atravessando reprova. Resultado: 103-107 pontos consistentemente
  escurecidos, 14 profundos (Δlum ≥ 0.30), melhor em (40,88) com
  Δlum 0.48 (caster: cerca a leste).
- **Card em faixa de cerca é card listrado**, e a média dilui: primeira
  medição +14% (card y3.5-6.5), segunda +19% (y2.2-4.2, size 2) — ambas
  com reprodução exata e overlay imune, mas magnitude parcial. A prova
  limpa é POR PIXEL, pareada (câmera estática, card estático, fundo
  descontado pelos frames de descoberta):

  ```
  WORLD (lit−shadow) por pixel: +50 +50 +17 +15 +14 +14 +13 +7 ... +0 +0
  OVERLAY:                      ±2 em todos
  shadow vs shadow2:            diff máximo por pixel = 0
  ```

  A borda da sombra ATRAVESSA o card: onde a listra cai, o fragmento
  perde o termo do sol inteiro (50 pts de R ≈ a parcela do sol na luz do
  dia); onde não cai, zero. Gate por fragmento, igual numa parede — que é
  exatamente o contrato do T5.

Probes: `tests/sun_shadow_card2_probe.lua` (runner `run_sunshadow2.cmd`);
v1 mantida como registro com aviso no cabeçalho. `tests/ground_grid_dump.lua`
(runner `run_grid.cmd`) imprime a grade de alturas de classe de um mapa —
foi ela que mostrou o "16 em tudo" de Pallet.

### T7 — campo de turbulência (FEITA, 2026-08-23)

O ar deixou de ser laminar. A banda do `flowAt` dava a todo ponto de uma
crista o mesmo vetor, e o que quebrava a marcha era o curl por partícula
— wander no TEMPO, não no espaço; dois motes a uma célula marchavam em
formação. Agora há estrutura espacial, e ela mora no `Wind` porque é uma
propriedade do AR, não de um cliente.

**O campo** (`lib/Wind.lua`, bloco de turbulência no topo):

- Dois lattices 64×64 (célula de 8 px → tile de 512), cada um o CURL de
  uma stream function espectral: soma de 12 senos com wavenumbers
  INTEIROS (tile sem costura por construção) e amplitude ~1/k. Curl de
  ψ = divergência zero — campo que agita sem PASTOREAR (fonte/sumidouro
  aglomera poeira em caroços). Normalizado a RMS 1: toda decisão de
  amplitude vive no envelope por frame.
- Amostragem bilinear com wrap, POSIÇÃO enrolada módulo tile — imune à
  lição do espectro d'água (fase acumulada vira ruído longe da origem).
- Os dois lattices se misturam a meio-a-meio (fator √2/2 para manter o
  RMS) e ADVECTAM com o vento a 0.55× e 0.78× — o slip diferencial é o
  que impede o composto de se repetir. Travel integrado no `Wind.step`
  (o rumo meandra; tempo absoluto não integra rumo variável) e enrolado
  módulo tile.
- Envelope: `turbEnv = TURB_MUL · (0.55 + 0.75·gust)` — calmaria ainda
  tem textura, rajada agita. `Wind.TURB_MUL` é o knob (probes usam 0).
- Build preguiçoso no primeiro step (LCG próprio, determinístico, RNG
  global intocado). Custo one-time ~50k senos; por chamada ≤0.2µs, zero
  alocação.

**Os consumidores:**

- Solver (`Particles.lua`): o seam `ctx.turbulence` da T1 virou código —
  px/s por unidade de eddy, a mesma forma do `speed`. Curl por partícula
  MANTIDO por baixo (flutter próprio ≠ estrutura do ar). WindFX passa
  `amount·SPEED·WindFX.TURB` (TURB = 0.5).
- `flowAt` soma `turbV·eddy` (turbV = amount·FLOW·0.35, share menor de
  propósito: gota atravessa eddy num frame, só o ângulo deve tremer) —
  chuva, motes do Weather e folhas herdam sem mudar uma linha.

**Portão** (`tests/wind_turb_probe.lua`, todos PASS):

| medição | valor |
|---|---|
| determinismo | bit-igual |
| tile (x+512) | mismatch 5e-15 |
| RMS espacial / envelope | 0.95 (knob 0 → 0.0000) |
| div/curl nodal | **0.0000 exato** (off-node 0.034) |
| um-ar (flowAt) | delta == turbV·eddy bit-a-bit, share 23% |
| vivo (3s) | \|Δu\| 0.86 ≈ decorrelado |
| estrutura a 8px / 16px | **14.6% / 28.6%** da velocidade média |
| transporte | 0.7° do rumo |
| par 2px após 4s | ×1.78 (diagnóstico, ver lição abaixo) |
| alocação (20k chamadas) | +3.9 KB ≈ zero |

**A lição de métrica que custou duas rodadas:** o primeiro portão exigiu
crescimento exponencial de par (Lyapunov de quadro-negro) e leu ×1.2 — o
mote ATRAVESSA o eddy congelado em <1s, o strain gira embaixo do par e o
esticamento vira passeio aleatório; e poeira vive 1-5s, horizonte de caos
de 4s não existe no jogo. O portão honesto afirma a frase do próprio
design ("vizinhos a uma célula recebem ar diferente"), não a assíntota de
uma teoria. Virou bullet na armadilha 4.

**Não coberto e assumido:** o LOOK em movimento (still não mostra
redemoinho — pendência de olho, junto com a do WindFX); chuva/neve sob
tempestade herdam o shiver e a leitura visual disso fica pra próxima
sessão de weather (os gates numéricos de chuva medem contagem, não
ângulo — nada quebra).

**Espectro v2 (reformado pela T8, mesmo dia):** k 1..10 com amp k^-0.5
(era 1..6 com 1/k). Motivo na seção T8; os portões da T7 re-rodados
melhoraram: estrutura 26.2%@8px / 48.9%@16px (era 14.6/28.6), par ×5.05
(era ×1.78), div nodal segue 0.0000 exata, off-node 0.062, transporte
3.7°.

### T8 — massa e arrasto (FEITA, 2026-08-23)

A velocidade da partícula virou ESTADO. Tudo que o solver calculava
(banda × speed do kind × curl + eddy) agora é o ALVO do ar, e a
partícula converge nele por blend implícito `dt/(τ+dt)` — estável em
qualquer dt — com `τ = Particles.TAU · mass/area` (TAU = 0.15). Os
mass/area que a T1 gravou nos KINDS viraram física sem editar o WindFX:
folha 0.12/2.2 → τ 8ms (fiel a cada eddy), dash 0.5/0.35 → τ 0.21s (o
mais pesado do ar). `mass = 0` é a escotilha: blend 1, movimento
cinemático pré-T8 exato. Primeira frame sem estado nasce NO alvo (spawn
no vento, como sempre foi). Sem física vertical de propósito: bob/lift
são o look, e folha que caísse de verdade sairia do campo. Os streaks
do dash já se orientavam por `m.vx` — herdaram a defasagem de graça.

**Portão** (`tests/wind_mass_probe.lua`, todos PASS):

| medição | valor |
|---|---|
| lei de relaxação (τ ajustado vs configurado) | **0.0%** leve e pesado |
| identidade de regime, 7 tipos | pior erro **0.00%** |
| aceleração lateral folha/grit/dash | 98.0 / 55.2 / 53.1 px/s² (**×1.85**) |
| velocidade lateral (report) | ×1.40 |
| vmax | 119 < cap 189 |
| alocação de regime (240 steps) | ≈ 0 (warmup à parte) |

Evidência visual: `probe_out_mass/mass_traces.png` — cinco pares de
trajetórias no MESMO ar congelado; o amarelo (folha) faz cada gancho, o
azul (dash) desliza a viagem alisada.

**As duas rodadas que reprovaram ensinaram:**

1. **A alavanca era o espectro, não o τ.** Com a energia em eddies de
   300-500px (forçamento ~0.25Hz no passo do mote), até o dash seguia
   95% — que É o que detrito pesado faz; o material só se lê na alta
   frequência, e não havia alta frequência. Achatar o espectro (k^-0.5,
   k até 10) pôs energia onde o filtro de primeira ordem morde, e de
   quebra deu à T7 o dobro de estrutura em escala de mote. E a métrica
   acompanhou: deriva lateral bruta não separa (×1.22); ACELERAÇÃO
   lateral pondera por f e separa (×1.85) — é ela que o olho chama de
   "treme vs desliza".
2. **Warmup de pool parece leak.** Dar `vx/vz` a 60 tabelas pooladas
   rehasheia cada uma UMA vez (~5 KB) — medir isso como alocação por
   step acusa vazamento onde há pool funcionando. E aritmética de
   controle com `collectgarbage("count")` entre coletas parciais devolve
   até número negativo. A prova certa: aquecer até as formas assentarem,
   coletar, e medir o crescimento em REGIME (deu ~0).

### T10 — emissor: passo do jogador/NPC (FEITA, 2026-08-23)

`lib/StepFX.lua`, ~250 linhas, o molde dos próximos emissores:

- **Campo próprio do solver, não o do WindFX** — WindFX limpa o campo
  quando `amount < FLOOR` (contrato certo pra mote ambiente, cuja razão
  de existir é o vento); passo faz poeira em calmaria. O solver
  unificado da T1 é o que torna isso barato: mesmo integrador, mesmo ar
  (mesma forma de ctx: `speed/turbulence = amount·SPEED·(1/TURB)`),
  mesmos sprites (`WindFX.pack()`, acessor novo de uma linha), mesmo
  draw (ParticleMesh → `Voxel3D.drawParticles`). World-pass only.
- **Passada é DISTÂNCIA, não animação**: a cada 8px percorridos por um
  walker (jogador, follower, NPCs de `ow.npcs`), um footfall na posição
  atual — bike emite mais por segundo por construção. Salto >24px num
  frame é warp: zera o acumulador sem emitir. Walker fora do alcance de
  cull não emite (senão é churn de claim/kill que infla contador e não
  desenha) — mas o trail avança, então entrar em alcance não despeja
  passadas acumuladas.
- **Footfall**: grão denso (kick, mass 0.45/0.35 — τ ~0.19s) jogado pra
  TRÁS com velocidade inicial que o arrasto da T8 gasta, chance 0.85; e
  puff leve (0.16/1.10 — τ ~0.02s, toma o ar quase já) que sobe e some,
  chance 0.70. Ambas × `dry` × `Quality.particles()`.
- **Gates**: módulo — voxel/outdoor/topo/sem transição (os do WindFX
  menos o vento); por-passada — `wetness() ≥ 0.45` mata (lama não
  levanta poeira), `cover() ≥ 0.35` abafa (neve). Acessores de
  molhado/neve são campos públicos SUBSTITUÍVEIS — o probe testa o gate
  sem 70s de chuva (armadilha 6).
- Instrumentos padrão da casa (ticks/lastGate/emitted/lastBatches/
  lastError...), update e draw em pcall (armadilha 1).

**Portão** (`tests/step_dust_probe.lua`, duas rodadas):

| medição | rodada A | rodada B |
|---|---|---|
| emissões por passada (lei: ~1.55) | 1.50 | 1.60 |
| kick médio vx (andando pro leste) | −5.3 | −5.9 |
| ar parado (row OFF): WindFX / StepFX | gated / **live** | gated / **live** |
| settle pós-parada | = fundo NPC | = fundo NPC |
| lama / neve / interior | 0 / 0 / 0 | 0 / 0 / 0 |
| NPC path (fundo com jogador parado) | 36-47 em 300 ticks | ✓ |
| erros / canários | 0 / vivos | 0 / vivos |

Crop: `probe_out_step/step_dust_crop.png` — a nuvem nos pés no calçadão
de Pallet. Três armadilhas novas de probe saíram daqui (elenco anda
junto; repel contra encontro; grama alta oclui a foto) — ver armadilha 4.

### T11 — emissor: vegetação (FEITA, 2026-08-23)

`lib/VegFX.lua` (~230 linhas), o segundo emissor — e a resposta da
pergunta que o molde do StepFX deixou aberta: **campo do WindFX, não
próprio**. O FLOOR decidiu: nada rasga de planta em ar parado, então o
clear-abaixo-do-FLOOR do WindFX é contrato CORRETO aqui, e compartilhar
o campo compra orçamento, clima, draw e passe 3D de graça. A ponte é
`WindFX.emit(kind, x, y, z, opts)` — spawn em ponto exato com defaults
do spawn(), api nova para todo emissor que sabe DE ONDE a partícula vem
(mais `WindFX.count/get` para probes).

- **Sítios por classe de arte** (`TileShape.at`, um scan por troca de
  mapa, listas públicas em `VegFX.sites`): cylinder/canopy → árvore com
  altura de copa; grass → touceira; flower → canteiro POR TILE (8px —
  ver armadilha nova). Route 1: 124/104/52.
- **Emissão amostrada**: a cada 0.35s, meia dúzia de tentativas sorteiam
  sítios e rolam chance ~ vento acima do FLOOR × PFX (MAX dobra, não
  4× — vendaval já é vendaval). O(tentativas), floresta de 500 células
  custa o mesmo que um quintal.
- **Rajada despe a árvore**: `Wind.gust() ≥ 0.70` com cooldown de 3s →
  5-8 folhas de copas reais de uma vez, no mesmo envelope do front do
  WindFX.
- Folha nasce NA copa (`s.h − 1..5`), com `lift` negativo (afunda
  enquanto o vento carrega — o clamp de chão apara), tinta da paleta
  LEAF; semente da touceira com SEED/SEED_B; pétala com paleta própria
  (`VegFX.PETAL`) sobre o kind seed. Tudo marcado `veg`.
- As folhas genéricas do pickKind FICAM: em vendaval o ar carrega
  folhagem de além da tela; o VegFX adiciona as que você vê soltar.

**Portão** (`tests/veg_probe.lua`, duas rodadas):

| medição | valor |
|---|---|
| sítios Route 1 (árvore/touceira/canteiro) | 124 / 104 / 52 |
| sheds em 10s de GALE (folha/semente/pétala) | 18-19 / 19-22 / 4-8 |
| **origem: folhas jovens vs copa real** | pior distância 7.0-9.8px, **0 violações** |
| FLOOR (row OFF) | 0 emissões, gate correto |
| erros / canários | 0 / vivos |

Crop: `probe_out_veg/veg_crop.png` — motes anelados sobre as copas e os
canteiros. Nota de arquitetura: o caminho de DRAW não precisou de nada —
o campo do WindFX desenha o que quer que esteja nele, e a validação de
pixel desse caminho é a da T3; o que a T11 muda (onde nasce) é provado
numericamente. Limite conhecido: árvores de mapas vizinhos não emitem
(mesma limitação do StepFX com walkers vizinhos).

### T12 — emissor: água (FEITA, 2026-08-23)

`lib/SprayFX.lua`, o terceiro emissor, no molde da T11 (campo do WindFX
via `emit` — borrifo sem vento não existe, o FLOOR acolhe). Sítios = a
faixa de margem (célula d'água com vizinho de terra em 4-viz, com a
normal média para a terra guardada por sítio), scan por troca de mapa,
emissão amostrada + burst de gust. `WindFX.emit` ganhou `opts.src` (o
marcador genérico de emissor; `veg` da T11 continua).

**A lei do tamanho, e as duas rodadas que ela custou:**

1. `sizeAt` NA margem: mar 0.12, lagoa 0.10 — iguais, porque o fetch
   morre em toda beira por design. FAIL que não testava nada.
2. A 1.5 células mar adentro: 0.23 vs 0.19 — `fetch01 = células/10`
   domina em qualquer corpo a essa distância. FAIL de novo, e de quebra
   apareceu um bug real: o sorteio no mapa inteiro com filtro de alcance
   depois fazia a taxa depender das margens LONGE (mar emitia como
   lagoa).
3. **4 células (64px) mar adentro + sorteio na lista em alcance**: mar
   0.39-0.43, lagoa 0.08 (o sample passa da lagoa inteira e cai em terra
   calma — lagoa não tem 4 células de fetch em lugar NENHUM, que é a
   física honesta de não ter carneirinho). Mar 21-22/10s, lagoa 3-4/10s,
   **≥7×**, e a contagem bate com a previsão analítica (1.8 tentativas/
   pulso × size × 28.6 pulsos).

**Portão** (`tests/spray_probe.lua`): sítios 128 na Route 19 / 16 na
lagoa; origem ≤9.6px com zero violações; FLOOR 0 com gate correto; zero
erros; canários vivos. Crop `probe_out_spray/spray_crop.png` — flagra
CAÇADO (spray vive 0.7-1.6s a ~95px/s; fim de janela segura 1-2 motes já
fora do quadro — o probe espera o instante com ≥2 visíveis), com o
jogador re-locado pro lado sul da água (armadilha da câmera).

**Descopo declarado: cachoeira.** Nenhuma classe de tile, flag de mapa
ou módulo do mod sabe o que é uma cachoeira (grep: zero), Gen 1 tem
meia dúzia de tiles disso em lugares que esta câmera mal visita, e névoa
de cachoeira em calmaria exigiria um campo próprio além. A margem é o
feature de todo dia; a cachoeira espera uma razão para existir.

---

## Riscos aceitos

- **Gold vai quebrar** e vai custar uma sessão de conserto. Decisão consciente.
- **Destravar passes pode acordar feature nunca validada** — precedente: o rim
  do ANIME acendendo no piso inteiro quando um passe morto foi ligado. Para o
  AmbientLife esse risco foi coberto pelo smoke (população real, dia e noite);
  para os lampiões/relâmpago sobre cards (T5) ainda não.
- **O campo cheio de WindFX não foi conferido a olho** — e agora o balé da
  turbulência (T7) e a leitura de material em movimento (T8) também não:
  still não mostra redemoinho nem inércia. Uma sessão de GALE olhando a
  poeira paga as três dívidas de uma vez.
- **Chuva e neve herdaram o shiver da turbulência via flowAt** (share
  0.35, de propósito menor que o do solver). Os gates numéricos medem
  contagem, não ângulo — nada reprova. O look de chuva foi re-olhado em
  2026-08-25 (o conserto dos impactos, adendo na T3-Weather); o de neve
  e o shiver em movimento seguem sem reavaliação.
- **Três probes antigos ainda usam o shot de 2 yields** (ver armadilha 7).
  As conclusões deles foram corroboradas por contadores, mas releituras
  futuras devem migrar pro shot que espera o callback.
- **O parity probe da T1 perdeu o baseline de propósito**: a T7 muda o
  movimento (é a função dela). `run_parity.cmd` contra números pré-T7 vai
  acusar diferença real, não regressão.
