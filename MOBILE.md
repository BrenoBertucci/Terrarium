# Mobile build (+ RTX + WILD) — o que mudou e por quê

> **1.5.0-mobile.wild.1.** Esta build acrescenta a linha **WILD**: Pokémon
> selvagens *visíveis*, andando na grama, em vez do sorteio cego a cada
> passo. É a primeira coisa neste mod que toca o jogo e não só o desenho
> dele — e por isso é uma linha, com OFF, e em OFF o jogo rola os dados
> exatamente como sempre rolou. Veja a seção no fim deste arquivo, e o
> README para as regras.

> **1.4.0-mobile.rtx.1.** Esta build acrescenta ao mobile 1.3.0 um passe de
> *fake ray tracing* em espaço de tela e um degrau de sombra suave. Nada
> disso é obrigatório: a linha **RTX** tem OFF, e em OFF o frame é
> byte-a-byte o de antes — nem o depth buffer legível é alocado. Veja o
> README para o que cada degrau marcha, e o final deste arquivo para o que
> foi tocado no código.


Este é o Dramatic Shape Voxel Mod 1.3.0 com as mudanças necessárias para
rodar num Android de entrada (o alvo foi um Samsung A14 5G: Mali de 2
núcleos, painel 2408×1080). O `id` do mod e `TERRARIUM` (independente do upstream `DRAMATIC_SHAPE`),
então ele **substitui** o original — não instale os dois ao mesmo tempo.

Nada aqui muda o que o mod *faz*. As mudanças são todas sobre quanto
trabalho ele pede por frame.

## Duas linhas novas no menu OPTIONS

| linha | valores | padrão |
|---|---|---|
| **RES** | 1/2 · 1/3 · 1/4 · FULL | **1/2** |
| **SHADOWS** | LOW · OFF · HIGH | **LOW** |

Ambas ficam no menu inclusive sob o preset FULL — é justamente sob FULL que
elas mais importam, e um preset que escondesse as linhas de performance
seria um preset do qual não dá para sair num aparelho lento.

**RES** é a que decide se o modo roda. Ela é o divisor da resolução em que
o passe 3D é rasterizado antes de ser ampliado de volta para a tela. Todo
custo do passe é quadrático nela: 1/2 é quatro vezes menos de tudo, 1/3 é
nove. A ampliação é *nearest*, então o resultado é mais quadriculado, não
mais borrado — que é o defeito certo para esta arte.

**SHADOWS LOW** mantém sombras projetadas de verdade, mas num mapa de
sombra de 512–1024 texels em vez de 2048, com um tap em vez de quatro, sem
os mapas vizinhos projetando, e redesenhado a cada dois frames enquanto se
anda. **OFF** desliga o passe do sol inteiro e devolve as sombras chapadas
sob os pés — que é o caminho que o mod já tinha para drivers sem canvas de
profundidade.

Colocar RES em FULL e SHADOWS em HIGH devolve o mod original.

## O que foi mudado no código

| arquivo | mudança |
|---|---|
| `lib/Quality.lua` | **novo.** As duas configurações e as constantes derivadas delas. |
| `lib/Voxel3D.lua` | O passe 3D renderiza num canvas `RES` vezes menor e `endScene` amplia para o tamanho que o engine precisa compor. Variante do shader com um tap de sombra em vez de quatro. |
| `lib/ShadowMap.lua` | Escada de resolução e alvo vindos de `Quality`; interruptor OFF; adiamento de redesenho enquanto se anda. |
| `lib/VoxelScene.lua` | Mapas vizinhos deixam de projetar sombra na escada LOW. |
| `lib/BattleScene.lua` | O mesmo, para a arena de batalha. |
| `lib/TiltShift.lua` | Gaussiana de 9 taps reduzida a 5 por amostragem linear (mesmo desfoque), e o desfoque passa a rodar na resolução reduzida em vez da resolução do painel. |
| `lib/ChunkMesher.lua` | Fatias de construção de malha por frame: 12ms → 5ms (urgente), 5ms → 2ms (ocioso), 30ms → 20ms (coberto). **E o culling espacial** — ver abaixo. |

