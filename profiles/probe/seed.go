// Package probe owns the reusable Probe installation profile.
//
// The profile contains its Terraform root and transient probe configuration.
// The HCL is authoritative for which shared Agni modules it imports; callers do
// not maintain a second dependency manifest or enumerate modules on the command
// line.
package probe

import (
	"embed"
	"fmt"
	"io/fs"
	"os"
	"path/filepath"
	"strings"

	agnitf "github.com/dash-xd/agni/terraform"
)

//go:embed terraform/*.tf config/*
var profileFS embed.FS

// Seed writes a complete Probe source/config tree into dst. Root HCL is copied
// unchanged, profile configuration is copied beneath config/, and Agni's shared
// Terraform library is made available beneath modules/. Terraform itself
// remains authoritative for which modules the root imports and uses.
//
// Probe owns root-level *.tf, config/, and modules/. Reseeding reconciles those
// source paths so files removed from the selected profile cannot survive and
// continue affecting Terraform or bootstrap behavior. Terraform runtime/state
// artifacts such as .terraform/ and terraform.tfstate are deliberately outside
// that source ownership and are preserved.
func Seed(dst string) error {
	dst = strings.TrimSpace(dst)
	if dst == "" {
		return fmt.Errorf("destination is required")
	}
	if err := os.MkdirAll(dst, 0o755); err != nil {
		return err
	}
	if err := reconcileRootTerraform("terraform", dst); err != nil {
		return fmt.Errorf("reconcile Probe Terraform root: %w", err)
	}
	if err := os.RemoveAll(filepath.Join(dst, "config")); err != nil {
		return fmt.Errorf("remove stale Probe config: %w", err)
	}
	if err := copyTree("terraform", dst); err != nil {
		return fmt.Errorf("seed Probe Terraform root: %w", err)
	}
	if err := copyTree("config", filepath.Join(dst, "config")); err != nil {
		return fmt.Errorf("seed Probe config: %w", err)
	}
	if err := agnitf.Seed(dst); err != nil {
		return fmt.Errorf("seed Probe shared Terraform library: %w", err)
	}
	return nil
}

func reconcileRootTerraform(sourceRoot, dst string) error {
	root, err := fs.Sub(profileFS, sourceRoot)
	if err != nil {
		return err
	}
	entries, err := fs.ReadDir(root, ".")
	if err != nil {
		return err
	}
	desired := make(map[string]struct{}, len(entries))
	for _, entry := range entries {
		if !entry.IsDir() && filepath.Ext(entry.Name()) == ".tf" {
			desired[entry.Name()] = struct{}{}
		}
	}
	existing, err := os.ReadDir(dst)
	if err != nil {
		return err
	}
	for _, entry := range existing {
		if entry.IsDir() || filepath.Ext(entry.Name()) != ".tf" {
			continue
		}
		if _, ok := desired[entry.Name()]; ok {
			continue
		}
		if err := os.Remove(filepath.Join(dst, entry.Name())); err != nil {
			return fmt.Errorf("remove stale profile source %s: %w", entry.Name(), err)
		}
	}
	return nil
}

func copyTree(sourceRoot, dst string) error {
	root, err := fs.Sub(profileFS, sourceRoot)
	if err != nil {
		return err
	}
	return fs.WalkDir(root, ".", func(path string, entry fs.DirEntry, walkErr error) error {
		if walkErr != nil {
			return walkErr
		}
		if entry.IsDir() {
			return nil
		}
		data, err := fs.ReadFile(root, path)
		if err != nil {
			return err
		}
		target := filepath.Join(dst, filepath.FromSlash(path))
		if err := os.MkdirAll(filepath.Dir(target), 0o755); err != nil {
			return err
		}
		return os.WriteFile(target, data, 0o644)
	})
}
