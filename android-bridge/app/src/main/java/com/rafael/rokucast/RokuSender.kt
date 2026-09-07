package com.rafael.rokucast

import android.net.Network
import java.net.HttpURLConnection
import java.net.URL
import java.net.URLEncoder

/**
 * Fala com o canal "Stremio Cast Receiver" sideloaded na Roku via ECP
 * (External Control Protocol), na porta 8060.
 *
 * Tenta primeiro /input (canal já em primeiro plano, sem relançar / sem piscar
 * a tela) e cai para /launch/dev caso o canal ainda não esteja rodando.
 *
 * Todas as chamadas aceitam um [Network] opcional — quando informado, o socket
 * é aberto por essa rede (Wi-Fi/Ethernet), ignorando dados móveis.
 */
object RokuSender {

    private const val CHANNEL_ID = "dev"
    private const val TIMEOUT_MS = 4000
    private const val PING_TIMEOUT_MS = 2500

    sealed class Result {
        data class Success(val viaInput: Boolean) : Result()
        data class Failure(val message: String) : Result()
    }

    /**
     * Health check leve: GET /query/device-info. Qualquer Roku responde 200,
     * tenha ou não o canal instalado — serve para saber se o IP ainda é de
     * uma Roku alcançável antes de confiar nele.
     */
    fun reachable(network: Network?, rokuIp: String): Boolean {
        if (rokuIp.isBlank()) return false
        return try {
            val conn = open(network, "http://$rokuIp:8060/query/device-info")
            conn.requestMethod = "GET"
            conn.connectTimeout = PING_TIMEOUT_MS
            conn.readTimeout = PING_TIMEOUT_MS
            val code = conn.responseCode
            conn.disconnect()
            code == 200
        } catch (e: Exception) {
            false
        }
    }

    fun send(network: Network?, rokuIp: String, streamUrl: String, title: String): Result {
        val encUrl = enc(streamUrl)
        val encTitle = enc(title.ifBlank { "Stremio" })
        val query = "stremioUrl=$encUrl&stremioTitle=$encTitle"

        val inputStatus = post(network, "http://$rokuIp:8060/input?$query")
        if (inputStatus == 200) {
            return Result.Success(viaInput = true)
        }

        val launchStatus = post(network, "http://$rokuIp:8060/launch/$CHANNEL_ID?$query")
        if (launchStatus == 200) {
            return Result.Success(viaInput = false)
        }

        val message = if (reachable(network, rokuIp)) {
            "A Roku em $rokuIp respondeu, mas o canal \"Stremio Cast Receiver\" não " +
                "está instalado. Faça o sideload pelo Developer Mode. " +
                "(input=$inputStatus, launch=$launchStatus)"
        } else {
            "Não consegui falar com a Roku em $rokuIp:8060. Confira se o celular " +
                "está no mesmo Wi-Fi (não só no 4G/5G) e se \"Controle por rede\" está " +
                "ativo na Roku (Configurações > Sistema > Controle externo). " +
                "(input=$inputStatus, launch=$launchStatus)"
        }
        return Result.Failure(message)
    }

    private fun post(network: Network?, urlStr: String): Int {
        return try {
            val conn = open(network, urlStr)
            conn.requestMethod = "POST"
            conn.connectTimeout = TIMEOUT_MS
            conn.readTimeout = TIMEOUT_MS
            conn.doOutput = true
            conn.setFixedLengthStreamingMode(0)
            conn.connect()
            conn.outputStream.close()
            val code = conn.responseCode
            conn.disconnect()
            code
        } catch (e: Exception) {
            -1
        }
    }

    /** Abre a conexão pela [network] informada (Wi-Fi), ou pela rota padrão se null. */
    private fun open(network: Network?, urlStr: String): HttpURLConnection {
        val url = URL(urlStr)
        val conn = network?.openConnection(url) ?: url.openConnection()
        return conn as HttpURLConnection
    }

    private fun enc(s: String): String = URLEncoder.encode(s, "UTF-8")
}