## Por que a escada do mapa de sombra não fazia nada

Vale registrar, porque não é óbvio. `ShadowMap.fit` escolhia a menor
resolução que resolvesse 0,45 world-pixel por texel. Numa tela de celular o
frustum de luz sai com cerca de 890 world-pixels de lado — 890/1024 = 0,87
e 890/1536 = 0,58, ambos acima do alvo. A busca caía no 2048 **todo frame**.
A escada existia mas nunca era usada; era uma constante de 4,2 milhões de
texels, redesenhada a cada quarto de pixel de movimento da câmera.

## Culling espacial (mobile.2)

O `ChunkMesher` se chamava assim desde o primeiro corte, mas não havia
chunk nenhum: o terreno de um mapa era **uma** malha, e todo frame
submetia ela inteira — mais a inteira de cada mapa conectado — estivesse na
tela ou não, e de novo no passe do sol. Uma casa tem algumas centenas de
kilobytes de vértices; uma rota tem 10 a 20 MB. É por isso que interior
sempre rodou bem e mundo aberto nunca.

Agora a caminhada da geometria alimenta um sink por célula espacial, e o
desenho submete só as células que encostam na caixa da câmera. O
`runGeometry` não sabe de nada disso — um quad é roteado por onde caiu o
seu primeiro canto, que é a única coisa que todo quad deste mesher tem em
comum.

- **Células largas e rasas** (256 × 64 world pixels). Não é arbitrário: os
  mapas Gen 1 são estreitos e altos (uma rota tem dez blocos de largura e
  vinte de altura) e a visão é o contrário — larga, e rasa na direção em
  que a câmera olha. Quase todo o culling disponível está no eixo Z.
- **Altura por célula.** A caixa é desenhada no chão, e um prédio plantado
  logo além do alcance ainda aparece acima do horizonte. Em vez de assumir
  o pior caso (um telhado de 160px) para todas as células, cada uma guarda
  a altura que realmente alcança — a maioria é chão raso e pode ser
  descartada bem mais perto.
- **Caixa generosa de propósito** (`VoxelScene.bounds`). Errar para mais
  custa alguns milhares de triângulos; errar para menos é um buraco no
  mundo. O alcance ao norte usa o mesmo cálculo a que o frustum de luz é
  ajustado, mas contra um teto duas vezes mais distante: o passe do sol
  pode abrir mão do campo distante porque o shader dele já dissolve
  aquelas sombras, terreno que simplesmente acaba tem uma borda visível.
- **Mapas vizinhos saem de graça.** Um mapa só é conectado do lado para o
  qual você *não* está olhando, na maior parte do tempo — e então nenhuma
  célula dele passa no teste.
- **A batalha não usa caixa.** A arena é enquadrada por uma câmera
  *posicionada*, com yaw e campo de visão próprios, e a `VoxelScene.bounds`
  responde pela órbita do modo livre. Entregar essa câmera a ela seria
  fazer a pergunta errada. O chunking continua valendo lá; só a rejeição
  não.

Nos ângulos de 15 e 35 graus isso descarta a maior parte de uma rota. Em
75 graus o horizonte está genuinamente em quadro e quase nada é
descartado — que é o comportamento correto, porque nesse ângulo você
realmente está vendo a rota inteira.

## O passe RTX (rtx.1)

Um passe novo, e um arquivo novo: `lib/RayFX.lua`. Tudo o que ele faz é
marchar raios pelo **depth buffer que o passe 3D já preencheu** — AO nos
cantos, reflexo na água pela normal analítica da própria ondulação, e
raios de luz em direção ao disco do sol. O raciocínio inteiro está no
cabeçalho do arquivo; aqui fica só o que foi tocado em volta dele.

