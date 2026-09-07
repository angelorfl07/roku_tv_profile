package com.rafael.rokucast

import android.content.Intent
import android.content.SharedPreferences
import android.os.Bundle
import android.widget.Button
import android.widget.EditText
import android.widget.TextView
import androidx.appcompat.app.AppCompatActivity
import java.util.concurrent.Executors

class MainActivity : AppCompatActivity() {

    private lateinit var prefs: SharedPreferences
    private lateinit var editRokuIp: EditText
    private lateinit var editStreamUrl: EditText
    private lateinit var editTitle: EditText
    private lateinit var textStatus: TextView

    private val executor = Executors.newSingleThreadExecutor()

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        setContentView(R.layout.activity_main)

        prefs = getSharedPreferences("roku_cast_bridge", MODE_PRIVATE)

        editRokuIp = findViewById(R.id.editRokuIp)
        editStreamUrl = findViewById(R.id.editStreamUrl)
        editTitle = findViewById(R.id.editTitle)
        textStatus = findViewById(R.id.textStatus)

        editRokuIp.setText(prefs.getString("roku_ip", ""))

        findViewById<Button>(R.id.btnDiscover).setOnClickListener { discoverRoku() }
        findViewById<Button>(R.id.btnSend).setOnClickListener { sendToRoku() }

        handleIncomingIntent(intent)
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        handleIncomingIntent(intent)
    }

    /** Extrai a URL do stream quando o app é aberto via "Compartilhar" ou
     *  como "player externo" a partir do Stremio (ou de outro app). */
    private fun handleIncomingIntent(intent: Intent) {
        val url = when (intent.action) {
            Intent.ACTION_SEND -> intent.getStringExtra(Intent.EXTRA_TEXT)
            Intent.ACTION_VIEW -> intent.data?.toString()
            else -> null
        }

        if (!url.isNullOrBlank()) {
            editStreamUrl.setText(url)
            val subject = intent.getStringExtra(Intent.EXTRA_SUBJECT)
            if (!subject.isNullOrBlank()) editTitle.setText(subject)

            // se já tiver um IP de Roku salvo, envia direto — só pede confirmação
            // manual quando falta configurar o IP.
            val savedIp = prefs.getString("roku_ip", "")
            if (!savedIp.isNullOrBlank()) {
                sendToRoku()
            } else {
                textStatus.text = "Stream recebido. Informe o IP da Roku e toque em Enviar."
            }
        }
    }

    private fun discoverRoku() {
        textStatus.text = "Procurando Roku na rede..."
        executor.execute {
            val ip = SsdpDiscovery.discoverFirstRoku()
            runOnUiThread {
                if (ip != null) {
                    editRokuIp.setText(ip)
                    textStatus.text = "Roku encontrada: $ip"
                } else {
                    textStatus.text = "Nenhuma Roku respondeu. Informe o IP manualmente " +
                        "(Configurações > Rede > Sobre, na Roku)."
                }
            }
        }
    }

    private fun sendToRoku() {
        val ip = editRokuIp.text.toString().trim()
        val url = editStreamUrl.text.toString().trim()
        val title = editTitle.text.toString().trim()

        if (ip.isBlank()) {
            textStatus.text = "Informe o IP da Roku primeiro."
            return
        }
        if (url.isBlank()) {
            textStatus.text = "Informe a URL do stream."
            return
        }

        prefs.edit().putString("roku_ip", ip).apply()
        textStatus.text = "Enviando para a Roku..."

        executor.execute {
            val result = RokuSender.send(ip, url, title)
            runOnUiThread {
                textStatus.text = when (result) {
                    is RokuSender.Result.Success ->
                        if (result.viaInput) "Enviado (canal já estava aberto)."
                        else "Canal lançado na Roku com o stream."
                    is RokuSender.Result.Failure -> result.message
                }
            }
        }
    }
}
