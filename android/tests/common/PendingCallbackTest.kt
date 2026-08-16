package com.follow.clash.common

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class PendingCallbackTest {
    @Test
    fun `starts empty`() {
        val slot = PendingCallback<Boolean>()

        assertFalse(slot.isPending)
    }

    @Test
    fun `replace leaves the new callback pending`() {
        val slot = PendingCallback<Boolean>()

        slot.replace({ }, supersededValue = false)

        assertTrue(slot.isPending)
    }

    @Test
    fun `resolve delivers the value once and empties the slot`() {
        val slot = PendingCallback<Boolean>()
        val received = mutableListOf<Boolean>()
        slot.replace({ received.add(it) }, supersededValue = false)

        slot.resolve(true)
        slot.resolve(true)

        assertEquals(listOf(true), received)
        assertFalse(slot.isPending)
    }

    @Test
    fun `replace settles the request it supersedes`() {
        val slot = PendingCallback<Boolean>()
        val first = mutableListOf<Boolean>()
        val second = mutableListOf<Boolean>()
        slot.replace({ first.add(it) }, supersededValue = false)

        slot.replace({ second.add(it) }, supersededValue = false)

        assertEquals(listOf(false), first)
        assertTrue(second.isEmpty())

        slot.resolve(true)

        assertEquals(listOf(false), first)
        assertEquals(listOf(true), second)
    }

    @Test
    fun `resolve on an empty slot is inert`() {
        val slot = PendingCallback<Boolean>()

        slot.resolve(true)

        assertFalse(slot.isPending)
    }

    @Test
    fun `cancel drops the matching callback without invoking it`() {
        val slot = PendingCallback<Boolean>()
        val received = mutableListOf<Boolean>()
        val callback: (Boolean) -> Unit = { received.add(it) }
        slot.replace(callback, supersededValue = false)

        slot.cancel(callback)

        assertFalse(slot.isPending)
        assertTrue(received.isEmpty())
    }

    @Test
    fun `cancel keeps a callback that is no longer the pending one`() {
        val slot = PendingCallback<Boolean>()
        val stale = mutableListOf<Boolean>()
        val current = mutableListOf<Boolean>()
        val staleCallback: (Boolean) -> Unit = { stale.add(it) }
        slot.replace(staleCallback, supersededValue = false)
        slot.replace({ current.add(it) }, supersededValue = false)

        slot.cancel(staleCallback)

        assertTrue(slot.isPending)

        slot.resolve(true)

        assertEquals(listOf(false), stale)
        assertEquals(listOf(true), current)
    }

    @Test
    fun `a callback that starts a new request is not resolved twice`() {
        val slot = PendingCallback<Boolean>()
        val outer = mutableListOf<Boolean>()
        val inner = mutableListOf<Boolean>()
        slot.replace(
            {
                outer.add(it)
                slot.replace({ value -> inner.add(value) }, supersededValue = false)
            },
            supersededValue = false,
        )

        slot.resolve(true)

        assertEquals(listOf(true), outer)
        assertTrue(inner.isEmpty())
        assertTrue(slot.isPending)

        slot.resolve(false)

        assertEquals(listOf(true), outer)
        assertEquals(listOf(false), inner)
    }
}
