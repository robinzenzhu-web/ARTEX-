package server

import (
	"bytes"
	"context"
	"encoding/json"
	"fmt"
	"io"
	"net/http"
	"net/url"
	"os"
	"regexp"
	"strings"
	"time"

	actool "github.com/Autumn-27/norma/tool"
)

// ScopeSentry's MCP `create_scan_task` only inserts a task row; it never
// triggers execution (its REST API needs a separate POST /api/task/start, and
// that endpoint only accepts a JWT — not the MCP X-API-Key). An agent therefore
// creates a task and polls forever on status=1.
//
// autoStartTool wraps that one MCP tool so the task is started right after a
// successful create. Credentials come from the environment; when they are
// absent the wrapper is a pure pass-through, so behaviour is unchanged for
// deployments that don't opt in.

const (
	envSSUser = "ARTEX_SCOPESENTRY_USER"
	envSSPass = "ARTEX_SCOPESENTRY_PASS"
)

var taskIDRe = regexp.MustCompile(`"id"\s*:\s*"([0-9a-fA-F]{24})"`)

// autoStartTool decorates an MCP tool and starts the created scan task.
type autoStartTool struct {
	actool.CoreTool
	restBase string
	user     string
	pass     string
}

// wrapScopeSentryAutoStart wraps mcp__ScopeSentry__create_scan_task when
// credentials are configured. mcpURL is the server's MCP endpoint.
func wrapScopeSentryAutoStart(t actool.CoreTool, srvName, mcpURL string) actool.CoreTool {
	if t == nil || srvName != "ScopeSentry" {
		return t
	}
	if t.Name() != "mcp__ScopeSentry__create_scan_task" {
		if strings.Contains(t.Name(), "create_scan_task") {
			fmt.Printf("[scopesentry] tool name mismatch: %q\n", t.Name())
		}
		return t
	}
	user := strings.TrimSpace(os.Getenv(envSSUser))
	pass := os.Getenv(envSSPass)
	if user == "" || pass == "" {
		fmt.Printf("[scopesentry] auto-start disabled: credentials not set\n")
		return t // opt-in only
	}
	base, ok := restBaseFromMCP(mcpURL)
	if !ok {
		fmt.Printf("[scopesentry] auto-start disabled: bad mcp url %q\n", mcpURL)
		return t
	}
	fmt.Printf("[scopesentry] auto-start armed: rest=%s user=%s\n", base, user)
	return &autoStartTool{CoreTool: t, restBase: base, user: user, pass: pass}
}

// restBaseFromMCP turns http://host:8082/mcp into http://host:8082.
func restBaseFromMCP(mcpURL string) (string, bool) {
	u, err := url.Parse(strings.TrimSpace(mcpURL))
	if err != nil || u.Scheme == "" || u.Host == "" {
		return "", false
	}
	return u.Scheme + "://" + u.Host, true
}

func (w *autoStartTool) Call(ctx context.Context, input json.RawMessage, tc *actool.ToolContext) (actool.Result, error) {
	res, err := w.CoreTool.Call(ctx, input, tc)
	if err != nil || res.IsError {
		fmt.Printf("[scopesentry] create_scan_task errored: err=%v isErr=%v\n", err, res.IsError)
		return res, err
	}
	id := extractTaskID(res)
	fmt.Printf("[scopesentry] create_scan_task returned id=%q\n", id)
	if id == "" {
		return res, nil
	}
	// Fire and forget: the agent must not block on the REST round-trip.
	go func() {
		sctx, cancel := context.WithTimeout(context.Background(), 20*time.Second)
		defer cancel()
		if serr := w.startTask(sctx, id); serr != nil {
			fmt.Printf("[scopesentry] auto-start %s failed: %v\n", id, serr)
			return
		}
		fmt.Printf("[scopesentry] auto-started task %s\n", id)
	}()
	return res, nil
}

func extractTaskID(res actool.Result) string {
	raw, err := json.Marshal(res.Content)
	if err != nil {
		return ""
	}
	// The MCP tool result carries the JSON payload as a text block, so after
	// marshalling the inner quotes are escaped (\"id\": \"...\"). Unescape before
	// matching, otherwise the regex never sees a plain "id".
	s := strings.ReplaceAll(string(raw), `\"`, `"`)
	m := taskIDRe.FindStringSubmatch(s)
	if len(m) < 2 {
		return ""
	}
	return m[1]
}

func (w *autoStartTool) startTask(ctx context.Context, id string) error {
	token, err := w.login(ctx)
	if err != nil {
		return fmt.Errorf("login: %w", err)
	}
	body, _ := json.Marshal(map[string]any{"ids": []string{id}})
	req, err := http.NewRequestWithContext(ctx, http.MethodPost,
		w.restBase+"/api/task/start", bytes.NewReader(body))
	if err != nil {
		return err
	}
	req.Header.Set("Content-Type", "application/json")
	req.Header.Set("Authorization", "Bearer "+token)
	resp, err := http.DefaultClient.Do(req)
	if err != nil {
		return err
	}
	defer resp.Body.Close()
	raw, _ := io.ReadAll(io.LimitReader(resp.Body, 4096))
	if resp.StatusCode < 200 || resp.StatusCode >= 300 {
		return fmt.Errorf("start status %d: %s", resp.StatusCode, strings.TrimSpace(string(raw)))
	}
	return nil
}

func (w *autoStartTool) login(ctx context.Context) (string, error) {
	body, _ := json.Marshal(map[string]string{"username": w.user, "password": w.pass})
	req, err := http.NewRequestWithContext(ctx, http.MethodPost,
		w.restBase+"/api/user/login", bytes.NewReader(body))
	if err != nil {
		return "", err
	}
	req.Header.Set("Content-Type", "application/json")
	resp, err := http.DefaultClient.Do(req)
	if err != nil {
		return "", err
	}
	defer resp.Body.Close()
	raw, _ := io.ReadAll(io.LimitReader(resp.Body, 8192))
	if resp.StatusCode != http.StatusOK {
		return "", fmt.Errorf("login status %d", resp.StatusCode)
	}
	var out struct {
		Data struct {
			AccessToken string `json:"access_token"`
		} `json:"data"`
	}
	if err := json.Unmarshal(raw, &out); err != nil {
		return "", err
	}
	if out.Data.AccessToken == "" {
		return "", fmt.Errorf("no access_token in login response")
	}
	return out.Data.AccessToken, nil
}
