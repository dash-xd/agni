package terraform

import (
	"os"
	"path/filepath"
	"reflect"
	"testing"
)

func TestModules(t *testing.T) {
	want := []string{"coreos-node", "regional-cell", "regional-network"}
	if got := Modules(); !reflect.DeepEqual(got, want) {
		t.Fatalf("Modules() = %#v, want %#v", got, want)
	}
}

func TestMaterializeModulesSelectsOnlyRequestedModules(t *testing.T) {
	dst := t.TempDir()
	if err := MaterializeModules(dst, "regional-network"); err != nil {
		t.Fatal(err)
	}
	if _, err := os.Stat(filepath.Join(dst, "modules", "regional-network", "main.tf")); err != nil {
		t.Fatalf("selected module missing: %v", err)
	}
	if _, err := os.Stat(filepath.Join(dst, "modules", "coreos-node", "main.tf")); !os.IsNotExist(err) {
		t.Fatalf("unselected module unexpectedly materialized: %v", err)
	}
}

func TestMaterializeModulesRejectsUnknownModule(t *testing.T) {
	if err := MaterializeModules(t.TempDir(), "astrochicken"); err == nil {
		t.Fatal("expected unknown module error")
	}
}
