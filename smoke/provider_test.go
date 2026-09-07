package smoke

import (
	"os"
	"path/filepath"
	"testing"
)

func TestPrepareWorkspaceMaterializesSelectedModulesAndRootFiles(t *testing.T) {
	dir := t.TempDir()
	files := map[string][]byte{"main.tf": []byte("terraform {}\n")}
	if err := prepareWorkspace(dir, []string{"regional-network"}, files); err != nil {
		t.Fatal(err)
	}
	for _, path := range []string{
		filepath.Join(dir, "main.tf"),
		filepath.Join(dir, "modules", "regional-network", "main.tf"),
	} {
		if _, err := os.Stat(path); err != nil {
			t.Fatalf("missing %s: %v", path, err)
		}
	}
	if _, err := os.Stat(filepath.Join(dir, "modules", "coreos-node", "main.tf")); !os.IsNotExist(err) {
		t.Fatalf("unselected module unexpectedly present: %v", err)
	}
}

func TestWriteRootFileRejectsTraversal(t *testing.T) {
	for _, name := range []string{"../escape.tf", "/tmp/escape.tf"} {
		if err := writeRootFile(t.TempDir(), name, []byte("x")); err == nil {
			t.Fatalf("expected %q to be rejected", name)
		}
	}
}
