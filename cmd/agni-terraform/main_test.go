package main

import (
	"os"
	"path/filepath"
	"testing"
)

func TestMaterializeSelectedModule(t *testing.T) {
	dir := t.TempDir()
	if err := materialize([]string{"--module", "regional-network", dir}); err != nil {
		t.Fatal(err)
	}
	if _, err := os.Stat(filepath.Join(dir, "modules", "regional-network", "main.tf")); err != nil {
		t.Fatalf("materialized module missing: %v", err)
	}
}

func TestMaterializeRequiresModule(t *testing.T) {
	if err := materialize([]string{t.TempDir()}); err == nil {
		t.Fatal("expected missing module error")
	}
}
