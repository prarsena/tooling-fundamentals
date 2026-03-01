// wrapper.go — custom vminitd wrapper for apple/container
//
// This binary runs as /sbin/vminitd inside the micro-VM before the OCI
// container process starts. It performs custom VM-level initialisation and
// then exec's the real vminitd at /sbin/vminitd.real.
//
// Build (for Linux arm64, matching the container VM architecture):
//   CGO_ENABLED=0 GOOS=linux GOARCH=arm64 go build -o wrapper wrapper.go
package main

import (
	"os"
	"syscall"
)

func main() {
	// Example: write a message to the kernel ring buffer
	// These messages appear in `container logs --boot <name>`
	if kmsg, err := os.OpenFile("/dev/kmsg", os.O_WRONLY, 0); err == nil {
		kmsg.WriteString("<6>custom-init: === CUSTOM INIT RUNNING ===\n")
		kmsg.Close()
	}

	// Example: set an environment variable for child processes
	os.Setenv("CUSTOM_INIT_RAN", "1")

	// -----------------------------------------------------------------------
	// Add your VM-level initialisation here, for example:
	//
	//   // Load a kernel module
	//   exec.Command("modprobe", "my_module").Run()
	//
	//   // Configure a network interface
	//   exec.Command("ip", "link", "add", "dummy0", "type", "dummy").Run()
	//
	//   // Write a file that the container process can read
	//   os.WriteFile("/run/custom-init-token", []byte("hello"), 0644)
	// -----------------------------------------------------------------------

	// Hand off to the real vminitd. exec replaces this process entirely —
	// the real vminitd becomes PID 1 as normal.
	if err := syscall.Exec("/sbin/vminitd.real", os.Args, os.Environ()); err != nil {
		// If exec fails we have no init — bail out so the VM can fail visibly.
		os.Exit(1)
	}
}
