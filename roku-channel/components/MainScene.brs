sub init()
    m.top.setFocus(true)

    m.video = m.top.findNode("videoPlayer")
    m.idleScreen = m.top.findNode("idleScreen")
    m.status = m.top.findNode("statusLabel")
    m.hint = m.top.findNode("hintLabel")
    m.debugUrl = m.top.findNode("debugUrlLabel")
    m.debugState = m.top.findNode("debugStateLabel")
    m.debugAudio = m.top.findNode("debugAudioLabel")

    ' Trick play NATIVO desligado de proposito: com ele ligado, o Video node em
    ' foco consome rewind/fastforward/play ANTES do onKeyEvent desta Scene, e os
    ' nossos tratamentos (inclusive o aviso de "seek nao suportado") viram codigo
    ' morto. Assumindo as teclas aqui, a Scene fica no controle.
    m.video.enableTrickPlay = false
    m.video.notificationInterval = 1
    m.video.observeField("state", "onVideoStateChange")
    m.video.observeField("position", "onPosition")
    m.video.observeField("availableAudioTracks", "onAudioTracksChange")

    m.stateLog = []
    m.formatsToTry = []
    m.currentFormat = ""
    m.currentUrl = ""
    m.currentTitle = ""
    m.resumeFrom = 0
    m.lastSavedPos = 0
    m.backArmed = false
    m.seekTarget = -1
    m.seekTimer = invalid
    m.baseHint = "OK: pausa/continua   |   << >> : pula 30s   |   VOLTAR: pausa (2x = sai)"

    m.reg = CreateObject("roRegistrySection", "resume")
end sub

' disparado automaticamente quando main.brs seta scene.stremioUrl
sub onNewUrl()
    url = m.top.stremioUrl

    ' DEBUG: mostra na tela exatamente o que o canal recebeu, pra facilitar
    ' diagnostico enquanto testamos (remover depois que estiver tudo ok).
    if url = ""
        m.debugUrl.text = "[debug] URL recebida: (vazia)"
    else
        m.debugUrl.text = "[debug] URL recebida (" + str(len(url)).trim() + " chars): " + url
    end if
    m.debugState.text = ""
    m.debugAudio.text = ""
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
    m.seekTarget = -1

    ' Retomar de onde parou: se a ultima URL salva no registro e esta mesma e
    ' havia uma posicao > 15s guardada, comeca de la. Assim, mesmo que o
    ' usuario saia do canal (VOLTAR), recastar o mesmo stream continua.
    ' (Em MKV progressivo de IPTV isso pode nao pegar se o host ignora Range -
    ' mesma limitacao do seek; custa nada manter e funciona quando o host ajuda.)
    m.resumeFrom = 0
    if m.reg.Exists("url") and m.reg.Read("url") = url and m.reg.Exists("pos")
        savedPos = int(val(m.reg.Read("pos")))
        if savedPos > 15 then m.resumeFrom = savedPos
    end if

    ' A Roku NAO detecta container sozinha em playback progressivo - passar o
    ' streamFormat errado da "malformed data" no pos=0 (ex.: "mp4" num Matroska
    ' real: o demuxer bate no header EBML e rejeita). Detecta pela extensao e,
    ' se o primeiro formato falhar de cara, tenta o outro.
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

    m.debugUrl.text = "[debug] fmt=" + fmt + " resume=" + str(m.resumeFrom).trim() + " (" + str(len(m.currentUrl)).trim() + " chars): " + m.currentUrl

    m.video.control = "stop"
    m.video.content = content
    m.video.visible = true
    m.video.control = "play"
    m.video.setFocus(true)

    m.hint.text = m.baseHint
end sub

function isHls(url as String) as Boolean
    return instr(1, lcase(url), ".m3u8") > 0
end function

' Confere a extensao do path ignorando querystring (?a=b) e fragmento (#x).
function hasExt(url as String, ext as String) as Boolean
    u = lcase(url)
    q = instr(1, u, "?")
    if q > 0 then u = left(u, q - 1)
    h = instr(1, u, "#")
    if h > 0 then u = left(u, h - 1)
    if len(u) < len(ext) then return false
    return right(u, len(ext)) = lcase(ext)
end function

sub onPosition()
    pos = m.video.position
    if pos <= 0 then return

    ' Detector de seek morto: o host ignora Range / MKV sem indice no comeco.
    if m.seekTarget >= 0
        if abs(pos - m.seekTarget) <= 3
            m.seekTarget = -1
            m.hint.text = m.baseHint
        else if m.seekTimer <> invalid and m.seekTimer.totalSeconds() > 6
            m.seekTarget = -1
            m.hint.text = "Este stream nao deixa avancar/retroceder (host ignora Range ou MKV sem indice). Use uma fonte HLS (.m3u8) ou debrid no Stremio."
        end if
    end if

    ' Salva posicao a cada ~5s pra permitir retomar depois.
    if pos - m.lastSavedPos < 5 and pos > m.lastSavedPos then return
    m.lastSavedPos = pos
    m.reg.Write("url", m.currentUrl)
    m.reg.Write("pos", str(pos).trim())
    m.reg.Flush()
    logAudioDiag()
end sub

sub clearResume()
    m.reg.Delete("url")
    m.reg.Delete("pos")
    m.reg.Flush()
    m.lastSavedPos = 0
end sub

