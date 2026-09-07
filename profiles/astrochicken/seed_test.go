package astrochicken

import (
	"os"
	"path/filepath"
	"testing"
)

func TestSeedWritesRootAndImportedModules(t *testing.T) {
	dst := t.TempDir()
	if err := Seed(dst); err != nil {
		t.Fatal(err)
	}
	for _, path := range []string{
		"main.tf",
		"variables.tf",
		"outputs.tf",
		"modules/regional-cell/main.tf",
		"modules/cloud-function-v1-http/main.tf",
		"modules/cloud-function-v2-http/main.tf",
	} {
		if _, err := os.Stat(filepath.Join(dst, filepath.FromSlash(path))); err != nil {
			t.Fatalf("missing seeded profile file %s: %v", path, err)
		}
	}
}
