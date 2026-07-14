package com.follow.clash

import android.content.Intent
import com.follow.clash.common.GlobalState
import com.follow.clash.common.ServiceDelegate
import com.follow.clash.common.intent
import com.follow.clash.core.Core
import com.follow.clash.service.ManagedService
import com.follow.clash.service.ProxyService
import com.follow.clash.service.ServiceConfig
import com.follow.clash.service.VpnService
import com.follow.clash.service.models.NotificationParams
import com.follow.clash.service.models.VpnOptions
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock

object ServiceController {
    private val lock = Mutex()
    private var delegate: ServiceDelegate<ManagedService>? = null
    private var boundIntent: Intent? = null
    @Volatile
    private var runTimeMillis = 0L
    @Volatile
    private var serviceDisconnectedListener: ((String) -> Unit)? = null

    fun setServiceDisconnectedListener(listener: ((String) -> Unit)?) {
        serviceDisconnectedListener = listener
    }

    fun unbind() {
        delegate?.unbind()
        delegate = null
        boundIntent = null
    }

    fun invokeAction(data: String, callback: ((String) -> Unit)?): Result<Unit> = runCatching {
        Core.invokeAction(data) { result ->
            callback?.invoke(result.orEmpty())
        }
    }

    fun quickSetup(
        initParams: String,
        setupParams: String,
        onStarted: (() -> Unit)?,
        onResult: ((String) -> Unit)?,
    ): Result<Unit> = runCatching {
        Core.quickSetup(initParams, setupParams) { result ->
            onResult?.invoke(result.orEmpty())
        }
        onStarted?.invoke()
    }

    fun setEventListener(callback: ((String?) -> Unit)?): Result<Unit> = runCatching {
        Core.updateEventListener(callback)
    }

    fun updateNotification(params: NotificationParams) {
        ServiceConfig.updateNotificationParams(params)
    }

    suspend fun start(options: VpnOptions, previousRunTimeMillis: Long): Long = lock.withLock {
        ServiceConfig.updateVpnOptions(options)
        val nextIntent = if (options.enable) {
            VpnService::class.intent
        } else {
            ProxyService::class.intent
        }

        if (boundIntent?.component != nextIntent.component) {
            unbind()
            delegate = ServiceDelegate(nextIntent, ::handleServiceDisconnected) { binder ->
                when (binder) {
                    is VpnService.LocalBinder -> binder.service
                    is ProxyService.LocalBinder -> binder.service
                    else -> error("Unsupported service binder: ${binder.javaClass.name}")
                }
            }
            boundIntent = nextIntent
            delegate?.bind()
        }

        val result = delegate?.useService { service -> service.start() }
            ?: return@withLock 0L
        if (result.isFailure) {
            GlobalState.log("Unable to start background service: ${result.exceptionOrNull()}")
            unbind()
            return@withLock 0L
        }

        runTimeMillis = previousRunTimeMillis.takeIf { it != 0L }
            ?: System.currentTimeMillis()
        runTimeMillis
    }

    suspend fun stop(): Long = lock.withLock {
        delegate?.useService { service -> service.stop() }
            ?.onFailure { error ->
                GlobalState.log("Unable to stop background service: $error")
            }
        unbind()
        runTimeMillis = 0L
        runTimeMillis
    }

    fun getRunTimeMillis(): Long = runTimeMillis

    private fun handleServiceDisconnected(message: String) {
        GlobalState.log("Background service disconnected: $message")
        unbind()
        runTimeMillis = 0L
        serviceDisconnectedListener?.invoke(message)
    }
}
