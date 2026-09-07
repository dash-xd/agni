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

func TestSeedModulesSelectsOnlyRequestedModules(t *testing.T) {
	dst := t.TempDir()
	if err := SeedModules(dst, "regional-network"); err != nil {
		t.Fatal(err)
	}
	if _, err := os.Stat(filepath.Join(dst, "modules", "regional-network", "main.tf")); err != nil {
		t.Fatalf("selected module missing: %v", err)
	}
	if _, err := os.Stat(filepath.Join(dst, "modules", "coreos-node", "main.tf")); !os.IsNotExist(err) {
		t.Fatalf("unselected module unexpectedly seeded: %v", err)
	}
}

func TestSeedModulesCanSelectServerlessModules(t *testing.T) {
	dst := t.TempDir()
	if err := SeedModules(dst, "cloud-function-v1-http", "cloud-function-v2-http"); err != nil {
		t.Fatal(err)
	}
	for _, name := range []string{"cloud-function-v1-http", "cloud-function-v2-http"} {
		if _, err := os.Stat(filepath.Join(dst, "modules", name, "main.tf")); err != nil {
			t.Fatalf("selected module %s missing: %v", name, err)
		}
	}
}

func TestSeedModulesCanSelectInternalAddressModule(t *testing.T) {
	dst := t.TempDir()
	if err := SeedModules(dst, "regional-internal-addresses"); err != nil {
		t.Fatal(err)
	}
	if _, err := os.Stat(filepath.Join(dst, "modules", "regional-internal-addresses", "main.tf")); err != nil {
		t.Fatalf("selected internal address module missing: %v", err)
	}
}

func TestSeedModulesRejectsUnknownModule(t *testing.T) {
	if err := SeedModules(t.TempDir(), "astrochicken"); err == nil {
		t.Fatal("expected unknown module error")
	}
}
