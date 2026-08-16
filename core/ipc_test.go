//go:build !cgo

package main

import (
	"bytes"
	"encoding/binary"
	"encoding/json"
	"io"
	"strings"
	"sync"
	"testing"
)

type fakeConn struct {
	mu       sync.Mutex
	written  bytes.Buffer
	readable *bytes.Reader
}

func (fake *fakeConn) Read(p []byte) (int, error) {
	if fake.readable == nil {
		return 0, io.EOF
	}
	return fake.readable.Read(p)
}

func (fake *fakeConn) Write(p []byte) (int, error) {
	fake.mu.Lock()
	defer fake.mu.Unlock()
	return fake.written.Write(p)
}

func (fake *fakeConn) Close() error {
	return nil
}

func (fake *fakeConn) frames(t *testing.T) [][]byte {
	t.Helper()
	fake.mu.Lock()
	defer fake.mu.Unlock()
	reader := bytes.NewReader(fake.written.Bytes())
	var frames [][]byte
	for {
		frame, err := readFrame(reader)
		if err == io.EOF {
			return frames
		}
		if err != nil {
			t.Fatalf("readFrame error: %v", err)
		}
		frames = append(frames, frame)
	}
}

func captureFrames(t *testing.T, run func()) [][]byte {
	t.Helper()
	fake := &fakeConn{}
	previous := conn
	conn = fake
	defer func() { conn = previous }()
	run()
	return fake.frames(t)
}

func captureSingleFrame(t *testing.T, run func()) []byte {
	t.Helper()
	frames := captureFrames(t, run)
	if len(frames) != 1 {
		t.Fatalf("captured %d frames, want 1", len(frames))
	}
	return frames[0]
}

func TestWriteFrameReadFrameRoundTrip(t *testing.T) {
	payloads := [][]byte{
		[]byte(""),
		[]byte("{}"),
		bytes.Repeat([]byte("x"), 70000),
	}

	buffer := &bytes.Buffer{}
	for _, payload := range payloads {
		if err := writeFrame(buffer, payload); err != nil {
			t.Fatalf("writeFrame error: %v", err)
		}
	}

	for i, payload := range payloads {
		got, err := readFrame(buffer)
		if err != nil {
			t.Fatalf("readFrame %d error: %v", i, err)
		}
		if !bytes.Equal(got, payload) {
			t.Errorf("frame %d length = %d, want %d", i, len(got), len(payload))
		}
	}
}

func TestWriteFrameRejectsOversizedPayload(t *testing.T) {
	err := writeFrame(&bytes.Buffer{}, make([]byte, maxIPCFrameSize+1))

	if err == nil {
		t.Fatal("writeFrame accepted a payload above the frame limit")
	}
	if !strings.Contains(err.Error(), "IPC frame exceeds") {
		t.Errorf("writeFrame error = %v, want an IPC frame limit error", err)
	}
}

func TestReadFrameRejectsOversizedHeader(t *testing.T) {
	header := make([]byte, 4)
	binary.LittleEndian.PutUint32(header, maxIPCFrameSize+1)

	_, err := readFrame(bytes.NewReader(header))

	if err == nil {
		t.Fatal("readFrame accepted a header above the frame limit")
	}
	if !strings.Contains(err.Error(), "IPC frame exceeds") {
		t.Errorf("readFrame error = %v, want an IPC frame limit error", err)
	}
}

func TestReadFrameRejectsTruncatedPayload(t *testing.T) {
	header := make([]byte, 4)
	binary.LittleEndian.PutUint32(header, 8)
	truncated := append(header, []byte("abc")...)

	if _, err := readFrame(bytes.NewReader(truncated)); err == nil {
		t.Fatal("readFrame accepted a truncated payload")
	}
}

func TestMethodResponseSuccessEnvelope(t *testing.T) {
	frame := captureSingleFrame(t, func() {
		MethodResponse{ID: "42"}.success(map[string]any{"ok": true})
	})

	var envelope map[string]any
	if err := json.Unmarshal(frame, &envelope); err != nil {
		t.Fatalf("response is not valid JSON: %v", err)
	}
	if envelope["id"] != "42" {
		t.Errorf("id = %v, want 42", envelope["id"])
	}
	if _, hasError := envelope["error"]; hasError {
		t.Error("a successful response must omit the error field")
	}
	result, ok := envelope["result"].(map[string]any)
	if !ok || result["ok"] != true {
		t.Errorf("result = %v, want {ok: true}", envelope["result"])
	}
}