| arquivo | mudança |
|---|---|
| `lib/RayFX.lua` | **novo.** A linha RTX, o shader (três variantes por `#define`) e o passe. |
| `lib/Mat4.lua` | `Mat4.invert` — a matriz da câmera ao contrário, que é como um pixel e sua profundidade voltam a ser um ponto do mundo. Eliminação de Gauss-Jordan com pivotamento; roda uma vez por frame. |
| `lib/Voxel3D.lua` | O depth buffer passa a ser um canvas **legível** quando alguém vai lê-lo (`depthstencil`), e o interno de sempre quando não. `endScene` roda o passe antes do upscale — então a arena de batalha herda tudo de graça. Mais a variante PCSS do shader da cena. |
| `lib/ShadowMap.lua` | `ShadowMap.softness()`: o tamanho aparente do sol, a profundidade do frustum e o texel do degrau, condensados no único número que o filtro suave precisa. |
| `lib/Quality.lua` | O degrau **SOFT** acima de HIGH, e `Quality.pcss()`. A escada de RES passa a ter FULL em segundo lugar em vez de último. |
| `main.lua` | A linha RTX no menu e na página do gerenciador. |

### Duas armadilhas que valem registro

**Continuação de linha não existe aqui.** O dialeto GLSL deste driver
recusa a barra invertida no fim da linha, então macro de várias linhas
simplesmente não compila — os taps de AO e a busca de bloqueador viraram
funções. Foi o único erro real que a primeira versão tinha, e só apareceu
compilando os nove shaders no hardware de verdade.

**A água se identifica pela geometria, não por uma flag.** Ela é a única
classe que fica abaixo de zero (é rebaixada a -2 para o lábio da margem
aparecer), então um ponto reconstruído abaixo de -0,4 *com a normal para
cima* é a superfície da água e nada mais é. A segunda metade do teste é o
que mantém as faces laterais do lábio de fora — sem ela, uma tira de dois
pixels da margem refletiria em pé.

## Pokémon na grama (wild.1)

Três arquivos novos e nenhum passe novo. A linha **WILD** troca o sorteio
cego do encontro selvagem por Pokémon que ficam *de pé* na grama: a mesma
tabela de encontros do mapa, sorteada pelos mesmos dez baldes cumulativos,
decide quem está ali agora — e a batalha começa quando você anda em cima
de um (ou aperta A nele).

| linha | valores | padrão |
|---|---|---|
| **WILD** | ROAM · MIX · OFF | **ROAM** |
| **W-COUNT** | SOME · FEW · MANY | **SOME** |

**ROAM** desliga o sorteio por passo no terreno em que este mod colocou
alguém. **MIX** deixa os dois. **OFF** é o jogo original.

| arquivo | mudança |
|---|---|
| `lib/RoamerArt.lua` | **novo.** Assa uma folha 16×96 por espécie a partir do *front pic* de batalha e grava em `save/mod-derived/TERRARIUM/roamers/`. |
| `lib/Roamer.lua` | **novo.** O objeto de mapa: mesmo contrato do `src/world/NPC.lua`, com o vagar preso ao terreno de onde ele foi sorteado. |
| `lib/WildRoamers.lua` | **novo.** Quem aparece, onde, quantos, o que some, a batalha, e as duas costuras do engine. |
| `main.lua` | A linha no menu, a tecla `9`, `WildRoamers.update()` no hook de update do pipeline e o wrap de `encounter.roll`. |

### Por que a arte vai para o disco

Porque uma folha **num caminho** é um sprite que o *engine* entende. O
`SpriteRenderer` carrega, o *bake* de OBP recolore, o shader de zona do SGB
pinta com a paleta do mapa, a grama alta desenha por cima dos pés, o passe
voxel corta o cartão dela e o sol joga a silhueta — e cada uma dessas
coisas é indexada pelo caminho da imagem. Uma `Image` criada em memória
teria exigido ensinar todas elas; um arquivo não exige tocar em nenhuma.

O custo é uma pausa de alguns milissegundos na primeira vez que cada
espécie aparece, e uma vez só na vida do save.

