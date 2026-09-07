sub init()
    m.top.setFocus(true)

    m.video = m.top.findNode("videoPlayer")
    m.idleScreen = m.top.findNode("idleScreen")
    m.status = m.top.findNode("statusLabel")
    m.hint = m.top.findNode("hintLabel")
    m.debugUrl = m.top.findNode("debugUrlLabel")
    m.debugState = m.top.findNode("debugStateLabel")

    m.video.enableTrickPlay = true
    m.video.notificationInterval = 1
    m.video.observeField("state", "onVideoStateChange")
    m.video.observeField("position", "onPosition")

    m.stateLog = []
    m.formatsToTry = []
    m.currentFormat = ""
    m.currentUrl = ""
    m.currentTitle = ""
    m.resumeFrom = 0
    m.lastSavedPos = 0
    m.backArmed = false

    m.reg = CreateObject("roRegistrySection", "resume")
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
    m.backArmed = false

    ' Retomar de onde parou: se a última URL salva no registro é esta mesma e
    ' havia uma posição > 15s guardada, começa de lá. Assim, mesmo que o
    ' usuário saia do canal (VOLTAR), recastar o mesmo stream continua.
    m.resumeFrom = 0
    if m.reg.Exists("url") and m.reg.Read("url") = url and m.reg.Exists("pos")
        p = m.reg.Read("pos").ToInt()
        if p > 15 then m.resumeFrom = p
    end if

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
    if m.resumeFrom > 0 then content.playStart = m.resumeFrom

    m.debugUrl.text = "[debug] fmt=" + fmt + " resume=" + str(m.resumeFrom).trim() +
        " (" + str(len(m.currentUrl)).trim() + " chars): " + m.currentUrl

    m.video.control = "stop"
    m.video.content = content
    m.video.visible = true
    m.video.control = "play"
    m.video.setFocus(true)

    m.hint.text = "▶❚❚ pausa/continua   ·   ◀◀ ▶▶ pula 30s   ·   VOLTAR pausa (2x = sai)"
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

' Salva a posição atual no registro a cada ~5s, pra permitir retomar depois.
sub onPosition()
    pos = m.video.position
    if pos <= 0 then return
    if pos - m.lastSavedPos < 5 and pos > m.lastSavedPos then return

    m.lastSavedPos = pos
    m.reg.Write("url", m.currentUrl)
    m.reg.Write("pos", str(pos).trim())
    m.reg.Flush()
end sub

sub clearResume()
    m.reg.Delete("url")
    m.reg.Delete("pos")
    m.reg.Flush()
    m.lastSavedPos = 0
end sub

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

    if state = "playing"
        ' garante que o Video node tem o foco — sem isto o botão play/pause do
        ' controle não chega no player e o usuário fica sem como pausar.
        m.video.setFocus(true)
        m.backArmed = false
        return
    end if

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
        m.hint.text = ""
        m.idleScreen.visible = true
        m.video.visible = false
        return
    end if

    if state = "finished"
        clearResume()
        m.status.text = "Playback encerrado. Envie outro stream pelo celular."
        m.hint.text = ""
        m.idleScreen.visible = true
        m.video.visible = false
    end if
end sub

' Tratamento das teclas do controle durante o playback. O Video node em foco já
' trata play/pause/rev/fwd nativamente quando enableTrickPlay funciona; isto
' reforça e cobre o caso do MKV progressivo, em que a Roku às vezes não liga o
' trick play nativo.
function onKeyEvent(key as String, press as Boolean) as Boolean
    if not press then return false
    if m.video.visible <> true then return false

    if key = "back"
        ' 1º VOLTAR: garante pausado e "arma" a saída. 2º VOLTAR: deixa sair.
        if m.backArmed
            clearResume()
            return false
        end if
        m.video.control = "pause"
        m.backArmed = true
        m.hint.text = "Pausado. ▶❚❚ para continuar  ·  VOLTAR de novo para sair"
        return true
    end if

    if key = "play" or key = "OK"
        if m.video.control = "play"
            m.video.control = "pause"
            m.hint.text = "Pausado. ▶❚❚ para continuar"
        else
            m.video.control = "play"
            m.hint.text = "▶❚❚ pausa/continua   ·   ◀◀ ▶▶ pula 30s   ·   VOLTAR pausa (2x = sai)"
        end if
        m.backArmed = false
        return true
    else if key = "rewind"
        target = m.video.position - 30
        if target < 0 then target = 0
        m.video.seek = target
        return true
    else if key = "fastforward"
        target = m.video.position + 30
        if m.video.duration > 0 and target > m.video.duration - 5 then target = m.video.duration - 5
        m.video.seek = target
        return true
    end if

    return false
end function
