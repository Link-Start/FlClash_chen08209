package main

import (
	"os"
	"path/filepath"
	"strings"
	"testing"

	"github.com/metacubex/mihomo/constant"
)

// typeMap turns a name -> adapter type table into the lookup proxyGroupNames
// expects, reporting a miss for any name outside the table.
func typeMap(types map[string]constant.AdapterType) func(string) (constant.AdapterType, bool) {
	return func(name string) (constant.AdapterType, bool) {
		adapterType, ok := types[name]
		return adapterType, ok
	}
}

func TestProxyGroupNamesKeepsOnlyGroups(t *testing.T) {
	names := proxyGroupNames(
		[]string{"GLOBAL", "Auto", "Direct node", "Fall", "Balance", "Chain"},
		typeMap(map[string]constant.AdapterType{
			"GLOBAL":      constant.Selector,
			"Auto":        constant.URLTest,
			"Direct node": constant.Direct,
			"Fall":        constant.Fallback,
			"Balance":     constant.LoadBalance,
			"Chain":       constant.Relay,
		}),
	)

	want := []string{"GLOBAL", "Auto", "Fall", "Balance", "Chain"}
	if strings.Join(names, ",") != strings.Join(want, ",") {
		t.Fatalf("proxyGroupNames = %v, want %v", names, want)
	}
}

func TestProxyGroupNamesPreservesListOrder(t *testing.T) {
	names := proxyGroupNames(
		[]string{"C", "A", "B"},
		typeMap(map[string]constant.AdapterType{
			"A": constant.Selector,
			"B": constant.Selector,
			"C": constant.Selector,
		}),
	)

	if strings.Join(names, ",") != "C,A,B" {
		t.Fatalf("proxyGroupNames = %v, want the config order C,A,B", names)
	}
}

func TestProxyGroupNamesSkipsUnknownNames(t *testing.T) {
	names := proxyGroupNames(
		[]string{"Known", "Missing"},
		typeMap(map[string]constant.AdapterType{"Known": constant.Selector}),
	)

	if len(names) != 1 || names[0] != "Known" {
		t.Fatalf("proxyGroupNames = %v, want only the registered name", names)
	}
}

func TestProxyGroupNamesPrependsUnlistedGlobal(t *testing.T) {
	names := proxyGroupNames(
		[]string{"Auto"},
		typeMap(map[string]constant.AdapterType{
			"Auto":   constant.URLTest,
			"GLOBAL": constant.Selector,
		}),
	)

	want := []string{"GLOBAL", "Auto"}
	if strings.Join(names, ",") != strings.Join(want, ",") {
		t.Fatalf("proxyGroupNames = %v, want %v", names, want)
	}
}

func TestProxyGroupNamesDoesNotDuplicateListedGlobal(t *testing.T) {
	names := proxyGroupNames(
		[]string{"Auto", "GLOBAL"},
		typeMap(map[string]constant.AdapterType{
			"Auto":   constant.URLTest,
			"GLOBAL": constant.Selector,
		}),
	)

	want := []string{"Auto", "GLOBAL"}
	if strings.Join(names, ",") != strings.Join(want, ",") {
		t.Fatalf("proxyGroupNames = %v, want %v", names, want)
	}
}

func TestProxyGroupNamesOmitsMissingGlobal(t *testing.T) {
	names := proxyGroupNames(
		[]string{"Auto"},
		typeMap(map[string]constant.AdapterType{"Auto": constant.URLTest}),
	)

	if len(names) != 1 || names[0] != "Auto" {
		t.Fatalf("proxyGroupNames = %v, want no GLOBAL entry", names)
	}
}

// A GLOBAL that is not a group used to be prepended without any type check
// while a listed one was filtered out, so the same adapter produced two
// different results depending on whether the config named it.
func TestProxyGroupNamesTreatsGlobalLikeAnyOtherName(t *testing.T) {
	types := map[string]constant.AdapterType{
		"Auto":   constant.URLTest,
		"GLOBAL": constant.Direct,
	}

	unlisted := proxyGroupNames([]string{"Auto"}, typeMap(types))
	listed := proxyGroupNames([]string{"GLOBAL", "Auto"}, typeMap(types))

	if strings.Join(unlisted, ",") != "Auto" {
		t.Fatalf("unlisted GLOBAL = %v, want it filtered out like a listed one", unlisted)
	}
	if strings.Join(listed, ",") != "Auto" {
		t.Fatalf("listed GLOBAL = %v, want it filtered out", listed)
	}
}

