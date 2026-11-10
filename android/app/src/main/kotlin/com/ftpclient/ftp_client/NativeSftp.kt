package com.ftpclient.ftp_client

import android.os.Handler
import android.os.Looper
import com.jcraft.jsch.ChannelSftp
import com.jcraft.jsch.JSch
import com.jcraft.jsch.JSchException
import com.jcraft.jsch.Session
import com.jcraft.jsch.SftpProgressMonitor
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.util.concurrent.ConcurrentHashMap
import java.util.concurrent.Executors

/**
 * Native SFTP transfers via JSch.
 *
 * Streams between the socket and the file on a background thread using the
 * platform's (hardware-accelerated) JCE crypto, so large files don't pass
 * through the Dart heap. Progress is reported back over [channel].
 */
class NativeSftp(private val channel: MethodChannel) {
    private val executor = Executors.newCachedThreadPool()
    private val main = Handler(Looper.getMainLooper())
    private val cancelled = ConcurrentHashMap.newKeySet<Int>()
    private val sessions = ConcurrentHashMap<Int, Session>()

    fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "download" -> transfer(call, result, upload = false)
            "upload" -> transfer(call, result, upload = true)
            "cancel" -> {
                val id = call.argument<Int>("id")!!
                cancelled.add(id)
                // Unblock a transfer stuck in a socket read/write
                executor.execute { sessions[id]?.disconnect() }
                result.success(null)
            }
            else -> result.notImplemented()
        }
    }

    private fun transfer(call: MethodCall, result: MethodChannel.Result, upload: Boolean) {
        val id = call.argument<Int>("id")!!
        val remotePath = call.argument<String>("remotePath")!!
        val localPath = call.argument<String>("localPath")!!
        val resume = call.argument<Boolean>("resume") ?: false

        executor.execute {
            var session: Session? = null
            try {
                session = openSession(call)
                sessions[id] = session
                if (cancelled.contains(id)) throw InterruptedException()

                val sftp = session.openChannel("sftp") as ChannelSftp
                sftp.connect(CONNECT_TIMEOUT_MS)
                sftp.bulkRequests = BULK_REQUESTS

                val localFile = File(localPath)
                val total: Long
                var mode = ChannelSftp.OVERWRITE
                var transferred = 0L

                if (upload) {
                    total = localFile.length()
                } else {
                    total = sftp.stat(remotePath).size
                    val existing = if (resume && localFile.exists()) localFile.length() else 0L

                    // Partial file already complete: nothing to fetch
                    if (existing == total && total > 0) {
                        sftp.disconnect()
                        reportProgress(id, total, total)
                        main.post { result.success(total) }
                        return@execute
                    }

                    // Continue a partial file; anything larger than remote is stale
                    if (existing in 1 until total) {
                        mode = ChannelSftp.RESUME
                        transferred = existing
                    }
                }

                var lastReport = 0L
                val monitor = object : SftpProgressMonitor {
                    override fun init(op: Int, src: String?, dest: String?, max: Long) {}

                    override fun count(count: Long): Boolean {
                        transferred += count
                        val now = System.currentTimeMillis()
                        if (now - lastReport >= PROGRESS_INTERVAL_MS) {
                            lastReport = now
                            reportProgress(id, transferred, total)
                        }
                        return !cancelled.contains(id)
                    }

                    override fun end() {}
                }

                if (upload) {
                    sftp.put(localPath, remotePath, monitor, mode)
                } else {
                    localFile.parentFile?.mkdirs()
                    sftp.get(remotePath, localPath, monitor, mode)
                }
                sftp.disconnect()

                if (cancelled.contains(id)) throw InterruptedException()
                reportProgress(id, total, total)
                main.post { result.success(transferred) }
            } catch (e: Exception) {
                val isCancel = cancelled.contains(id)
                main.post {
                    if (isCancel) {
                        result.error("CANCELLED", "Cancelled", null)
                    } else {
                        result.error("SFTP_ERROR", e.message ?: e.toString(), null)
                    }
                }
            } finally {
                session?.disconnect()
                sessions.remove(id)
                cancelled.remove(id)
            }
        }
    }

    /** Connect, retrying when the server drops the handshake (MaxStartups etc.) */
    private fun openSession(call: MethodCall): Session {
        val host = call.argument<String>("host")!!
        val port = call.argument<Int>("port")!!
        val username = call.argument<String>("username")!!
        val password = call.argument<String>("password")
        val keyPath = call.argument<String>("keyPath")

        var attempt = 1
        while (true) {
            val jsch = JSch()
            if (!keyPath.isNullOrEmpty()) jsch.addIdentity(keyPath)

            val session = jsch.getSession(username, host, port)
            if (!password.isNullOrEmpty()) session.setPassword(password)
            session.setConfig("StrictHostKeyChecking", "no")
            session.setConfig("PreferredAuthentications", "publickey,password")
            // AES first: hardware accelerated on ARMv8 via JCE
            session.setConfig("cipher.s2c", CIPHERS)
            session.setConfig("cipher.c2s", CIPHERS)
            // Socket read timeout doubles as stall detection
            session.timeout = READ_TIMEOUT_MS

            try {
                session.connect(CONNECT_TIMEOUT_MS)
                return session
            } catch (e: JSchException) {
                session.disconnect()
                val authFailed = e.message?.contains("Auth fail") == true
                if (authFailed || attempt >= MAX_CONNECT_ATTEMPTS) throw e
                Thread.sleep(500L * attempt)
                attempt++
            }
        }
    }

    private fun reportProgress(id: Int, bytes: Long, total: Long) {
        main.post {
            channel.invokeMethod(
                "progress",
                mapOf("id" to id, "bytes" to bytes, "total" to total),
            )
        }
    }

    companion object {
        private const val CONNECT_TIMEOUT_MS = 30_000
        private const val READ_TIMEOUT_MS = 60_000
        private const val PROGRESS_INTERVAL_MS = 250L
        private const val BULK_REQUESTS = 64
        private const val MAX_CONNECT_ATTEMPTS = 3
        private const val CIPHERS =
            "aes128-gcm@openssh.com,aes128-ctr,aes256-gcm@openssh.com,aes256-ctr," +
                "aes192-ctr,chacha20-poly1305@openssh.com"
    }
}
