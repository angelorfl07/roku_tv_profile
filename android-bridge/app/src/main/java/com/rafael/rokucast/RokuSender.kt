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
 * Todas as chamadas tentam primeiro pela [Network] informada (Wi-Fi/Ethernet,
 * ignorando dados móveis) e, se a chamada nem completar, repetem pela rota
 * padrão do sistema — o navegador do celular usa a rota padrão e funciona,
 * então ela serve de rede de segurança.
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
     * tenha ou não o canal instalado.
     */
    fun reachable(network: Network?, rokuIp: String): Boolean {
        if (rokuIp.isBlank()) return false
        return getBody(network, "http://$rokuIp:8060/query/device-info", PING_TIMEOUT_MS) != null
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

        // Diagnóstico: a Roku responde? o canal "dev" está instalado?
        val apps = getBody(network, "http://$rokuIp:8060/query/apps", PING_TIMEOUT_MS)
        val message = when {
            apps == null ->
                "Não consegui falar com a Roku em $rokuIp:8060. Confira se o celular está no " +
                    "mesmo Wi-Fi (não só no 4G/5G). (input=$inputStatus, launch=$launchStatus)"
            !apps.contains("id=\"$CHANNEL_ID\"") ->
                "A Roku respondeu, mas o canal \"Stremio Cast Receiver\" NÃO está instalado nela. " +
                    "Faça o sideload: abra http://$rokuIp no navegador (usuário rokudev), aba " +
                    "\"Upload\", e instale o stremio-cast-receiver.zip."
            else ->
                "O canal está instalado, mas recusou o comando (input=$inputStatus, launch=$launchStatus). " +
                    "Abra o canal \"Stremio Cast Receiver\" na Roku uma vez e tente de novo."
        }
        return Result.Failure(message)
    }

    /** POST sem corpo; tenta pela [network] e, se falhar de vez, pela rota padrão. */
    private fun post(network: Network?, urlStr: String): Int {
        val viaNetwork = rawPost(network, urlStr)
        if (viaNetwork != -1 || network == null) return viaNetwork
        return rawPost(null, urlStr)
    }

    private fun rawPost(network: Network?, urlStr: String): Int {
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

    /** GET; devolve o corpo como String, ou null se a chamada não completar (200). */
    private fun getBody(network: Network?, urlStr: String, timeoutMs: Int): String? {
        val viaNetwork = rawGet(network, urlStr, timeoutMs)
        if (viaNetwork != null || network == null) return viaNetwork
        return rawGet(null, urlStr, timeoutMs)
    }

    private fun rawGet(network: Network?, urlStr: String, timeoutMs: Int): String? {
        return try {
            val conn = open(network, urlStr)
            conn.requestMethod = "GET"
            conn.connectTimeout = timeoutMs
            conn.readTimeout = timeoutMs
            val code = conn.responseCode
            val body = if (code == 200) conn.inputStream.bufferedReader().use { it.readText() } else null
            conn.disconnect()
            if (code == 200) body else null
        } catch (e: Exception) {
            null
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
