package main

import (
	"fmt"
	"os"

	"github.com/dash-xd/agni/profiles/probe"
)

func main() {
	if len(os.Args) != 3 || os.Args[1] != "seed" {
		fmt.Fprintln(os.Stderr, "usage: probe seed <destination>")
		os.Exit(2)
	}
	if err := probe.Seed(os.Args[2]); err != nil {
		fmt.Fprintf(os.Stderr, "probe: %v\n", err)
		os.Exit(1)
	}
}
