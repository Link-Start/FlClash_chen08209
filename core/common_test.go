package main

import (
	"encoding/json"
	"os"
	"path/filepath"
	"testing"
)

func TestDefaultSetupParams(t *testing.T) {
	params := defaultSetupParams()

	if params.TestURL != "https://www.gstatic.com/generate_204" {
		t.Errorf("TestURL = %s, want the gstatic generate_204 probe", params.TestURL)
	}
	if params.SelectedMap == nil {
		t.Error("SelectedMap must be a usable map so decoding can merge into it")
	}
}

func TestDefaultSetupParamsSurvivesPartialDecode(t *testing.T) {
	params := defaultSetupParams()

	if err := json.Unmarshal([]byte(`{"selected-map":{"GLOBAL":"auto"}}`), params); err != nil {
		t.Fatalf("decode error: %v", err)
	}

	if params.TestURL != "https://www.gstatic.com/generate_204" {
		t.Errorf("TestURL = %s, want the default to survive a partial payload", params.TestURL)
	}
	if params.SelectedMap["GLOBAL"] != "auto" {
		t.Errorf("SelectedMap = %v, want GLOBAL mapped to auto", params.SelectedMap)
	}
}

func TestReadFile(t *testing.T) {
	dir := t.TempDir()
	path := filepath.Join(dir, "config.yaml")
	want := []byte("mixed-port: 7890\n")
	if err := os.WriteFile(path, want, 0o600); err != nil {
		t.Fatalf("setup error: %v", err)
	}

	got, err := readFile(path)
	if err != nil {
		t.Fatalf("readFile error: %v", err)
	}
	if string(got) != string(want) {
		t.Errorf("readFile = %q, want %q", got, want)
	}
}

func TestReadFileReportsMissingPath(t *testing.T) {
	_, err := readFile(filepath.Join(t.TempDir(), "absent.yaml"))

	if err == nil {
		t.Fatal("readFile accepted a missing path")
	}
	if !os.IsNotExist(err) {
		t.Errorf("readFile error = %v, want a not-exist error", err)
	}
}

func TestUnmarshalJsonPreservesLargeIntegers(t *testing.T) {
	target := map[string]any{}

	if err := UnmarshalJson([]byte(`{"id":9007199254740993}`), &target); err != nil {
		t.Fatalf("UnmarshalJson error: %v", err)
	}

	number, ok := target["id"].(json.Number)
	if !ok {
		t.Fatalf("id decoded as %T, want json.Number so int64 precision survives", target["id"])
	}
	value, err := number.Int64()
	if err != nil {
		t.Fatalf("Int64() error: %v", err)
	}
	if value != 9007199254740993 {
		t.Errorf("id = %d, want 9007199254740993", value)
	}
}

func TestUnmarshalJsonReportsInvalidPayload(t *testing.T) {
	target := map[string]any{}

	if err := UnmarshalJson([]byte(`{`), &target); err == nil {
		t.Fatal("UnmarshalJson accepted malformed JSON")
	}
}

func TestToExternalProviderRejectsUnsupportedProvider(t *testing.T) {
	provider, err := toExternalProvider(nil)

	if err == nil {
		t.Fatal("toExternalProvider accepted a provider it cannot describe")
	}
	if provider != nil {
		t.Errorf("provider = %+v, want nil alongside the error", provider)
	}
}

func TestMethodCallDecodeArgumentsRejectsEmptyPayload(t *testing.T) {
	tests := map[string]json.RawMessage{
		"empty": nil,
		"null":  json.RawMessage("null"),
	}

	for name, arguments := range tests {
		t.Run(name, func(t *testing.T) {
			call := MethodCall{Method: validateConfigMethod, Arguments: arguments}
			target := ""

			err := call.decodeArguments(&target)

			if err == nil {
				t.Fatal("decodeArguments accepted a missing payload")
			}
			if err.Error() != "missing arguments" {
				t.Errorf("error = %v, want \"missing arguments\"", err)
			}
		})
	}
}

func TestMethodCallDecodeArgumentsAcceptsScalar(t *testing.T) {
	call := MethodCall{
		Method:    validateConfigMethod,
		Arguments: json.RawMessage(`"/tmp/config.yaml"`),
	}
	target := ""

	if err := call.decodeArguments(&target); err != nil {
		t.Fatalf("decodeArguments error: %v", err)
	}
	if target != "/tmp/config.yaml" {
		t.Errorf("target = %s, want /tmp/config.yaml", target)
	}
}
