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

func TestSeedRequiresDestination(t *testing.T) {
	if err := Seed(" "); err == nil {
		t.Fatal("expected destination error")
	}
}