' ---- DIAGNOSTICO DE AUDIO ----------------------------------------------------
' A Roku Express (modelo 3960, is-tv=false) NAO decodifica Dolby Digital/Digital
' Plus nem DTS: so repassa o bitstream por HDMI pra TV decodificar. Se a midia
' so tem faixa eac3/ac3/dts (sem AAC/estereo) e a TV nao decodifica, o video
' toca com imagem e SEM SOM nenhum. O canal nao tem API pra forcar downmix; so
' da pra (1) mostrar o formato/faixas na tela, (2) trocar pra uma faixa
' AAC/estereo SE existir (releases "dual audio"), (3) avisar em texto claro.
sub onAudioTracksChange()
    logAudioDiag()
    tryPickStereoTrack()
end sub

sub logAudioDiag()
    fmt = m.video.audioFormat
    if fmt = invalid then fmt = ""

    txt = "[audio] audioFormat='" + fmt + "'"

    tracks = m.video.availableAudioTracks
    if tracks = invalid or tracks.count() = 0
        txt = txt + "  faixas=(vazio - normal em MKV progressivo)"
    else
        txt = txt + "  faixas=" + str(tracks.count()).trim()
        i = 0
        for each t in tracks
            nm = ""
            if t <> invalid and t.name <> invalid then nm = t.name
            txt = txt + chr(10) + "[audio] track[" + str(i).trim() + "] " + nm
            i = i + 1
        end for
    end if

    noDecode = (fmt = "" or fmt = "eac3" or fmt = "ac3" or fmt = "dts" or fmt = "truehd" or fmt = "ac4" or fmt = "mat")
    if noDecode and m.video.state = "playing" and m.video.duration > 0
        txt = txt + chr(10) + "[audio] SEM SOM? Este aparelho pode nao decodificar Dolby/DTS. Use um release com faixa AAC ou AC3 estereo, coloque a saida de audio da TV em PCM, ou espelhe pelo celular (Miracast)."
    end if

    m.debugAudio.text = txt
end sub

' Sem campo de codec em availableAudioTracks (so name/language/track), da pra
' olhar so o name. Se algo cheira a AAC/estereo/2.0, troca a faixa. Nesta midia
' as 2 faixas sao eac3 -> nao acha nada, mas fica pronto pra "dual audio".
sub tryPickStereoTrack()
    tracks = m.video.availableAudioTracks
    if tracks = invalid or tracks.count() < 2 then return

    for each t in tracks
        if t <> invalid and t.name <> invalid and t.track <> invalid and t.track <> ""
            n = lcase(t.name)
            hit = (instr(1, n, "aac") > 0) or (instr(1, n, "stereo") > 0) or (instr(1, n, "2.0") > 0) or (instr(1, n, "2ch") > 0)
            if hit and t.track <> m.video.currentAudioTrack
                m.video.audioTrack = t.track
                m.status.text = "Trocando faixa de audio para: " + t.name
                return
            end if
        end if
    end for
end sub

sub onVideoStateChange()
    state = m.video.state

    ' DEBUG: historico curto das ultimas transicoes + errorCode/errorMsg (a Roku
    ' as vezes preenche o erro mesmo caindo direto pra "finished" com duracao 0).
    line = state + " (pos=" + str(m.video.position).trim() + " dur=" + str(m.video.duration).trim() + " fmt=" + m.currentFormat + ")"

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
        ' reassume o foco - sem isto o botao play/pause do controle nao chega
        ' no player e o usuario fica sem como pausar.
        m.video.setFocus(true)
        m.backArmed = false
        logAudioDiag()
        return
    end if

    ' Falha de carregamento: "error", ou "finished" sem nunca ter tido duracao.
    isLoadFailure = (state = "error") or (state = "finished" and m.video.duration = 0)

    if isLoadFailure
        if m.formatsToTry <> invalid and m.formatsToTry.count() > 0
            nextFmt = m.formatsToTry[0]
            m.status.text = "Formato '" + m.currentFormat + "' nao abriu, tentando '" + nextFmt + "'..."
            startNextAttempt()
            return
        end if
        m.status.text = "Nao consegui tocar este stream (formato/codec incompativel ou URL inacessivel pela Roku). Envie outro pelo celular."
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

' Teclas do controle durante o playback. Com enableTrickPlay=false, esta Scene e
' a unica a tratar transporte.
function onKeyEvent(key as String, press as Boolean) as Boolean
    if not press then return false
    if m.video.visible <> true then return false

    if key = "back"
        ' 1o VOLTAR: garante pausado e "arma" a saida. 2o VOLTAR: deixa sair.
        if m.backArmed
            clearResume()
            return false
        end if
        m.video.control = "pause"
        m.backArmed = true
        m.hint.text = "Pausado. OK para continuar. VOLTAR de novo para sair."
        return true
    end if

    ' So aceita transporte quando realmente esta tocando/pausado - evita o
    ' "aperto e nao acontece nada" enquanto um MKV grande ainda da buffering.
    active = (m.video.state = "playing" or m.video.state = "paused")

    if key = "play" or key = "OK"
        if not active then return true
        if m.video.control = "play"
            m.video.control = "pause"
            m.hint.text = "Pausado. OK para continuar."
        else
            m.video.control = "play"
            m.hint.text = m.baseHint
        end if
        m.backArmed = false
        return true
    else if key = "rewind" or key = "fastforward"
        if not active or m.video.duration <= 0
            m.hint.text = "Aguarde o video carregar para avancar/retroceder..."
            return true
        end if
        delta = 30
        if key = "rewind" then delta = -30
        target = m.video.position + delta
        if target < 0 then target = 0
        if target > m.video.duration - 5 then target = m.video.duration - 5
        m.seekTarget = target
        m.seekTimer = CreateObject("roTimespan")
        m.video.seek = target
        m.hint.text = "Buscando..."
        return true
    end if

    return false
end function
