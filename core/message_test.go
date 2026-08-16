package main

import (
	"sync"
	"testing"
	"time"
)

type batchCollector struct {
	mu      sync.Mutex
	batches [][]Message
}

func (collector *batchCollector) send(messages []Message) {
	collector.mu.Lock()
	defer collector.mu.Unlock()
	collector.batches = append(collector.batches, messages)
}

func (collector *batchCollector) snapshot() [][]Message {
	collector.mu.Lock()
	defer collector.mu.Unlock()
	return append([][]Message(nil), collector.batches...)
}

func (collector *batchCollector) flattened() []Message {
	var messages []Message
	for _, batch := range collector.snapshot() {
		messages = append(messages, batch...)
	}
	return messages
}

func runBatcherUntilDrained(t *testing.T, priority, bulk chan Message) *batchCollector {
	t.Helper()
	collector := &batchCollector{}
	done := make(chan struct{})
	go func() {
		defer close(done)
		runMessageBatcher(priority, bulk, collector.send)
	}()
	select {
	case <-done:
	case <-time.After(5 * time.Second):
		t.Fatal("runMessageBatcher did not return after both queues closed")
	}
	return collector
}

func TestIsBulkMessageRoutesHighVolumeTypes(t *testing.T) {
	bulkTypes := []MessageType{LogMessage, RequestMessage}
	for _, messageType := range bulkTypes {
		if !isBulkMessage(Message{Type: messageType}) {
			t.Errorf("%s must be routed to the bulk queue", messageType)
		}
	}

	priorityTypes := []MessageType{DelayMessage, LoadedMessage, GeoUpdateMessage}
	for _, messageType := range priorityTypes {
		if isBulkMessage(Message{Type: messageType}) {
			t.Errorf("%s must be routed to the priority queue", messageType)
		}
	}
}

func TestEnqueueLatestEvictsOldestOfItsOwnQueue(t *testing.T) {
	queue := make(chan Message, 2)
	for i := 0; i < 4; i++ {
		enqueueLatest(queue, Message{Type: DelayMessage, Data: i})
	}

	if len(queue) != 2 {
		t.Fatalf("queue length = %d, want 2", len(queue))
	}
	for _, want := range []int{2, 3} {
		got := (<-queue).Data.(int)
		if got != want {
			t.Errorf("retained Data = %d, want %d", got, want)
		}
	}
}

func TestEnqueueLatestNeverBlocks(t *testing.T) {
	queue := make(chan Message, 1)
	done := make(chan struct{})
	go func() {
		defer close(done)
		for i := 0; i < 1000; i++ {
			enqueueLatest(queue, Message{Type: LogMessage, Data: i})
		}
	}()

	select {
	case <-done:
	case <-time.After(5 * time.Second):
		t.Fatal("enqueueLatest blocked on a full queue")
	}
}

func TestRunMessageBatcherPrefersPriorityAndGuaranteesBulkOpportunity(t *testing.T) {
	priority := make(chan Message, 64)
	bulk := make(chan Message, 64)
	for i := 0; i < 20; i++ {
		priority <- Message{Type: DelayMessage, Data: i}
	}
	for i := 0; i < 5; i++ {
		bulk <- Message{Type: LogMessage, Data: i}
	}
	close(priority)
	close(bulk)

	got := runBatcherUntilDrained(t, priority, bulk).flattened()

	want := make([]Message, 0, 25)
	appendPriority := func(from, to int) {
		for i := from; i < to; i++ {
			want = append(want, Message{Type: DelayMessage, Data: i})
		}
	}
	appendPriority(0, 8)
	want = append(want, Message{Type: LogMessage, Data: 0})
	appendPriority(8, 16)
	want = append(want, Message{Type: LogMessage, Data: 1})
	appendPriority(16, 20)
	want = append(want,
		Message{Type: LogMessage, Data: 2},
		Message{Type: LogMessage, Data: 3},
		Message{Type: LogMessage, Data: 4},
	)

	if len(got) != len(want) {
		t.Fatalf("delivered %d messages, want %d", len(got), len(want))
	}
	for i := range want {
		if got[i].Type != want[i].Type || got[i].Data != want[i].Data {
			t.Fatalf(
				"message %d = {%s %v}, want {%s %v}",
				i, got[i].Type, got[i].Data, want[i].Type, want[i].Data,
			)
		}
	}
}

func TestRunMessageBatcherFlushesAtBatchSize(t *testing.T) {
	total := messageBatchSize*2 + 6
	priority := make(chan Message, total)
	bulk := make(chan Message)
	for i := 0; i < total; i++ {
		priority <- Message{Type: DelayMessage, Data: i}
	}
	close(priority)
	close(bulk)

	batches := runBatcherUntilDrained(t, priority, bulk).snapshot()

	wantSizes := []int{messageBatchSize, messageBatchSize, 6}
	if len(batches) != len(wantSizes) {
		t.Fatalf("got %d batches, want %d", len(batches), len(wantSizes))
	}
	for i, wantSize := range wantSizes {
		if len(batches[i]) != wantSize {
			t.Errorf("batch %d size = %d, want %d", i, len(batches[i]), wantSize)
		}
	}
}

func TestRunMessageBatcherFlushesOnInterval(t *testing.T) {
	priority := make(chan Message, 4)
	bulk := make(chan Message, 4)
	collector := &batchCollector{}
	done := make(chan struct{})
	go func() {
		defer close(done)
		runMessageBatcher(priority, bulk, collector.send)
	}()

	for i := 0; i < 3; i++ {
		priority <- Message{Type: DelayMessage, Data: i}
	}

	deadline := time.After(2 * time.Second)
	for {
		if len(collector.flattened()) == 3 {
			break
		}
		select {
		case <-deadline:
			t.Fatal("batcher did not flush a partial batch on the interval tick")
		case <-time.After(5 * time.Millisecond):
		}
	}

	close(priority)
	close(bulk)
	select {
	case <-done:
	case <-time.After(5 * time.Second):
		t.Fatal("runMessageBatcher did not return after both queues closed")
	}
}

func TestRunMessageBatcherDrainsBulkAfterPriorityCloses(t *testing.T) {
	priority := make(chan Message)
	bulk := make(chan Message, 4)
	for i := 0; i < 4; i++ {
		bulk <- Message{Type: RequestMessage, Data: i}
	}
	close(priority)
	close(bulk)

	got := runBatcherUntilDrained(t, priority, bulk).flattened()

	if len(got) != 4 {
		t.Fatalf("delivered %d bulk messages, want 4", len(got))
	}
	for i, message := range got {
		if message.Type != RequestMessage || message.Data != i {
			t.Errorf("message %d = {%s %v}, want {request %d}", i, message.Type, message.Data, i)
		}
	}
}

func TestMessageJson(t *testing.T) {
	message := Message{
		Type: GeoUpdateMessage,
		Data: GeoUpdateStatus{Type: "geoip", Updating: true},
	}

	encoded, err := message.Json()
	if err != nil {
		t.Fatalf("Json() error = %v", err)
	}

	want := `{"type":"geoUpdate","data":{"type":"geoip","updating":true}}`
	if encoded != want {
		t.Errorf("Json() = %s, want %s", encoded, want)
	}
}
