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

- [ ] Testar `send_to_roku.sh` com uma URL de vídeo simples (mp4 direto) para
      validar o canal sideloaded antes de mexer no app Android.
- [x] Confirmado: o Stremio expõe player externo — a URL chega automaticamente
      via `ACTION_VIEW`, sem precisar copiar/colar.
- [ ] Validar se as URLs que você usa (torrent puro vs. debrid) são acessíveis
      pela Roku na rede local.
- [ ] Testar compatibilidade de formato: HEVC/H.264, containers MKV, HLS.
- [ ] Compilar o `android-bridge/` no Android Studio e testar em dispositivo
      físico.
