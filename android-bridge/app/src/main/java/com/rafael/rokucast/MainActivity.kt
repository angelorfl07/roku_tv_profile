package com.rafael.rokucast

import android.content.Intent
import android.os.Bundle
import android.widget.Button
import android.widget.EditText
import android.widget.TextView
import androidx.appcompat.app.AppCompatActivity
import java.util.concurrent.Executors

class MainActivity : AppCompatActivity() {

    private lateinit var config: RokuConfig
    private lateinit var editRokuIp: EditText
    private lateinit var editStreamUrl: EditText
    private lateinit var editTitle: EditText
    private lateinit var textStatus: TextView

    private val executor = Executors.newSingleThreadExecutor()

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        setContentView(R.layout.activity_main)

        config = RokuConfig(this)

        editRokuIp = findViewById(R.id.editRokuIp)
        editStreamUrl = findViewById(R.id.editStreamUrl)
        editTitle = findViewById(R.id.editTitle)
        textStatus = findViewById(R.id.textStatus)

        editRokuIp.setText(config.rokuIp)

        findViewById<Button>(R.id.btnDiscover).setOnClickListener { discoverRoku() }
        findViewById<Button>(R.id.btnForget).setOnClickListener { forgetRoku() }
        findViewById<Button>(R.id.btnSend).setOnClickListener { onSendClicked() }

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

        if (url.isNullOrBlank()) {
            // Abertura normal do app: revalida o IP salvo em background e,
            // se ele não responder mais, procura a Roku na rede sozinho.
            ensureRokuReady(autoSend = false)
            return
        }

        editStreamUrl.setText(url)

        // "title" é o extra usado pela convenção informal de player externo
        // (mesma que o MX Player popularizou); EXTRA_SUBJECT cobre o caso
        // de "compartilhar" ao invés de "abrir com".
        val title = intent.getStringExtra("title")
            ?: intent.getStringExtra(Intent.EXTRA_SUBJECT)
        if (!title.isNullOrBlank()) editTitle.setText(title)

        // Fluxo automático: resolve o IP (salvo, ou redescobre) e já envia.
        ensureRokuReady(autoSend = true)
    }

    /**
     * Garante um IP de Roku que responde, sem incomodar o usuário:
     *  1. usa o IP salvo/digitado se ele ainda responder na porta ECP (8060);
     *  2. senão, faz uma busca SSDP na rede e salva o que encontrar;
     *  3. só pede ação manual se as duas coisas falharem.
     *
     * Com [autoSend] = true, dispara o envio do stream assim que o IP resolver.
     */
    private fun ensureRokuReady(autoSend: Boolean) {
        val candidate = editRokuIp.text.toString().trim().ifBlank { config.rokuIp }

        textStatus.text = when {
            candidate.isNotBlank() -> "Falando com a Roku em $candidate..."
            else -> "Procurando a Roku na rede..."
        }

        executor.execute {
            val net = LocalNetwork.of(this)

            // 1. IP salvo/digitado que já responde ao health check → caminho feliz.
            var ip: String? = candidate.takeIf {
                it.isNotBlank() && RokuSender.reachable(net, it)
            }
            var verified = ip != null

            // 2. senão, busca SSDP na rede.
            if (ip == null) {
                runOnUiThread {
                    textStatus.text = if (candidate.isBlank())
                        "Procurando a Roku na rede..."
                    else
                        "O IP $candidate não respondeu ao teste. Procurando a Roku na rede..."
                }
                val found = SsdpDiscovery.discoverFirstRoku(net)?.takeIf { it.isNotBlank() }
                if (found != null) {
                    ip = found
                    verified = RokuSender.reachable(net, found)
                }
            }

            // 3. último recurso: nada respondeu ao health check, mas temos um
            //    palpite (IP salvo/digitado) — tenta com ele mesmo assim; quem
            //    dá o veredito final é o POST do ECP, não o health check (que
            //    pode ser falso-negativo dependendo da config da Roku).
            if (ip == null && candidate.isNotBlank()) {
                ip = candidate
                verified = false
            }

            val resolvedIp = ip
            val isVerified = verified

            runOnUiThread {
                if (resolvedIp == null) {
                    textStatus.text = "Não achei a Roku. Confira se ela está ligada e no mesmo " +
                        "Wi-Fi do celular (não numa rede de convidados), depois toque em " +
                        "\"Detectar Roku na rede\" ou digite o IP manualmente."
                    return@runOnUiThread
                }

                config.save(resolvedIp, verified = isVerified)
                editRokuIp.setText(resolvedIp)

                when {
                    autoSend -> sendToRoku(resolvedIp)
                    isVerified -> textStatus.text =
                        "Roku pronta em $resolvedIp. É só mandar o stream pelo Stremio."
                    else -> textStatus.text = "Roku em $resolvedIp encontrada, mas ela não " +
                        "respondeu ao teste na porta 8060 — vou tentar assim mesmo quando você " +
                        "mandar um stream. Se falhar, veja \"Controle por rede\" na Roku."
                }
            }
        }
    }

    private fun onSendClicked() {
        val url = editStreamUrl.text.toString().trim()
        if (url.isBlank()) {
            textStatus.text = "Informe a URL do stream."
            return
        }
        val typed = editRokuIp.text.toString().trim()
        if (typed.isNotBlank()) {
            sendToRoku(typed)
        } else {
            ensureRokuReady(autoSend = true)
        }
    }

    private fun discoverRoku() {
        textStatus.text = "Procurando Roku na rede..."
        executor.execute {
            val net = LocalNetwork.of(this)
            val ip = SsdpDiscovery.discoverFirstRoku(net)?.takeIf { it.isNotBlank() }
            val reachable = ip != null && RokuSender.reachable(net, ip)
            runOnUiThread {
                if (ip == null) {
                    textStatus.text = "Nenhuma Roku respondeu. Informe o IP manualmente " +
                        "(na Roku: Configurações > Rede > Sobre)."
                    return@runOnUiThread
                }
                editRokuIp.setText(ip)
                config.save(ip, verified = reachable)
                textStatus.text = if (reachable) {
                    "Roku encontrada e salva: $ip"
                } else {
                    "Roku encontrada e salva: $ip (não respondeu ao teste na porta 8060, mas " +
                        "vou tentar mesmo assim ao enviar; se falhar, veja \"Controle por rede\" na Roku)."
                }
            }
        }
    }

    private fun forgetRoku() {
        config.clear()
        editRokuIp.setText("")
        textStatus.text = "IP salvo apagado. Toque em \"Detectar Roku na rede\" ou digite um IP."
    }

    private fun sendToRoku(ip: String) {
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

        textStatus.text = "Enviando para a Roku ($ip)..."

        executor.execute {
            val net = LocalNetwork.of(this)
            val result = RokuSender.send(net, ip, url, title)
            runOnUiThread {
                when (result) {
                    is RokuSender.Result.Success -> {
                        config.save(ip, verified = true)
                        textStatus.text = if (result.viaInput)
                            "Enviado (canal já estava aberto)."
                        else
                            "Canal lançado na Roku com o stream."
                    }
                    is RokuSender.Result.Failure -> {
                        textStatus.text = result.message
                    }
                }
            }
        }
    }
}
