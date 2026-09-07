sub init()
    m.top.setFocus(true)

    m.video = m.top.findNode("videoPlayer")
    m.status = m.top.findNode("statusLabel")

    m.video.enableTrickPlay = true
    m.video.notificationInterval = 1
    m.video.observeField("state", "onVideoStateChange")
end sub

' disparado automaticamente quando main.brs seta scene.stremioUrl
sub onNewUrl()
    url = m.top.stremioUrl
    if url <> ""
        playUrl(url, m.top.stremioTitle)
    end if
end sub

sub playUrl(url as String, title as String)
    m.status.visible = false

    content = createObject("roSGNode", "ContentNode")
    content.url = url
    content.title = title

    ' "hls" para links .m3u8 (comum com resolvers/debrid), "mp4" cobre mp4/mkv na maioria
    ' dos modelos Roku. Se o stream não tocar, o formato costuma ser a primeira coisa a
    ' checar (ver observações de compatibilidade no CLAUDE.md do projeto).
    if isHls(url)
        content.streamFormat = "hls"
    else
        content.streamFormat = "mp4"
    end if

    m.video.content = content
    m.video.visible = true
    m.video.control = "play"
    m.video.setFocus(true)
end sub

function isHls(url as String) as Boolean
    return instr(1, lcase(url), ".m3u8") > 0
end function

sub onVideoStateChange()
    state = m.video.state

    if state = "finished" or state = "error"
        errMsg = ""
        if state = "error"
            errMsg = " Verifique se o formato do stream é compatível com a Roku."
        end if
        m.status.text = "Playback encerrado." + errMsg + " Envie outro stream pelo celular."
        m.status.visible = true
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
