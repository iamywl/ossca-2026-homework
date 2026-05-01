package main

import (
	"encoding/json"
	"errors"
	"log"
	"net/http"
	"os"
	"os/exec"
	"path/filepath"
	"syscall"
)

type unshareRequest struct {
	Path string   `json:"path"`
	Args []string `json:"args"`
}

type unshareResponse struct {
	ParentPID int `json:"parent_pid"`
	ChildPID  int `json:"child_pid"`
}

func main() {
	mux := http.NewServeMux()
	mux.HandleFunc("/unshare/netns", handleUnshareNetNS)

	log.Fatal(http.ListenAndServe(":8080", mux))
}

func handleUnshareNetNS(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodPost {
		http.Error(w, "method not allowed", http.StatusMethodNotAllowed)
		return
	}

	var req unshareRequest
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		http.Error(w, "invalid json", http.StatusBadRequest)
		return
	}

	if err := validateRequest(req); err != nil {
		http.Error(w, err.Error(), http.StatusBadRequest)
		return
	}

	childPID, err := startInNewNetNS(req.Path, req.Args)
	if err != nil {
		http.Error(w, err.Error(), http.StatusInternalServerError)
		return
	}

	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(http.StatusOK)
	if err := json.NewEncoder(w).Encode(unshareResponse{
		ParentPID: os.Getpid(),
		ChildPID:  childPID,
	}); err != nil {
		log.Printf("failed to write response: %v", err)
	}
}

func validateRequest(req unshareRequest) error {
	if req.Path == "" {
		return errors.New("path is required")
	}
	if !filepath.IsAbs(req.Path) {
		return errors.New("path must be absolute")
	}
	return nil
}

func startInNewNetNS(path string, args []string) (int, error) {
	cmd := exec.Command(path, args...)
	cmd.SysProcAttr = &syscall.SysProcAttr{
		Unshareflags: syscall.CLONE_NEWNET,
	}

	if err := cmd.Start(); err != nil {
		return 0, err
	}

	go func() {
		if err := cmd.Wait(); err != nil {
			log.Printf("child process %d exited: %v", cmd.Process.Pid, err)
		}
	}()

	return cmd.Process.Pid, nil
}
