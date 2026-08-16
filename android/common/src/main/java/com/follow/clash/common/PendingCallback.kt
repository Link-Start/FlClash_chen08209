package com.follow.clash.common

/**
 * A single-slot callback holder for request/response hops that leave the process
 * and come back through an Android callback, such as a permission prompt or the
 * VPN consent dialog.
 *
 * Only the newest request is ever pending: [replace] settles the request it
 * supersedes rather than dropping it, so no caller is left waiting forever. The
 * slot is cleared before the callback runs, so a callback that starts another
 * request cannot resolve itself twice.
 */
class PendingCallback<T> {
    private var callback: ((T) -> Unit)? = null

    val isPending: Boolean
        get() = callback != null

    fun replace(next: (T) -> Unit, supersededValue: T) {
        resolve(supersededValue)
        callback = next
    }

    fun resolve(value: T) {
        val current = callback ?: return
        callback = null
        current(value)
    }

    fun cancel(target: (T) -> Unit) {
        if (callback === target) {
            callback = null
        }
    }
}
