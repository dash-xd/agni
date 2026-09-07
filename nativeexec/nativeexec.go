package nativeexec

import (
	"context"
	"fmt"
	"os"
	"os/exec"
	"strings"
)

// Run executes a native tool without changing its arguments, environment,
// state, or configuration semantics. Agni composes mature native tools; it
// does not reimplement them.
func Run(ctx context.Context, program string, args ...string) error {
	program = strings.TrimSpace(program)
	if program == "" {
		return fmt.Errorf("program is required")
	}
	path, err := exec.LookPath(program)
	if err != nil {
		return fmt.Errorf("find %s: %w", program, err)
	}
	cmd := exec.CommandContext(ctx, path, args...)
	cmd.Stdin = os.Stdin
	cmd.Stdout = os.Stdout
	cmd.Stderr = os.Stderr
	cmd.Env = os.Environ()
	if err := cmd.Run(); err != nil {
		return fmt.Errorf("%s: %w", program, err)
	}
	return nil
}