func TestMethodResponseFailureEnvelope(t *testing.T) {
	frame := captureSingleFrame(t, func() {
		MethodResponse{ID: "7"}.failure("core_error", "boom", []string{"detail"})
	})

	var envelope struct {
		ID     string       `json:"id"`
		Result any          `json:"result"`
		Error  *MethodError `json:"error"`
	}
	if err := json.Unmarshal(frame, &envelope); err != nil {
		t.Fatalf("response is not valid JSON: %v", err)
	}
	if envelope.ID != "7" {
		t.Errorf("id = %s, want 7", envelope.ID)
	}
	if envelope.Result != nil {
		t.Errorf("result = %v, want null on failure", envelope.Result)
	}
	if envelope.Error == nil {
		t.Fatal("failure response must carry an error")
	}
	if envelope.Error.Code != "core_error" || envelope.Error.Message != "boom" {
		t.Errorf("error = %+v, want code core_error message boom", envelope.Error)
	}
}

func TestDecodeMethodArgumentsRejectsInvalidPayloads(t *testing.T) {
	tests := []struct {
		name      string
		arguments string
	}{
		{name: "missing", arguments: ""},
		{name: "null", arguments: "null"},
		{name: "wrong type", arguments: `"not-an-object"`},
	}

	for _, test := range tests {
		t.Run(test.name, func(t *testing.T) {
			call := &MethodCall{
				ID:        "1",
				Method:    initClashMethod,
				Arguments: json.RawMessage(test.arguments),
			}
			target := InitParams{}
			accepted := true

			frame := captureSingleFrame(t, func() {
				accepted = decodeMethodArguments(call, MethodResponse{ID: call.ID}, &target)
			})

			if accepted {
				t.Fatal("decodeMethodArguments accepted an invalid payload")
			}
			var envelope struct {
				Error *MethodError `json:"error"`
			}
			if err := json.Unmarshal(frame, &envelope); err != nil {
				t.Fatalf("response is not valid JSON: %v", err)
			}
			if envelope.Error == nil || envelope.Error.Code != "invalid_arguments" {
				t.Errorf("error = %+v, want code invalid_arguments", envelope.Error)
			}
		})
	}
}

func TestDecodeMethodArgumentsAcceptsValidPayload(t *testing.T) {
	call := &MethodCall{
		ID:        "1",
		Method:    initClashMethod,
		Arguments: json.RawMessage(`{"home-dir":"/tmp/flclash","version":3}`),
	}
	target := InitParams{}

	frames := captureFrames(t, func() {
		if !decodeMethodArguments(call, MethodResponse{ID: call.ID}, &target) {
			t.Fatal("decodeMethodArguments rejected a valid payload")
		}
	})

	if len(frames) != 0 {
		t.Errorf("a successful decode must not send a response, got %d frames", len(frames))
	}
	if target.HomeDir != "/tmp/flclash" || target.Version != 3 {
		t.Errorf("decoded params = %+v, want {/tmp/flclash 3}", target)
	}
}

func TestHandleMethodCallReportsUnknownMethod(t *testing.T) {
	frame := captureSingleFrame(t, func() {
		handleMethodCall(
			&MethodCall{ID: "9", Method: CoreMethod("nopeMethod")},
			MethodResponse{ID: "9"},
		)
	})

	var envelope struct {
		Error *MethodError `json:"error"`
	}
	if err := json.Unmarshal(frame, &envelope); err != nil {
		t.Fatalf("response is not valid JSON: %v", err)
	}
	if envelope.Error == nil || envelope.Error.Code != "not_implemented" {
		t.Fatalf("error = %+v, want code not_implemented", envelope.Error)
	}
	if !strings.Contains(envelope.Error.Message, "nopeMethod") {
		t.Errorf("error message = %s, want it to name the method", envelope.Error.Message)
	}
}

func TestSendMessageBatchWrapsMessagesInMethodCall(t *testing.T) {
	batch := []Message{
		{Type: DelayMessage, Data: Delay{Url: "https://example.test", Name: "a", Value: 12}},
		{Type: LogMessage, Data: "hello"},
	}

	frame := captureSingleFrame(t, func() {
		sendMessageBatch(batch)
	})

	call := MethodCall{}
	if err := json.Unmarshal(frame, &call); err != nil {
		t.Fatalf("batch frame is not a MethodCall: %v", err)
	}
	if call.Method != messageMethod {
		t.Errorf("method = %s, want %s", call.Method, messageMethod)
	}
	if call.ID != "" {
		t.Errorf("id = %s, want an empty id for event calls", call.ID)
	}

	var decoded []Message
	if err := json.Unmarshal(call.Arguments, &decoded); err != nil {
		t.Fatalf("arguments are not a message list: %v", err)
	}
	if len(decoded) != 2 {
		t.Fatalf("decoded %d messages, want 2", len(decoded))
	}
	if decoded[0].Type != DelayMessage || decoded[1].Type != LogMessage {
		t.Errorf("decoded types = %s,%s, want delay,log", decoded[0].Type, decoded[1].Type)
	}
}

func TestSendWithoutConnectionDoesNotPanic(t *testing.T) {
	previous := conn
	conn = nil
	defer func() { conn = previous }()

	send([]byte("{}"))
}
