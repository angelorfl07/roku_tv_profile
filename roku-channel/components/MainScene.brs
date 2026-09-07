sub init()
    m.top.setFocus(true)

    m.video = m.top.findNode("videoPlayer")
    m.idleScreen = m.top.findNode("idleScreen")
    m.status = m.top.findNode("statusLabel")
    m.debugUrl = m.top.findNode("debugUrlLabel")
    m.debugState = m.top.findNode("debugStateLabel")

    m.video.enableTrickPlay = true
    m.video.notificationInterval = 1
    m.video.observeField("state", "onVideoStateChange")

    m.stateLog = []
    m.formatsToTry = []
    m.currentFormat = ""
    m.currentUrl = ""
    m.currentTitle = ""
end sub

' disparado automaticamente quando main.brs seta scene.stremioUrl
sub onNewUrl()
    url = m.top.stremioUrl

    ' DEBUG: mostra na tela exatamente o que o canal recebeu, pra facilitar
    ' diagnóstico enquanto testamos (remover depois que estiver tudo ok).
    if url = ""
        m.debugUrl.text = "[debug] URL recebida: (vazia)"
    else
        m.debugUrl.text = "[debug] URL recebida (" + str(len(url)).trim() + " chars): " + url
    end if
    m.debugState.text = ""
    m.stateLog = []

    if url <> ""
        playUrl(url, m.top.stremioTitle)
    end if
end sub

sub playUrl(url as String, title as String)
    m.idleScreen.visible = false
    m.currentUrl = url
    m.currentTitle = title

    ' Ordem de formatos a tentar. A Roku NÃO detecta container sozinha em
    ' playback progressivo — passar o streamFormat errado dá "malformed data"
    ' logo no pos=0 (ex.: "mp4" num Matroska real: o demuxer bate no header
    ' EBML e rejeita). Então detectamos pela extensão e, se o primeiro
    ' formato falhar de cara, tentamos o outro automaticamente.
    if isHls(url)
        m.formatsToTry = ["hls"]
    else if hasExt(url, ".mpd")
        m.formatsToTry = ["dash"]
    else if hasExt(url, ".mkv") or hasExt(url, ".mka")
        m.formatsToTry = ["mkv", "mp4"]
    else if hasExt(url, ".ts")
        m.formatsToTry = ["ts", "mp4"]
    else if hasExt(url, ".mp3")
        m.formatsToTry = ["mp3"]
    else
        ' mp4 / m4v / mov / desconhecido — mp4 primeiro, mkv como rede de segurança
        m.formatsToTry = ["mp4", "mkv"]
    end if

    startNextAttempt()
end sub

sub startNextAttempt()
    if m.formatsToTry = invalid or m.formatsToTry.count() = 0 then return

    fmt = m.formatsToTry.shift()
    m.currentFormat = fmt

    content = createObject("roSGNode", "ContentNode")
    content.url = m.currentUrl
    content.title = m.currentTitle
    content.streamFormat = fmt

    m.debugUrl.text = "[debug] fmt=" + fmt + " (" + str(len(m.currentUrl)).trim() + " chars): " + m.currentUrl

    m.video.control = "stop"
    m.video.content = content
    m.video.visible = true
    m.video.control = "play"
    m.video.setFocus(true)
end sub

function isHls(url as String) as Boolean
    return instr(1, lcase(url), ".m3u8") > 0
end function

' Confere a extensão do path ignorando querystring (?a=b) e fragmento (#x).
function hasExt(url as String, ext as String) as Boolean
    u = lcase(url)
    q = instr(1, u, "?")
    if q > 0 then u = left(u, q - 1)
    h = instr(1, u, "#")
    if h > 0 then u = left(u, h - 1)
    if len(u) < len(ext) then return false
    return right(u, len(ext)) = lcase(ext)
end function

sub onVideoStateChange()
    state = m.video.state

    ' DEBUG: mantém um histórico curto das últimas transições de estado (em vez
    ' de só a última), e sempre checa errorCode/errorMsg — a Roku às vezes
    ' preenche esses campos mesmo quando o estado "grosso" não é literalmente
    ' "error" (ex.: cai direto pra "finished" com duração 0 numa falha de load).
    line = state + " (pos=" + str(m.video.position).trim() +
        " dur=" + str(m.video.duration).trim() + " fmt=" + m.currentFormat + ")"

    errCode = m.video.errorCode
    errMsg = m.video.errorMsg
    if errCode <> 0 or errMsg <> ""
        line = line + " ERRO[" + str(errCode).trim() + "]: " + errMsg
    end if

    if m.stateLog = invalid then m.stateLog = []
    m.stateLog.push(line)
    while m.stateLog.count() > 6
        m.stateLog.shift()
    end while

    full = ""
    for each l in m.stateLog
        full = full + "[debug] " + l + chr(10)
    end for
    m.debugState.text = full

    ' Falha de carregamento: "error", ou "finished" sem nunca ter tido duração.
    isLoadFailure = (state = "error") or (state = "finished" and m.video.duration = 0)

    if isLoadFailure
        if m.formatsToTry <> invalid and m.formatsToTry.count() > 0
            nextFmt = m.formatsToTry[0]
            m.status.text = "Formato '" + m.currentFormat + "' não abriu, tentando '" + nextFmt + "'..."
            startNextAttempt()
            return
        end if
        m.status.text = "Não consegui tocar este stream (formato/codec incompatível" +
            " ou URL inacessível pela Roku). Envie outro pelo celular."
        m.idleScreen.visible = true
        m.video.visible = false
        return
    end if

    if state = "finished"
        m.status.text = "Playback encerrado. Envie outro stream pelo celular."
        m.idleScreen.visible = true
        m.video.visible = false
    end if
end sub

' Tratamento explícito das teclas do controle remoto (reforça o comportamento
' padrão do Video node, que já trata play/pause/rev/fwd automaticamente quando
' está em foco — isto é um fallback para garantir consistência entre modelos).
function onKeyEvent(key as String, press as Boolean) as Boolean
    if not press then return false
    if m.video.visible <> true then return false

    if key = "play"
        if m.video.control = "play"
            m.video.control = "pause"
        else
            m.video.control = "play"
        end if
        return true
    else if key = "rewind"
        m.video.seek = m.video.position - 10
        return true
    else if key = "fastforward"
        m.video.seek = m.video.position + 10
        return true
    end if

    return false
end function
