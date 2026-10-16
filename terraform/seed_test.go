package terraform

import (
	"os"
	"path/filepath"
	"reflect"
	"testing"
)

func TestModules(t *testing.T) {
	want := []string{"cloud-function-v1-http", "cloud-function-v2-http", "coreos-node", "regional-cell", "regional-internal-addresses", "regional-network"}
	if got := Modules(); !reflect.DeepEqual(got, want) {
		t.Fatalf("Modules() = %#v, want %#v", got, want)
	}
}

func TestSeedWritesSharedLibrary(t *testing.T) {
	dst := t.TempDir()
	if err := Seed(dst); err != nil {
		t.Fatal(err)
	}
	for _, name := range Modules() {
		if _, err := os.Stat(filepath.Join(dst, "modules", name, "main.tf")); err != nil {
			t.Fatalf("shared module %s missing: %v", name, err)
		}
	}
}

func TestSeedRemovesStaleModuleSource(t *testing.T) {
	dst := t.TempDir()
	stale := filepath.Join(dst, "modules", "removed-module", "main.tf")
	if err := os.MkdirAll(filepath.Dir(stale), 0o755); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(stale, []byte("stale\n"), 0o644); err != nil {
		t.Fatal(err)
	}
	state := filepath.Join(dst, "terraform.tfstate")
	if err := os.WriteFile(state, []byte("{}\n"), 0o600); err != nil {
		t.Fatal(err)
	}

	if err := Seed(dst); err != nil {
		t.Fatal(err)
	}
	if _, err := os.Stat(stale); !os.IsNotExist(err) {
		t.Fatalf("stale module source still exists: %v", err)
	}
	if _, err := os.Stat(state); err != nil {
		t.Fatalf("state artifact was not preserved: %v", err)
	}
}

func TestSeedRequiresDestination(t *testing.T) {
	if err := Seed(" "); err == nil {
		t.Fatal("expected destination error")
	}
}
