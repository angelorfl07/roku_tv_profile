# Stremio → Roku Cast

Levar o conteúdo que você assiste no Stremio (Android) para a Roku TV, com o
vídeo tocando na TV e play/pause/avançar/retroceder funcionando — sem depender
dos apps de espelhamento pagos e ruins da Roku Channel Store.

## O problema real e por que "espelhar" não é a melhor resposta

Espelhamento de tela (Miracast) manda *pixels e áudio já decodificados* do
celular para a TV. Funciona com qualquer conteúdo que o celular consiga tocar,
mas tem custo: a Roku só suporta Miracast (não o protocolo do Chromecast), o
celular precisa ficar ligado com a tela acesa a transmissão inteira, a
qualidade despenca em vídeo com muito movimento, e a bateria do celular sofre.
Além disso o Stremio **descontinuou o suporte a DLNA** e não tem cast nativo
para Roku — só Chromecast é bem suportado oficialmente.

A alternativa melhor é fazer a Roku baixar e tocar o stream **diretamente**,
como o Chromecast faz: em vez de espelhar a tela, mandamos só a URL do vídeo
para um canal Roku que a gente mesmo escreve, e a Roku decodifica localmente
(sem gastar bateria/rede do celular, sem lag de encode). É esse o design deste
projeto.

**Trade-off a testar na prática:** a Roku decodifica em hardware um conjunto
mais limitado de formatos do que o player do Stremio no celular (ExoMKV/H.264
e HLS geralmente tocam bem; HEVC depende do modelo; áudio DTS/TrueHD e alguns
containers MKV mais exóticos podem falhar). Espelhamento nunca falha por causa
de formato — cast direto pode, se o release for muito fora do padrão. Por isso
o app Android também serve como fallback rápido: se o cast direto falhar,
ligar o Miracast nativo da Roku (zero código, ver seção abaixo) resolve na
hora.

## Arquitetura

```
Stremio (Android)
   │  compartilha / abre a URL do stream em outro player
   ▼
Roku Cast Bridge (app Android deste projeto)
   │  HTTP POST (ECP) para a Roku, na mesma rede Wi-Fi
   ▼
Stremio Cast Receiver (canal Roku, sideloaded)
   │  toca a URL num Video node (SceneGraph)
   ▼
Roku TV — vídeo na tela, play/pause/rev/fwd no controle remoto da própria Roku
```

- **`roku-channel/`** — canal Roku privado (BrightScript/SceneGraph), sideloaded
  via Developer Mode (não passa pela Channel Store). Recebe a URL via deep link
  (`ECP /launch/dev`) ou, se já estiver aberto, via `ECP /input` (sem
  relançar/piscar a tela). Toca num `Video` node com `enableTrickPlay = true` —
  o controle remoto da Roku já manda play/pause/rev/fwd nativamente.
- **`android-bridge/`** — app Android (Kotlin) que:
  1. aparece no menu "Compartilhar" e como "player externo" quando o Stremio
     manda a URL de um stream;
  2. descobre a Roku na rede (SSDP) ou usa um IP salvo manualmente;
  3. dispara a chamada ECP para a Roku com essa URL.
- **`scripts/`** — `send_to_roku.sh` (testar o canal via `curl`, sem precisar do
  app ainda) e `package_channel.sh` (empacota o canal num `.zip` para sideload).

## Como o Stremio entrega a URL para o app-ponte

Confirmado: o Stremio Android usado aqui expõe "player externo". Esse é o
caminho usado — ao tocar um stream, escolha "Roku Cast Bridge" na lista de
players. O Android manda a URL via `ACTION_VIEW` com `mimeType=video/*`, que é
exatamente o que o `MainActivity` já trata.

Apps de "player externo" no Android costumam seguir a convenção informal do
MX Player, passando extras como `title` (String) e às vezes `position`/
`headers` junto com a URL. O app já lê esse extra `title` como fallback (além
do `EXTRA_SUBJECT` usado em compartilhamento); os demais extras não são
necessários para o cast funcionar e foram deixados de fora por simplicidade.

Se em algum momento o player externo não estiver disponível para um stream
específico (situação rara), o caminho manual continua funcionando: copiar a
URL do stream e colar direto no app Roku Cast Bridge.