### Custo por frame

Cada Pokémon visível é **mais um cartão de sprite** no frame e mais um
projetor de sombra no passe do sol. Em SOME são seis; em MANY, dez. No
alvo mobile isso é ruído perto do terreno, mas é a razão de **FEW**
existir — e a razão de o padrão não ser MANY.

### As duas costuras

**Andar em cima de um** é lido em `Player:tryMove`, depois da chamada
interna: `"blocked"`/`"entity"` é exatamente o instante em que um jogo
moderno começa o encontro, e ler *depois* mantém a virada no lugar, o
cooldown da batida e tudo o mais que um passo recusado já faz.

**Apertar A** cai em `OverworldState:talkTo`, porque um roamer fica em
`ow.npcs` (é assim que o próprio engine o anda, de graça) e portanto o
`interact()` o encontra na célula da frente. O `talkTo` inteiro é sobre
texto, item, treinador e script de um objeto de mapa — nada que um Pokémon
tenha —, então ele é respondido antes.

## Quando o modo 3D simplesmente nao aparece

Se o mod instala, a linha **VOXEL** aparece no OPTIONS, voce liga e nada
acontece -- o jogo continua chapado -- o que houve foi o driver da GPU
**recusar o shader**. Nao e instalacao errada, e nao adianta reinstalar.

Ate a v1.30.0 isso era o fim: o shader da cena e um bloco unico, e qualquer
construcao que o driver recusasse derrubava o modo inteiro, calado. Duas
construcoes dele sao legitimamente recusaveis por um driver GLES2 conforme, e
as duas estavam no ar:

- o **estagio de vertice amostra tres texturas**. GLES2 pode expor ZERO
  unidades de textura no vertice, e ai o shader nao linka. Foi o que pegou os
  aparelhos com GPU **Adreno**;
- o estagio de fragmento usa **dez samplers**, e GLES2 garante oito.

Agora a compilacao **desce uma escada** em vez de desistir:

| degrau | o que perde |
|---|---|
| `full` | nada |
| `no-vtf` | as pegadas e o desgaste lembrado do capim |
| `no-crypt` | o granito fotografado do interior da Torre |
| `minimal` | os dois |

So o ultimo degrau falhar significa ficar sem 3D -- e nesse caso o mod passa
a **dizer o porque**. O relatorio sai no log do sistema (`logcat` no Android)
e num arquivo `TERRARIUM-gpu-report.txt` ao lado do save:

```
gpu:      Adreno (TM) 640
driver:   OpenGL ES 3.2 v1.r0p0
glsl3:    true
derivs:   true
3D:       OFF -- the mode could not build
rung:     4 minimal (vertex taps OFF, crypt stone OFF)
refusals: 4
  [1 full] key=-1-: <o que o driver disse>
```

**Esse bloco e o que um relato de bug precisa.** Cole ele inteiro.

---

# 1.33.0-beta — o Poco X7 rodava a 1 fps, e o motivo não era o que a página acima supunha

Um Poco X7 Global (Dimensity 7300-Ultra, **Mali-G615 MC2**, painel **2712×1220
em paisagem = 3,31 megapixels**) rodava a linha VOXEL a cerca de **um quadro
por segundo**. Tudo que está escrito acima já estava aplicado: RES 1/2 por
padrão, SHADOWS LOW, o culling espacial, a escada do mapa de sombra. Nada
disso ajudava, e o motivo é que o custo não estava em nenhum lugar onde essas
linhas mexem.

## 1. Todo render target era SETE VEZES o que o código pedia

`love.graphics.newCanvas(w, h)` **não faz uma textura w por h.** Faz uma cujo
tamanho em *unidades* é w por h e cujo tamanho em *pixels* é `w * dpiscale`,
onde `dpiscale` é `love.graphics.getDPIScale()` por padrão. No desktop isso é
1 e os dois números são o mesmo — que é exatamente por que isso ficou
invisível a vida inteira do mod. No Android é a densidade do painel: **2,625**.

