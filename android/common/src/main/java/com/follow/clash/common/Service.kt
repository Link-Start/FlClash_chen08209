package com.follow.clash.common

import android.content.Intent
import android.os.IBinder
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.filterNotNull
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import kotlinx.coroutines.withTimeout

class ServiceDelegate<T>(
    private val intent: Intent,
    private val onServiceDisconnected: ((String) -> Unit)? = null,
    private val interfaceCreator: (IBinder) -> T,
) {
    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.Default)
    private val serviceState = MutableStateFlow<Result<T>?>(null)
    private var isBinding = false
    private var job: Job? = null

    private fun handleBind(data: Pair<IBinder?, String>) {
        val binder = data.first
        if (binder == null) {
            disconnect(data.second)
            return
        }
        runCatching { interfaceCreator(binder) }
            .onSuccess { service -> serviceState.value = Result.success(service) }
            .onFailure { error -> disconnect(error.message.orEmpty()) }
    }

    @Synchronized
    private fun disconnect(message: String) {
        isBinding = false
        job?.cancel()
        job = null
        serviceState.value = Result.failure(IllegalStateException(message))
        onServiceDisconnected?.invoke(message)
    }

    @Synchronized
    fun bind() {
        if (isBinding) return
        isBinding = true
        job?.cancel()
        serviceState.value = null
        job = scope.launch {
            runCatching {
                GlobalState.application.bindServiceFlow(intent)
                    .collect { handleBind(it) }
            }.onFailure { error ->
                if (error !is CancellationException) {
                    disconnect(error.message.orEmpty())
                }
            }
        }
    }

    suspend fun <R> useService(
        timeoutMillis: Long = 5_000,
        block: suspend (T) -> R,
    ): Result<R> = runCatching {
        withTimeout(timeoutMillis) {
            val service = serviceState.filterNotNull().first().getOrThrow()
            withContext(Dispatchers.Default) {
                block(service)
            }
        }
    }

    @Synchronized
    fun unbind() {
        if (!isBinding) return
        isBinding = false
        job?.cancel()
        job = null
        serviceState.value = null
    }
}