**Streams via torrent puro** (sem debrid) passam pelo servidor local do
Stremio no celular antes de virar um link HTTP — se esse servidor só escutar
em `127.0.0.1`, a Roku (outro aparelho na rede) não vai conseguir acessar a
URL. Isso precisa ser validado testando; se for o caso, **usar um serviço de
debrid** (que já entrega link HTTP direto, acessível de qualquer aparelho na
rede) é o caminho mais confiável para o cast direto funcionar.

## Setup — canal Roku

1. Ativar o Developer Mode na Roku: no controle remoto, pressione em sequência
   Home 3x, Up 2x, Right, Left, Right, Left, Right. Defina uma senha quando
   pedido. Isso abre `http://<IP-DA-ROKU>` com o "Application Installer".
2. Gerar o pacote: `./scripts/package_channel.sh` (cria
   `stremio-cast-receiver.zip`).
3. Acessar `http://<IP-DA-ROKU>` no navegador, logar com usuário `rokudev` e a
   senha definida, e enviar esse `.zip` em "Upload".
4. O canal "Stremio Cast Receiver" abre na Roku. Anote o IP da Roku (aparece
   em Configurações > Rede > Sobre, na própria Roku).
5. Testar sem o app Android ainda:
   `./scripts/send_to_roku.sh <IP-DA-ROKU> "<URL-DE-UM-VIDEO-MP4-QUALQUER>"`

## Setup — app Android (bridge)

O projeto em `android-bridge/` é um projeto Gradle/Kotlin padrão, não foi
compilado neste ambiente (sem SDK do Android aqui). Abra a pasta
`android-bridge/` no Android Studio, deixe o Gradle sincronizar, e rode num
celular físico (mesma rede Wi-Fi da Roku) — não precisa de conta de
desenvolvedor nem de Play Store, é só instalar via USB/depuração.

