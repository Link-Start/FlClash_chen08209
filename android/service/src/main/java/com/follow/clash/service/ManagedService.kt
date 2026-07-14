package com.follow.clash.service

import com.follow.clash.common.BroadcastAction
import com.follow.clash.common.GlobalState
import com.follow.clash.common.sendBroadcast

interface ManagedService {
    fun notifyCreated() {
        GlobalState.log("Service created")
        BroadcastAction.SERVICE_CREATED.sendBroadcast()
    }

    fun notifyDestroyed() {
        GlobalState.log("Service destroyed")
        BroadcastAction.SERVICE_DESTROYED.sendBroadcast()
    }

    fun start()

    fun stop()
}
