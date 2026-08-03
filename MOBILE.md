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
núcleos, painel 2408×1080). O `id` do mod continua sendo `DRAMATIC_SHAPE`,
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
| `lib/RoamerArt.lua` | **novo.** Assa uma folha 16×96 por espécie a partir do *front pic* de batalha e grava em `save/mod-derived/DRAMATIC_SHAPE/roamers/`. |
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