2,625 ao quadrado é **6,9**:

| alvo | pedido | alocado |
| --- | --- | --- |
| canvas da cena (RES 1/2) | 1356×610 = 0,83 Mpx | 3560×1601 = **5,70 Mpx** |
| canvas de apresentação | 2712×1220 = 3,31 Mpx | 7119×3202 = **22,79 Mpx** (91 MB) |
| depth buffer legível | 0,83 Mpx | **5,70 Mpx**, escrito na memória todo frame |
| mapa de sombra (LOW) | 512² | **1344²** |
| e o mesmo de novo para RayFX, TiltShift, Bloom, Weather e o par do DOF |||

Um alvo de render **sete vezes a área da tela em que ele é mostrado**,
blitado todo frame. É por isso que RES não salvava nada: RES divide um número
que depois é multiplicado de volta por 2,625 duas vezes.

O conserto é `dpiscale = 1`, e não é um meio-termo: o tamanho que o caminho de
render pede **já está em pixels de framebuffer** (ver `sceneSize` no
`main.lua`), então fixar o dpiscale em 1 não muda o tamanho em UNIDADES —
a composição, a projeção, os closures de FX e cada uv de cada shader veem
exatamente os mesmos números de antes. Muda só quantos pixels existem atrás
deles. **`lib/RenderTarget.lua`** existe para que isso não possa voltar: toda
alocação passa por lá, e `RenderTarget.dpi` deixa os probes reproduzirem a
alocação do Android num desktop.

## 2. O passe do sol se realocava duas vezes por frame — e desligava a própria otimização

`ShadowMap.available()` chamava `getCanvas(Quality.shadowSizes()[1])` para
responder "dá para rodar?". Mas `getCanvas` não responde nada: ele **faz** o
canvas daquele tamanho. Rodando uma vez por frame, junto com `begin()`
fazendo-o do tamanho que `fit()` realmente quer (768 numa janela de celular),
isso é **dois render targets destruídos e dois criados por frame**.

E custou mais que as alocações. `getCanvas` põe `ready = false` quando
realoca; `ShadowMap.stale` começa com `if not ready then return true end`; e o
adiamento "redesenha a cada dois frames" da seção acima mora atrás desse
teste. Ou seja: **o adiamento nunca disparou uma vez sequer**, e o passe do
sol redesenhava a geometria inteira do mapa em todo frame — inclusive parado.

## 3. A linha RES é um DIVISOR, e divisor não é custo

1/2 da janela em que este mod foi escrito são 332 mil pixels. 1/2 do painel
daquele celular são 827 mil. A mesma linha, duas vezes e meia o trabalho.

Então **RES ganhou AUTO** (`lib/AutoQuality.lua`), que é o padrão novo:

- um **orçamento de pixels** decide o primeiro frame (0,22 Mpx num tiler,
  1,6 Mpx num desktop), então qualquer painel começa perto da mesma
  quantidade de trabalho — no Poco X7 isso é 1/4;
- depois ele **mede** e anda a escada até os frames caberem, mirando 30 fps.

Duas coisas que um governador precisa e quase nunca tem:

- **Não oscila.** Um degrau do qual já se desceu fica marcado e a subida
  nunca volta nele. A caminhada é monótona: sobe no máximo uma vez por
  degrau, marca o primeiro que não segura, e assenta um abaixo dele.
- **O portão de outlier é RELATIVO.** A primeira versão recusava qualquer
  frame acima de 250 ms — o que num aparelho a 1000 ms por frame recusa
  *todos*, e o governador ficaria parado justamente na máquina para a qual
  ele foi escrito. Agora o portão é o maior entre 250 ms e 4× o que este
  aparelho vem fazendo.

`tests/autoquality_offline.lua` prova as duas coisas com frames sintéticos,
sem GPU nenhuma (`python tools/run_autoquality_offline.py`).

