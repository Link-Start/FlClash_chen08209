package com.follow.clash

import android.content.Intent
import com.follow.clash.common.GlobalState
import com.follow.clash.common.ServiceDelegate
import com.follow.clash.common.intent
import com.follow.clash.core.Core
import com.follow.clash.service.CommonService
import com.follow.clash.service.IBaseService
import com.follow.clash.service.State
import com.follow.clash.service.VpnService
import com.follow.clash.service.models.NotificationParams
import com.follow.clash.service.models.VpnOptions
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock

object Service {
    private val runLock = Mutex()
    private var delegate: ServiceDelegate<IBaseService>? = null
    private var intent: Intent? = null
    private var runTime: Long = 0L

    var onServiceDisconnected: ((String) -> Unit)? = null

    fun unbind() {
        delegate?.unbind()
        delegate = null
        intent = null
    }

    suspend fun invokeAction(data: String, cb: ((result: String) -> Unit)?): Result<Unit> {
        return runCatching {
            Core.invokeAction(data) { result ->
                cb?.invoke(result.orEmpty())
            }
        }
    }

    suspend fun quickSetup(
        initParamsString: String,
        setupParamsString: String,
        onStarted: (() -> Unit)?,
        onResult: ((result: String) -> Unit)?,
    ): Result<Unit> {
        return runCatching {
            Core.quickSetup(initParamsString, setupParamsString) { result ->
                onResult?.invoke(result.orEmpty())
            }
            onStarted?.invoke()
        }
    }

    suspend fun setEventListener(cb: ((result: String?) -> Unit)?): Result<Unit> {
        return runCatching {
            Core.callSetEventListener(cb)
        }
    }

    suspend fun updateNotificationParams(params: NotificationParams): Result<Unit> {
        State.notificationParamsFlow.emit(params)
        return Result.success(Unit)
    }

    suspend fun setCrashlytics(enable: Boolean): Result<Unit> {
        GlobalState.setCrashlytics(enable)
        return Result.success(Unit)
    }

    suspend fun startService(options: VpnOptions, previousRunTime: Long): Long {
        return runLock.withLock {
            State.options = options
            val nextIntent = when (options.enable) {
                true -> VpnService::class.intent
                false -> CommonService::class.intent
            }
            if (intent != nextIntent) {
                unbind()
                delegate = ServiceDelegate(nextIntent, ::handleServiceDisconnected) { binder ->
                    when (binder) {
                        is VpnService.LocalBinder -> binder.getService()
                        is CommonService.LocalBinder -> binder.getService()
                        else -> throw IllegalArgumentException("Invalid binder type")
                    }
                }
                intent = nextIntent
                delegate?.bind()
            }
            val result = delegate?.useService { service ->
                service.start()
            } ?: return@withLock 0L
            if (result.isFailure) {
                return@withLock 0L
            }
            runTime = previousRunTime.takeIf { it != 0L } ?: System.currentTimeMillis()
            runTime
        }
    }

    suspend fun stopService(): Long {
        return runLock.withLock {
            delegate?.useService { service ->
                service.stop()
            }
            unbind()
            runTime = 0L
            runTime
        }
    }

    suspend fun getRunTime(): Long = runTime

    private fun handleServiceDisconnected(message: String) {
        GlobalState.log("Background service disconnected: $message")
        unbind()
        runTime = 0L
        onServiceDisconnected?.invoke(message)
    }
}