Depois de instalado:
1. Abra o app uma vez e informe o IP da Roku (ou toque em "Detectar Roku na
   rede").
2. No Stremio, mande o stream para o Roku Cast Bridge (player externo ou
   compartilhar — ver seção acima).

### IP da Roku: salvo e revalidado sozinho (desde v1.1)

O IP fica persistido em `SharedPreferences` (`RokuConfig.kt`) e **não é mais
perguntado a cada abertura**. Fluxo a cada vez que o app abre ou recebe um
stream (`MainActivity.ensureRokuReady`):

1. testa o IP salvo com um health check leve (`GET :8060/query/device-info`,
   `RokuSender.reachable`);
2. se respondeu, usa direto — silencioso, sem UI;
3. se **não** respondeu (Roku trocou de IP no DHCP, mudou de rede, desligou),
   faz uma busca SSDP na rede, salva o novo IP e segue;
4. só mostra erro pedindo ação manual se a busca também falhar.

Botão **"Esquecer IP"** limpa o valor salvo (para trocar de Roku de propósito).

Todas as chamadas (ECP e SSDP) são forçadas pela rede Wi-Fi/Ethernet
(`LocalNetwork.of` → `Network.openConnection` / `Network.bindSocket`), com
fallback pela rota padrão do sistema. Isso evita o Android rotear o socket
pela operadora quando os dados móveis (4G/5G) estão ligados junto com o Wi-Fi.

### ⚠️ Causa real do "não consegui falar com a Roku" (resolvido na v1.4)

O sintoma (`input=-1, launch=-1`, depois "porta 8060 não respondeu ao teste")
**não era rede nem 5G** — era **cleartext HTTP bloqueado dentro do app**. Com
`targetSdk >= 28`, o Android proíbe por padrão qualquer requisição `http://`
(sem TLS) feita pelo app; toda chamada ao ECP da Roku (`http://<ip>:8060/...`)
estourava exceção antes de sair. O navegador do próprio celular acessava a
mesma URL normalmente porque não está sujeito à policy do app — foi o que
despistou o diagnóstico. Corrigido com `android:usesCleartextTraffic="true"`
no `<application>` do `AndroidManifest.xml`. As mudanças de bind de rede /
health check / SSDP das v1.1–v1.3 continuam válidas, mas nenhuma delas
resolvia isto sozinha.

## Fallback sem escrever nada: Miracast nativo da Roku

Enquanto o canal/app não estão prontos, ou para qualquer conteúdo que o cast
direto não conseguir tocar: a maioria das Rokus modernas já suporta Miracast
nativamente (modelos muito antigos, como o Roku Express 3700 original, não
suportam).

1. Na Roku: Configurações > Sistema > Espelhamento de tela > "Solicitar" ou
   "Sempre permitir".
2. No Android: painel de configurações rápidas > "Cast"/"Smart View"/
   "Transmitir tela" (o nome varia por fabricante; em aparelhos Android 12+
   sem Miracast nativo, isso pode não aparecer).
3. Abra o Stremio e toque o conteúdo normalmente — a tela inteira (com os
   controles do player) aparece na TV.

Esse caminho é 100% redundante ao canal Roku em termos de resultado final,
só que com mais lag/qualidade menor e o celular precisa ficar ativo.

## Status / próximos passos

- [x] Canal Roku sideloaded validado de ponta a ponta: ECP `/launch/dev`,
      deep link, `ContentNode`, transporte (`buffering → playing → finished`)
      — testado com `https://www.w3schools.com/html/mov_bbb.mp4`.
      Observação: links de `googleapis.com/commondatastorage` falharam com
      `HTTP response error` mesmo em HTTP puro (sem TLS) — não é bug do canal,
      parece bloqueio de rede/DNS específico pra esse domínio na rede de
      quem testou. Sem relevância prática (o Stremio nunca vai apontar pra
      esse domínio).
- [x] Confirmado: o Stremio expõe player externo — a URL chega automaticamente
      via `ACTION_VIEW`, sem precisar copiar/colar.
- [ ] Testar com uma URL **real** de stream do Stremio (não mais vídeo de
      demonstração) — truque sem precisar do app Android ainda: no seletor
      de "player externo" do Stremio, escolher o Chrome; a URL aparece na
      barra de endereço e pode ser copiada de lá pro `send_to_roku.sh`.
- [~] Testado com stream real do Stremio (IPTV Xtream, 2026-09-07): a URL
      chegou no canal, mas deu `ERRO[-5] malformed data` no `pos=0`. Causa:
      o canal mandava `streamFormat="mp4"` pra tudo que não fosse `.m3u8`, e
      o release era Matroska real (`.mkv`, `video/x-matroska`, H.264 720p +
      E-AC3 — ambos suportados pela Roku Express 3960BR; só o container estava
      declarado errado). Corrigido no `build_version=2`: detecção de
      `streamFormat` por extensão (`.mkv/.mka→mkv`, `.mpd→dash`, `.ts→ts`,
      `.m3u8→hls`, senão `mp4`) + fallback automático `mkv↔mp4` se o primeiro
      falhar no load. **Falta reconfirmar o playback com o canal v2.**
      Nota: a URL do Stremio (`play.dnshtp.com`) responde **302** para um
      `http://<ip>:<porta>` cru — a Roku OS 15.x segue esse redirect em
      playback progressivo sem problema (o destino serve `Accept-Ranges` +
      `Content-Type` corretos); se algum stream futuro falhar só por causa de
      redirect, aí sim resolver o `Location` num Task node antes de tocar.
- [ ] Validar se as URLs que você usa (torrent puro vs. debrid) são acessíveis
      pela Roku na rede local.
- [ ] Testar mais formatos: HEVC, HLS (`.m3u8`), DASH.
- [x] Compilar o `android-bridge/` — CI em `.github/workflows/build-apk.yml`
      gera o `app-debug.apk` a cada push que mexe em `android-bridge/`.
- [ ] **Sideload do canal na Roku de produção (Roku Express 3960BR, "Roku Casa",
      IP 10.0.0.5).** Em 2026-09-07 o `/query/device-info` dela mostrou
      `developer-enabled=true` mas `keyed-developer-id` **vazio** e o
      `/query/apps` sem `id="dev"` — ou seja, o Developer Mode está ligado
      porém o `.zip` do canal nunca foi enviado pra ESTA Roku (o "[x] validado
      de ponta a ponta" acima foi noutra Roku/sessão). O app Android estava
      dando "não consegui falar com a Roku" por causa disso, não por rede: o
      GET `:8060/query/device-info` respondia normal do próprio celular.
      Enviar via `http://10.0.0.5` (Application Installer, usuário `rokudev`).
      A partir da v1.3 o app distingue essa situação e mostra "canal NÃO está
      instalado" com o passo do sideload.