Duas linhas novas na escada de RES: **1/6 e 1/8**. 1/8 é o piso porque no
`fitScale` de um celular isso é mais ou menos um texel de canvas por pixel de
mundo — abaixo disso não há o que economizar.

## 4. E o resto, que só um tiler cobra

| o que | por que num Mali |
| --- | --- |
| **RTX passa a ter AUTO**, que é OFF num tiler | RT marcha **treze** buscas de profundidade *dependentes* por pixel num passe de tela cheia, e força o depth buffer da cena a ser um canvas LEGÍVEL — o único anexo que um tiler jamais escreveria na memória |
| `RayFX.floor` não pode mais desfazer o AUTO do dispositivo | a cripta e a loja pediam AO por baixo, e ligavam o passe inteiro de volta dentro de cada Poké Mart |
| `clear()` antes de todo blit que cobre o alvo inteiro | ligar um alvo sem limpar diz ao driver que o conteúdo antigo importa, então o tile é **carregado** da memória antes do primeiro fragmento — e depois todo ele é sobrescrito. São 13 MB de leitura por passe por frame naquele painel |
| textura de chunk só é religada quando muda | eram 66 a 86 `Mesh:setTexture` redundantes por passe |
| vizinho fora de quadro não entrega mais grama, flores, postes nem árvores | quatro malhas de mapa inteiro, para o mapa e para cada vizinho, nos dois passes, sem caixa nenhuma |
| a escada de sombra HIGH/SOFT é limitada num tiler | 2048² é 4,2 megatexels de cor mais outro tanto de profundidade, todo frame |
| FULL não prende mais o desfoque no máximo num celular | e a linha T-SHIFT deixa de sumir do menu sob FULL lá, que era o modo mais caro do mod sem nenhum jeito de chegar no interruptor |

## O que foi medido, e o que não dá para medir daqui

O desktop desta casa é uma Intel UHD numa janela de 1,33 Mpx, e o `dpiscale`
dela é 1 — então **o conserto de número 1 é literalmente um no-op aqui**. O
que dá para provar no desktop foi provado:

- `tests/mali_cost_probe.lua` — custo por passe, sensibilidade a resolução,
  e a contagem de **trocas de canvas por frame**, que é o número que um tiler
  cobra e que viaja entre máquinas.
- `tests/visual_ab_probe.lua` — oito mapas, tudo que se mexe fixado, e o
  build de construção da malha **aguardado por `ChunkMesher.pending()` em vez
  de contado em frames**. Sem isso o piso de ruído é maior que o efeito e a
  medição não é medição.
- `tests/gpu_compat_probe.lua` — a escada GLES2 ainda compila nos 4 degraus
  e nas 2 precisões depois da mudança no GLSL.
- `tests/autoquality_offline.lua` — o governador, em aritmética pura.

**Duas mudanças foram implementadas, medidas e REVERTIDAS**, e o registro
delas vale mais que elas valiam:

- cortar os casters do sol pela caixa da **luz** em vez da câmera parecia
  obviamente certo e não é: o volume ortográfico é ajustado em espaço de
  LUZ, então ele é cisalhado e alcança mais longe em x/z do mundo que a
  caixa de onde saiu. Sombras de árvore sumiram — 4,0% dos pixels da ROUTE_1
  contra um piso de ruído de 0,0%.
- condicionar o *fetch* de `glassMask` ficou de fora, e o motivo é o registro
  mais útil dos três. Com ele, VIRIDIAN_CITY diferia 1,04% da base, tudo nas
  **flores** (que caem nos retângulos da máscara por acidente, como o próprio
  comentário do shader avisa); revertendo, aquele par deu 0,000%. Parecia
  bissecção limpa e não era: uma execução posterior do mesmo build revertido
  diferiu **2,46% de si mesma** naquele mapa. O piso de ruído do probe nesses
  mapas é de 1 a 3% e **não resolve** uma mudança desse tamanho. A frase
  honesta não é "essa linha quebra as flores", é "não deu para mostrar que ela
  é inofensiva" — e um fetch a menos não paga uma pergunta em aberto agora que
  o RES AUTO deixa o canvas da cena do celular em um quinto de megapixel.
