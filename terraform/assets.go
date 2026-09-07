// Package terraform exposes Agni's reusable Terraform implementation as
// selectable embedded assets. Callers choose which modules to materialize;
// Agni does not impose a deployment topology or environment name.
package terraform

import (
	"embed"
	"fmt"
	"io/fs"
	"os"
	"path/filepath"
	"sort"
	"strings"
)

//go:embed modules/*/*.tf
var assets embed.FS

var moduleNames = []string{
	"coreos-node",
	"regional-cell",
	"regional-network",
}

// Modules returns the reusable Terraform modules compiled into this Agni
// package.
func Modules() []string {
	out := append([]string(nil), moduleNames...)
	sort.Strings(out)
	return out
}

// MaterializeModules writes only the selected modules beneath dst/modules.
// This is intentionally selection-driven so clients such as Smoke can compose
// a narrow transient Terraform root without copying every Agni environment or
// asset into their execution scope.
func MaterializeModules(dst string, names ...string) error {
	dst = strings.TrimSpace(dst)
	if dst == "" {
		return fmt.Errorf("destination is required")
	}
	if len(names) == 0 {
		return fmt.Errorf("at least one Terraform module is required")
	}

	known := make(map[string]struct{}, len(moduleNames))
	for _, name := range moduleNames {
		known[name] = struct{}{}
	}

	seen := map[string]struct{}{}
	for _, name := range names {
		name = strings.TrimSpace(name)
		if _, ok := known[name]; !ok {
			return fmt.Errorf("unknown Terraform module %q", name)
		}
		if _, ok := seen[name]; ok {
			continue
		}
		seen[name] = struct{}{}

		root := "modules/" + name
		err := fs.WalkDir(assets, root, func(path string, entry fs.DirEntry, err error) error {
			if err != nil {
				return err
			}
			if entry.IsDir() {
				return nil
			}
			data, err := assets.ReadFile(path)
			if err != nil {
				return err
			}
			target := filepath.Join(dst, filepath.FromSlash(path))
			if err := os.MkdirAll(filepath.Dir(target), 0o755); err != nil {
				return err
			}
			if err := os.WriteFile(target, data, 0o644); err != nil {
				return err
			}
			return nil
		})
		if err != nil {
			return fmt.Errorf("materialize Terraform module %s: %w", name, err)
		}
	}
	return nil
}
