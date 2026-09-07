package main

import (
	"context"
	"fmt"
	"os"

	"github.com/dash-xd/agni/nativeexec"
)

func main() {
	if err := run(context.Background(), os.Args[1:]); err != nil {
		fmt.Fprintf(os.Stderr, "agni: %v\n", err)
		os.Exit(1)
	}
}

func run(ctx context.Context, args []string) error {
	if len(args) == 0 {
		return usage()
	}

	switch args[0] {
	case "terraform":
		return nativeexec.Run(ctx, "terraform", args[1:]...)
	case "gcloud":
		return nativeexec.Run(ctx, "gcloud", args[1:]...)
	case "butane", "coreos":
		return nativeexec.Run(ctx, "butane", args[1:]...)
	case "qemu":
		program := os.Getenv("AGNI_QEMU")
		if program == "" {
			program = "qemu-system-x86_64"
		}
		return nativeexec.Run(ctx, program, args[1:]...)
	case "exec":
		if len(args) < 2 {
			return fmt.Errorf("usage: agni exec <program> [args...]")
		}
		return nativeexec.Run(ctx, args[1], args[2:]...)
	case "help", "-h", "--help":
		return usage()
	default:
		return fmt.Errorf("unknown command %q", args[0])
	}
}

func usage() error {
	fmt.Fprintln(os.Stderr, `usage: agni <command> [args...]

commands:
  terraform  invoke Terraform unchanged
  gcloud     invoke the Google Cloud CLI unchanged
  butane     invoke Butane unchanged
  coreos     alias for Butane
  qemu       invoke QEMU (AGNI_QEMU overrides qemu-system-x86_64)
  exec       invoke another native program unchanged

Agni contains no organization-specific credentials or deployment values.`)
	return nil
}
