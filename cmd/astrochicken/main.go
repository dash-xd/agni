package main

import (
	"fmt"
	"os"

	"github.com/dash-xd/agni/profiles/astrochicken"
)

func main() {
	if len(os.Args) != 3 || os.Args[1] != "seed" {
		fmt.Fprintln(os.Stderr, "usage: astrochicken seed <destination>")
		os.Exit(2)
	}
	if err := astrochicken.Seed(os.Args[2]); err != nil {
		fmt.Fprintf(os.Stderr, "astrochicken: %v\n", err)
		os.Exit(1)
	}
}
