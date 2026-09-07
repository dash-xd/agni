// Package terraform exposes Agni's reusable Terraform implementation as
// selectable embedded source. Callers choose which modules to seed;
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
var source embed.FS

var moduleNames = []string{
	"cloud-function-v1-http",
	"cloud-function-v2-http",
	"coreos-node",
	"regional-cell",
	"regional-internal-addresses",
	"regional-network",
}

func Modules() []string {
	out := append([]string(nil), moduleNames...)
	sort.Strings(out)
	return out
}

// SeedModules copies only the selected Agni-owned Terraform modules beneath
// dst/modules. This seed path is independent from Smoke ghxd/worktree seeding:
// it performs no Git operations, repository checkout, object sharing, or role
// ref handling. It only copies embedded Terraform source unchanged into a
// caller-owned root.
func SeedModules(dst string, names ...string) error {
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
		err := fs.WalkDir(source, root, func(path string, entry fs.DirEntry, err error) error {
			if err != nil {
				return err
			}
			if entry.IsDir() {
				return nil
			}
			data, err := source.ReadFile(path)
			if err != nil {
				return err
			}
			target := filepath.Join(dst, filepath.FromSlash(path))
			if err := os.MkdirAll(filepath.Dir(target), 0o755); err != nil {
				return err
			}
			return os.WriteFile(target, data, 0o644)
		})
		if err != nil {
			return fmt.Errorf("seed Terraform module %s: %w", name, err)
		}
	}
	return nil
}
