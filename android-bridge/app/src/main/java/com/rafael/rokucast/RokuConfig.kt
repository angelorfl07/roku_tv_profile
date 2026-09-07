package com.rafael.rokucast

import android.content.Context
import android.content.SharedPreferences

/**
 * Config persistente do app (SharedPreferences). Guarda o IP da Roku entre
 * aberturas do APK para não perguntar de novo toda vez.
 *
 * O IP só é "esquecido"/redescoberto quando:
 *  - ele para de responder na porta de controle (Roku trocou de IP no DHCP,
 *    mudou de rede, ficou offline) — o app faz uma busca SSDP e salva o novo;
 *  - o usuário toca em "Esquecer IP" ou digita outro manualmente.
 */
class RokuConfig(context: Context) {

    private val prefs: SharedPreferences =
        context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)

    /** Último IP conhecido da Roku ("" se nunca foi salvo). */
    val rokuIp: String
        get() = prefs.getString(KEY_IP, "").orEmpty()

    /** true depois que um envio (ou um health check) confirmou que esse IP responde. */
    val verified: Boolean
        get() = prefs.getBoolean(KEY_VERIFIED, false)

    fun save(ip: String, verified: Boolean) {
        prefs.edit()
            .putString(KEY_IP, ip.trim())
            .putBoolean(KEY_VERIFIED, verified)
            .apply()
    }

    fun clear() {
        prefs.edit().remove(KEY_IP).remove(KEY_VERIFIED).apply()
    }

    companion object {
        private const val PREFS_NAME = "roku_cast_bridge"
        private const val KEY_IP = "roku_ip"
        private const val KEY_VERIFIED = "roku_ip_verified"
    }
}
