//go:build !windows

package main

import (
	"github.com/ebitengine/purego"
)

// openLib loads the trellis2 shared library on POSIX platforms.
func openLib(path string) (uintptr, error) {
	return purego.Dlopen(path, purego.RTLD_NOW|purego.RTLD_GLOBAL)
}
