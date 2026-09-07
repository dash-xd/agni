// Package astrochicken owns the Astrochicken installation profile.
//
// The profile contains its Terraform root and probe configuration. The HCL is
// authoritative for which shared Agni modules it imports; callers do not
// maintain a second dependency manifest or enumerate modules on the command
// line.
package astrochicken

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

// Seed writes a complete Astrochicken source/config tree into dst. Root HCL is
// copied unchanged, profile configuration is copied beneath config/, and Agni's
// shared Terraform library is made available beneath modules/. Terraform itself
// remains authoritative for which modules the root imports and uses.
func Seed(dst string) error {
	dst = strings.TrimSpace(dst)
	if dst == "" {
		return fmt.Errorf("destination is required")
	}

	if err := copyTree("terraform", dst); err != nil {
		return fmt.Errorf("seed Astrochicken Terraform root: %w", err)
	}
	if err := copyTree("config", filepath.Join(dst, "config")); err != nil {
		return fmt.Errorf("seed Astrochicken config: %w", err)
	}
	if err := agnitf.Seed(dst); err != nil {
		return fmt.Errorf("seed Astrochicken shared Terraform library: %w", err)
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