- trocar a margem de 96 px do chunk por bounds exatas abriu uma faixa de céu
  no alto da ROUTE_1. Aquela margem não está só cobrindo quads que
  transbordam a célula: está cobrindo o alcance norte de `VoxelScene.bounds`,
  que é ajustado para onde o CHÃO deixa de ser visível e fica cerca de um
  chunk aquém de onde o terreno ainda aparece no horizonte. **O bug de
  verdade é a caixa de visão**, e a margem fica até ele ser consertado.

Nenhum dos oito mapas do A/B final ficou acima do próprio piso de ruído.

---

# 1.34.0-beta — o chuvisco que só existia em GLES

A 1.33.0-beta subiu no Poco X7 e voltou com um sintoma novo: **um sinal de
interferência de TV sobre o mundo inteiro, pior na água, e só no Android**.

## O estágio de fragmento inteiro rodava em fp16

Um fragment shader de desktop calcula em fp32. Um de GLES não. A precisão
padrão de `float` no estágio de fragmento é **mediump**, e a LÖVE emite
exatamente isso — está no fonte dela, extraível da `love.dll`:

```glsl
GLSL.PIXEL = { HEADER = [[
#ifdef GL_ES
	precision mediump float;
#endif
```

`mediump` num celular é **fp16**: onze bits de mantissa, máximo 65504, e
**resolução de UM na casa de 1024**.

Este shader trabalha em **pixels de mundo**. Uma rota tem centenas deles e o
outro lado de uma cidade passa de mil — então em fp16 uma coordenada de mundo
é quantizada a cerca de um pixel de mundo inteiro. E tudo depois herda: a
busca no mapa do sol (`vSun`), a normal da onda (`vWave`), a distância da
margem (`vShore`), todo `floor()` e `fract()` que vira padrão, e os seis
hashes `fract(sin(dot(...)) * 43758.5)`, cujo trabalho é **amplificar** uma
mudança pequena da entrada. Uma quantização que se desloca quando a câmera
anda, amplificada de propósito, é literalmente chuvisco de TV.

O `VXHP` da 1.31 tinha consertado essa mesma classe de problema para os
**uniforms**, porque lá era erro de link e o modo não subia — um erro que se
anuncia. As varyings e as locais tinham o mesmo defeito e **nenhum erro para
anunciá-lo**: só `vWorld` e `vGrid` carregavam qualificador, e o resto rodou
em fp16 em todo aparelho Android desde sempre.

Uma linha resolve todas de uma vez:

```glsl
#ifdef PIXEL
#if defined(GL_ES) && defined(GL_FRAGMENT_PRECISION_HIGH)
  precision highp float;
#endif
#endif
```

**As duas metades da guarda são essenciais e nenhuma é óbvia:**

- `#ifdef PIXEL` — o estágio de vértice já é highp por padrão, e um macro que
  pode valer `mediump` o **rebaixaria**. Aquilo são as posições dos vértices.
- `GL_ES` **junto com** `GL_FRAGMENT_PRECISION_HIGH` — a LÖVE define o segundo
  **no desktop também**, e lá `highp` é `#define`ado para nada
  (`#if !defined(GL_ES) && __VERSION__ < 140 → #define highp`). Perguntar só
  por ele emite `precision  float;` e derruba o shader inteiro. Aconteceu
  duas vezes durante este trabalho, as duas pegas pelo `gpu_compat_probe`
  (ALL PASS → 34 falhas, na mesma rodada).

E porque esse tipo de coisa não pode depender de alguém lembrar:
**`tools/essl1_check.py`** afirma as duas regras de GLES2 que já tiraram o
modo do ar, como texto, a partir do fonte publicado — a linha de precisão com
a guarda certa no estágio certo, e **todo uniform da região compartilhada com
qualificador explícito** (37 hoje, eram 36 na 1.31). Um segundo, sem GPU.

