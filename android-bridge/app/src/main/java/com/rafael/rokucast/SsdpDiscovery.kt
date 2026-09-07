package com.rafael.rokucast

import android.net.Network
import java.net.DatagramPacket
import java.net.DatagramSocket
import java.net.InetAddress

/**
 * Descoberta best-effort de Rokus na rede local via SSDP (M-SEARCH),
 * procurando pelo serviço "roku:ecp". Roda em thread de background —
 * chame a partir de uma coroutine/executor, nunca na main thread.
 */
object SsdpDiscovery {

    private const val SSDP_ADDRESS = "239.255.255.250"
    private const val SSDP_PORT = 1900
    private const val SEARCH_TARGET = "roku:ecp"

    /**
     * Retorna o IP da primeira Roku encontrada, ou null se nenhuma responder
     * a tempo. Se [network] for informada, o socket é preso a ela (Wi-Fi) para
     * o M-SEARCH não sair pela rede móvel.
     */
    fun discoverFirstRoku(network: Network? = null, timeoutMs: Int = 3000): String? {
        val socket = DatagramSocket()
        try {
            try {
                network?.bindSocket(socket)
            } catch (e: Exception) {
                // segue sem bind — melhor tentar pela rota padrão do que desistir
            }
            socket.soTimeout = timeoutMs

            val message = "M-SEARCH * HTTP/1.1\r\n" +
                "HOST: $SSDP_ADDRESS:$SSDP_PORT\r\n" +
                "MAN: \"ssdp:discover\"\r\n" +
                "MX: 2\r\n" +
                "ST: $SEARCH_TARGET\r\n\r\n"

            val data = message.toByteArray()
            val address = InetAddress.getByName(SSDP_ADDRESS)
            val packet = DatagramPacket(data, data.size, address, SSDP_PORT)
            socket.send(packet)

            val buf = ByteArray(2048)
            val response = DatagramPacket(buf, buf.size)
            socket.receive(response)

            return response.address.hostAddress
        } catch (e: Exception) {
            return null
        } finally {
            socket.close()
        }
    }
}
