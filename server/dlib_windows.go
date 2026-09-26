//go:build windows

package main

import (
	"fmt"
	"syscall"
	"unsafe"
)

// openLib loads the trellis2 shared library on Windows. purego's Dlopen is
// POSIX-only; RegisterLibFunc on Windows resolves symbols with
// syscall.GetProcAddress, so a syscall.Handle works directly as the handle.
func openLib(path string) (uintptr, error) {
	d, err := syscall.LoadDLL(path)
	if err != nil {
		return 0, fmt.Errorf("LoadLibrary: %w", err)
	}
	// Keep the DLL alive for the process lifetime; RegisterLibFunc resolves
	// t2_* symbols lazily against this handle.
	loadedDLLs = append(loadedDLLs, d)
	return uintptr(unsafe.Pointer(d.Handle)), nil
}

// loadedDLLs retains handles so the loader never unloads them.
var loadedDLLs []*syscall.DLL
