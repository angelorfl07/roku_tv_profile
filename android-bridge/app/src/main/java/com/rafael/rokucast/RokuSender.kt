package com.rafael.rokucast

import java.net.HttpURLConnection
import java.net.URL
import java.net.URLEncoder

/**
 * Fala com o canal "Stremio Cast Receiver" sideloaded na Roku via ECP
 * (External Control Protocol), na porta 8060.
 *
 * Tenta primeiro /input (canal já em primeiro plano, sem relançar / sem piscar
 * a tela) e cai para /launch/dev caso o canal ainda não esteja rodando.
 */
object RokuSender {

    private const val CHANNEL_ID = "dev"
    private const val TIMEOUT_MS = 4000

    sealed class Result {
        data class Success(val viaInput: Boolean) : Result()
        data class Failure(val message: String) : Result()
    }

    fun send(rokuIp: String, streamUrl: String, title: String): Result {
        val encUrl = enc(streamUrl)
        val encTitle = enc(title.ifBlank { "Stremio" })
        val query = "stremioUrl=$encUrl&stremioTitle=$encTitle"

        val inputStatus = post("http://$rokuIp:8060/input?$query")
        if (inputStatus == 200) {
            return Result.Success(viaInput = true)
        }

        val launchStatus = post("http://$rokuIp:8060/launch/$CHANNEL_ID?$query")
        return if (launchStatus == 200) {
            Result.Success(viaInput = false)
        } else {
            Result.Failure("Falha ao falar com a Roku (input=$inputStatus, launch=$launchStatus). Confira o IP e se o canal foi sideloaded.")
        }
    }

    private fun post(urlStr: String): Int {
        return try {
            val conn = URL(urlStr).openConnection() as HttpURLConnection
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

    private fun enc(s: String): String = URLEncoder.encode(s, "UTF-8")
}
