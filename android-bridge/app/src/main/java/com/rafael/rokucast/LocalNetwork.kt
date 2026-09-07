package com.rafael.rokucast

import android.content.Context
import android.net.ConnectivityManager
import android.net.Network
import android.net.NetworkCapabilities

/**
 * Devolve a rede local (Wi-Fi ou Ethernet) para forçar as chamadas à Roku
 * por ela.
 *
 * Sem isto, com dados móveis (4G/5G) ligados o Android pode rotear o socket
 * pela operadora — principalmente quando o Wi-Fi está "sem internet" — e a
 * Roku, que só existe na rede local, fica inalcançável (foi exatamente o
 * `input=-1, launch=-1` visto em teste: conexão TCP nunca completou).
 */
object LocalNetwork {

    /** A primeira rede Wi-Fi/Ethernet disponível, ou null se só houver rede móvel. */
    fun of(context: Context): Network? {
        val cm = context.applicationContext
            .getSystemService(Context.CONNECTIVITY_SERVICE) as? ConnectivityManager
            ?: return null

        return cm.allNetworks.firstOrNull { network ->
            val caps = cm.getNetworkCapabilities(network) ?: return@firstOrNull false
            val local = caps.hasTransport(NetworkCapabilities.TRANSPORT_WIFI) ||
                caps.hasTransport(NetworkCapabilities.TRANSPORT_ETHERNET)
            local && caps.hasCapability(NetworkCapabilities.NET_CAPABILITY_INTERNET)
        } ?: cm.allNetworks.firstOrNull { network ->
            // Fallback: Wi-Fi sem flag de internet (rede "sem internet") ainda
            // serve para falar com a Roku na LAN.
            val caps = cm.getNetworkCapabilities(network) ?: return@firstOrNull false
            caps.hasTransport(NetworkCapabilities.TRANSPORT_WIFI) ||
                caps.hasTransport(NetworkCapabilities.TRANSPORT_ETHERNET)
        }
    }
}