## O xadrez da água

Separado do chuvisco, e o motivo de "na água é pior" ter duas causas. O dither
ordenado da água era `floor(sc / 2.0)` — **dois pixels de CANVAS, fixo**. Um
xadrez só é dither enquanto a célula tem o tamanho de um pixel de tela: em RES
FULL são 2 pixels, e no 1/4 que o AUTO escolhe num painel de 3,31 Mpx são
**oito**. O dither virou o padrão. Agora a célula e a amplitude seguem o RES, e
em FULL e 1/2 é identidade exata.

## E o que ainda não tem resposta

**A torre nova e a loja nova não aparecem no aparelho, e não reproduzem
aqui.** Foram fotografadas de pé em todas as combinações que um Mali poderia
impor: rung `full`, rung `no-crypt` (os cinco samplers da cripta recusados, que
é o que a `lib/Shop.lua` diz que a loja empresta), uniforms forçados a
`mediump`, RES 1/4 e RES 1/2. Em todas, a loja está montada e a torre de pedra
com o adro está de pé.

Então a próxima pergunta não é uma hipótese, é um dado que falta — e o mod não
tinha como dar nenhum. Daí a linha **DIAG** (`lib/Diag.lua`, padrão OFF), que
imprime sobre o canto da tela:

```
TERRARIUM 1.34.0-beta
gpu: Mali-G615-MC2 / OpenGL ES | mobile: true | panel: 2712x1220 | dpiscale: 2.625
shader   rung=full prec=highp refusals=0 avail=true
RES      AUTO -> 1/4   SHADOWS LOW
RTX      AUTO -> off   PFX ON
rows     TOWER=NEW SHOP=NEW CRYPT=NEW TREES=VOXEL
TowerKit ON  ShopKit ON  CryptKit ON  RoomKit loaded
map      LAVENDER_TOWN   models=17
```

Cada linha ali mata uma hipótese: a versão instalada, o degrau que o driver
aceitou, se o dispositivo foi detectado como móvel, o que cada linha resolve,
se algum kit **falhou ao carregar** (um módulo que estoura no load é engolido
pelo loader e a feature some calada), e **quantos modelos o mapa construiu** —
que separa "o kit está desligado" de "o kit rodou e não produziu nada".

Existe porque um celular não pode ser perguntado: `print` não chega ao logcat
de dentro de um mod, `io` e `os.getenv` não estão no sandbox, a pasta do save
não é legível por adb num Android moderno, e o único canal que funciona — uma
foto da tela — carrega pixels e mais nada.


## Adendo 1.34.1 — a correcao da correcao

A 1.34.0 derrubou o modo 3D no celular inteiro. A linha `precision highp
float;` nao pode simplesmente ser adicionada: a LOVE concatena
`GLSL.PIXEL.MAIN` **antes** do fonte do mod, e o MAIN carrega
`vec4 effect(vec4 vcolor, Image tex, vec2 texcoord, vec2 pixcoord);` -- uma
declaracao adiantada escrita com o `mediump` padrao dela. Levantar o padrao
depois disso deixa a definicao com parametros `highp` contra um prototipo
`mediump`, e GLSL ES 1.00 recusa. Sem shader, sem modo.

Duas conclusoes, e a segunda vale mais que a primeira:

1. `effect()` fixa os proprios parametros float em `mediump`.
2. **A linha virou um degrau da escada (`FRAG_HIGHP`)**, largavel. Uma
   correcao de precisao que pode tirar o modo do ar nao e correcao. O pior
   caso passou a ser o fp16 que sempre rodou -- imagem com chuvisco em vez de
   nenhuma imagem -- e o `gpu_compat_probe` testa esse fallback com um driver
   falso que recusa o define.

E a licao de metodo: **um degrau so vale se largar ele for testado.** O eixo
novo levou o caso "nada compila" de 8 para 16 recusas, e o numero esta escrito
por extenso no teste para que acrescentar um eixo sem pensar quebre ele.
