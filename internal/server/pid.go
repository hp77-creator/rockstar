package server

import (
	"fmt"
	"os"
	"path/filepath"
	"strconv"
	"syscall"
)

// pidFile manages the PID file for the server
type pidFile struct {
	path string
}

// newPIDFile creates a new PID file manager
func newPIDFile() (*pidFile, error) {
	homeDir, err := os.UserHomeDir()
	if err != nil {
		return nil, fmt.Errorf("failed to get home directory: %w", err)
	}

	// Use same directory as other app files
	pidDir := filepath.Join(homeDir, ".clipboard-manager")
	if err := os.MkdirAll(pidDir, 0755); err != nil {
		return nil, fmt.Errorf("failed to create PID directory: %w", err)
	}

	return &pidFile{
		path: filepath.Join(pidDir, "clipboard-manager.pid"),
	}, nil
}

// write writes the current process PID to the PID file
func (p *pidFile) write() error {
	pid := os.Getpid()
	return os.WriteFile(p.path, []byte(strconv.Itoa(pid)), 0644)
}

// read reads the PID from the PID file
func (p *pidFile) read() (int, error) {
	data, err := os.ReadFile(p.path)
	if err != nil {
		if os.IsNotExist(err) {
			return 0, nil
		}
		return 0, err
	}

	pid, err := strconv.Atoi(string(data))
	if err != nil {
		return 0, fmt.Errorf("invalid PID in file: %w", err)
	}

	return pid, nil
}

// remove removes the PID file
func (p *pidFile) remove() error {
	if err := os.Remove(p.path); err != nil && !os.IsNotExist(err) {
		return fmt.Errorf("failed to remove PID file: %w", err)
	}
	return nil
}

// isRunning checks if a process with the given PID is running
func isRunning(pid int) bool {
	process, err := os.FindProcess(pid)
	if err != nil {
		return false
	}

	// On Unix systems, FindProcess always succeeds, so we need to check if the process actually exists
	err = process.Signal(syscall.Signal(0))
	return err == nil
}

// killProcess attempts to kill a process with the given PID
func killProcess(pid int) error {
	process, err := os.FindProcess(pid)
	if err != nil {
		return fmt.Errorf("failed to find process: %w", err)
	}

	// First try SIGTERM for graceful shutdown
	if err := process.Signal(syscall.SIGTERM); err != nil {
		// If SIGTERM fails, force kill with SIGKILL
		if err := process.Kill(); err != nil {
			return fmt.Errorf("failed to kill process: %w", err)
		}
	}

	return nil
}
