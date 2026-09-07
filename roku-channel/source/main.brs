' Stremio Cast Receiver — ponto de entrada do canal
' Recebe a URL do stream via deep link (ECP /launch/dev) ou via roInput (ECP /input)
' enquanto o canal já está em primeiro plano, e manda tocar no Video node da MainScene.

sub Main(args as Dynamic) as Void
    screen = CreateObject("roSGScreen")
    m.port = CreateObject("roMessagePort")
    screen.setMessagePort(m.port)

    ' necessário para receber eventos de /input sem precisar relançar o canal
    m.rokuInput = CreateObject("roInput")
    m.rokuInput.setMessagePort(m.port)

    scene = screen.CreateScene("MainScene")
    screen.show()

    handleArgs(scene, args)

    while true
        msg = wait(0, m.port)
        msgType = type(msg)

        if msgType = "roSGScreenEvent"
            if msg.isScreenClosed()
                return
            end if
        else if msgType = "roInputEvent"
            handleArgs(scene, msg.getInfo())
        end if
    end while
end sub

' args chega tanto do launch (deep link) quanto do roInput (mesmo formato de associative array)
sub handleArgs(scene as Object, args as Dynamic)
    if args = invalid then return

    url = getFirst(args, ["stremiourl", "url", "contentid"])
    title = getFirst(args, ["stremiotitle", "title"])

    if url <> invalid and url <> ""
        scene.stremioTitle = decodeUri(title)
        scene.stremioUrl = decodeUri(url)
    end if
end sub

' procura a primeira chave existente (case-insensitive) entre uma lista de aliases
function getFirst(aa as Object, keys as Object) as Dynamic
    if aa = invalid then return invalid
    for each k in keys
        for each realKey in aa.keys()
            if lcase(realKey) = lcase(k)
                val = aa[realKey]
                if val <> invalid and val <> ""
                    return val
                end if
            end if
        end for
    end for
    return invalid
end function

function decodeUri(s as Dynamic) as String
    if s = invalid then return ""
    xfer = createObject("roUrlTransfer")
    return xfer.unescape(s)
end function
