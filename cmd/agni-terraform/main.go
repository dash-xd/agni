package main

import (
	"fmt"
	"os"
	"strings"

	agnitf "github.com/dash-xd/agni/terraform"
)

func main() {
	if err := run(os.Args[1:]); err != nil {
		fmt.Fprintf(os.Stderr, "agni-terraform: %v\n", err)
		os.Exit(1)
	}
}

func run(args []string) error {
	if len(args) == 0 {
		return usage()
	}
	switch args[0] {
	case "modules":
		if len(args) != 1 {
			return fmt.Errorf("usage: agni-terraform modules")
		}
		for _, name := range agnitf.Modules() {
			fmt.Println(name)
		}
		return nil
	case "seed":
		return seed(args[1:])
	default:
		return fmt.Errorf("unknown operation %q", args[0])
	}
}

func seed(args []string) error {
	var modules []string
	for len(args) > 0 && args[0] == "--module" {
		if len(args) < 2 || strings.TrimSpace(args[1]) == "" {
			return fmt.Errorf("--module requires a module name")
		}
		modules = append(modules, args[1])
		args = args[2:]
	}
	if len(args) != 1 || strings.TrimSpace(args[0]) == "" {
		return fmt.Errorf("usage: agni-terraform seed --module <name> [--module <name> ...] <destination>")
	}
	return agnitf.SeedModules(args[0], modules...)
}

func usage() error {
	return fmt.Errorf("usage: agni-terraform <modules|seed> ...")
}