func TestProxyGroupNamesEmptyList(t *testing.T) {
	names := proxyGroupNames(nil, typeMap(nil))
	if len(names) != 0 {
		t.Fatalf("proxyGroupNames = %v, want empty", names)
	}
}

func TestIsProxyGroupType(t *testing.T) {
	groups := []constant.AdapterType{
		constant.Selector,
		constant.URLTest,
		constant.Fallback,
		constant.Relay,
		constant.LoadBalance,
	}
	for _, adapterType := range groups {
		if !isProxyGroupType(adapterType) {
			t.Errorf("isProxyGroupType(%v) = false, want true", adapterType)
		}
	}

	singles := []constant.AdapterType{constant.Direct, constant.Reject}
	for _, adapterType := range singles {
		if isProxyGroupType(adapterType) {
			t.Errorf("isProxyGroupType(%v) = true, want false", adapterType)
		}
	}
}

func TestDelayValue(t *testing.T) {
	tests := []struct {
		delay uint16
		want  int32
	}{
		{delay: 0, want: -1},
		{delay: 1, want: 1},
		{delay: 250, want: 250},
		{delay: 65535, want: 65535},
	}
	for _, test := range tests {
		if got := delayValue(test.delay); got != test.want {
			t.Errorf("delayValue(%d) = %d, want %d", test.delay, got, test.want)
		}
	}
}

func TestProviderPathsStayUnderTheRoot(t *testing.T) {
	home := filepath.Join("var", "home")
	root, target := providerPaths(home, 1234567890123)

	wantRoot := filepath.Join(home, "profiles", "providers")
	if root != wantRoot {
		t.Fatalf("root = %q, want %q", root, wantRoot)
	}
	wantTarget := filepath.Join(wantRoot, "1234567890123")
	if target != wantTarget {
		t.Fatalf("target = %q, want %q", target, wantTarget)
	}
}

// The ID is an int64 rendered through strconv, so no caller-supplied value can
// add a separator or climb out of the providers root.
func TestProviderPathsCannotEscape(t *testing.T) {
	home := t.TempDir()
	ids := []int64{1, -1, 0, 1 << 62, -(1 << 62)}

	for _, id := range ids {
		root, target := providerPaths(home, id)
		cleaned := filepath.Clean(target)
		if !strings.HasPrefix(cleaned, root+string(filepath.Separator)) {
			t.Errorf("providerPaths(%d) escaped: %q is outside %q", id, cleaned, root)
		}
		if filepath.Dir(cleaned) != root {
			t.Errorf("providerPaths(%d) = %q, want a direct child of %q", id, cleaned, root)
		}
	}
}

func TestHandleValidateConfigAcceptsAValidFile(t *testing.T) {
	path := filepath.Join(t.TempDir(), "config.yaml")
	if err := os.WriteFile(path, []byte("mixed-port: 7890\n"), 0o600); err != nil {
		t.Fatalf("write config: %v", err)
	}

	if got := handleValidateConfig(path); got != "" {
		t.Fatalf("handleValidateConfig = %q, want no error", got)
	}
}

// A read failure used to be overwritten by the unmarshal result, so a path that
// does not exist was reported as a valid configuration.
func TestHandleValidateConfigReportsAMissingFile(t *testing.T) {
	got := handleValidateConfig(filepath.Join(t.TempDir(), "absent.yaml"))

	if got == "" {
		t.Fatal("handleValidateConfig accepted a path that does not exist")
	}
	if !strings.Contains(got, "absent.yaml") {
		t.Errorf("handleValidateConfig = %q, want it to name the missing file", got)
	}
}

func TestHandleValidateConfigReportsMalformedYaml(t *testing.T) {
	path := filepath.Join(t.TempDir(), "config.yaml")
	if err := os.WriteFile(path, []byte("proxies: [unterminated\n"), 0o600); err != nil {
		t.Fatalf("write config: %v", err)
	}

	if got := handleValidateConfig(path); got == "" {
		t.Fatal("handleValidateConfig accepted malformed yaml")
	}
}
