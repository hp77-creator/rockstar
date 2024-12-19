package cmd

import (
	"clipboard-manager/internal/storage"
	"clipboard-manager/pkg/types"
	"fmt"
	"os"
	"os/exec"
	"runtime"
	"strings"
	"text/tabwriter"
	"time"

	"github.com/progrium/darwinkit/macos/appkit"
)

// SearchCommand handles searching and pasting clipboard history
type SearchCommand struct {
	store storage.SearchService
}

// NewSearchCommand creates a new search command
func NewSearchCommand(store storage.SearchService) *SearchCommand {
	return &SearchCommand{store: store}
}

// Search searches clipboard history and displays results
func (c *SearchCommand) Search(query string, limit int) error {
	opts := storage.SearchOptions{
		Query:     query,
		Limit:     limit,
		SortBy:    "last_used",
		SortOrder: "desc",
	}

	results, err := c.store.Search(opts)
	if err != nil {
		return fmt.Errorf("search failed: %w", err)
	}

	if len(results) == 0 {
		fmt.Println("No results found")
		return nil
	}

	// Create tabwriter for aligned output
	w := tabwriter.NewWriter(os.Stdout, 0, 0, 2, ' ', 0)
	fmt.Fprintln(w, "ID\tType\tSource\tPreview\tLast Used")
	fmt.Fprintln(w, "--\t----\t------\t-------\t---------")

	for _, result := range results {
		preview := getPreview(result.Clip)
		lastUsed := result.LastUsed.Format(time.RFC822)
		fmt.Fprintf(w, "%s\t%s\t%s\t%s\t%s\n",
			result.Clip.ID,
			result.Clip.Type,
			result.Clip.Metadata.SourceApp,
			preview,
			lastUsed,
		)
	}
	w.Flush()

	return nil
}

// Paste copies the content with given ID to clipboard and simulates Command+V
func (c *SearchCommand) Paste(id string) error {
	// Get the clip
	results, err := c.store.Search(storage.SearchOptions{
		Query: id,
		Limit: 1,
	})
	if err != nil {
		return fmt.Errorf("failed to get clip: %w", err)
	}

	if len(results) == 0 {
		return fmt.Errorf("no clip found with ID: %s", id)
	}

	clip := results[0].Clip

	// Get pasteboard
	pb := appkit.Pasteboard_GeneralPasteboard()

	// Set content based on type
	switch clip.Type {
	case "text":
		pb.SetStringForType(string(clip.Content), appkit.PasteboardType("public.utf8-plain-text"))
	case "image/png":
		pb.SetDataForType(clip.Content, appkit.PasteboardType("public.png"))
	case "image/tiff":
		pb.SetDataForType(clip.Content, appkit.PasteboardType("public.tiff"))
	case "file":
		pb.SetStringForType(string(clip.Content), appkit.PasteboardType("public.file-url"))
	default:
		return fmt.Errorf("unsupported content type: %s", clip.Type)
	}

	// Simulate Command+V using osascript
	if runtime.GOOS == "darwin" {
		cmd := exec.Command("osascript", "-e", `
			tell application "System Events"
				keystroke "v" using command down
			end tell
		`)
		if err := cmd.Run(); err != nil {
			return fmt.Errorf("failed to simulate paste: %w", err)
		}
	}

	return nil
}

// getPreview returns a preview string for a clip
func getPreview(clip *types.Clip) string {
	const maxPreviewLength = 50

	switch clip.Type {
	case "text":
		text := string(clip.Content)
		text = strings.ReplaceAll(text, "\n", " ")
		if len(text) > maxPreviewLength {
			text = text[:maxPreviewLength] + "..."
		}
		return text
	case "image/png", "image/tiff":
		return fmt.Sprintf("[Image %d bytes]", len(clip.Content))
	case "file":
		return fmt.Sprintf("[File URL: %s]", string(clip.Content))
	default:
		return fmt.Sprintf("[%s %d bytes]", clip.Type, len(clip.Content))
	}
}
