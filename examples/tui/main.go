package cmd

import (
	"clipboard-manager/internal/storage"
	"fmt"
	"github.com/gdamore/tcell/v2"
	"strings"
)

type InteractiveMode struct {
	store      storage.SearchService
	screen     tcell.Screen
	results    []storage.SearchResult
	selected   int
	offset     int
	searchMode bool
	searchText string
}

func NewInteractiveMode(store storage.SearchService) (*InteractiveMode, error) {
	screen, err := tcell.NewScreen()
	if err != nil {
		return nil, fmt.Errorf("failed to create screen: %w", err)
	}

	if err := screen.Init(); err != nil {
		return nil, fmt.Errorf("failed to initialize screen: %w", err)
	}

	// Set default style
	screen.SetStyle(tcell.StyleDefault.
		Background(tcell.ColorReset).
		Foreground(tcell.ColorReset))

	return &InteractiveMode{
		store:    store,
		screen:   screen,
		selected: 0,
		offset:   0,
	}, nil
}

func (im *InteractiveMode) Run() error {
	defer im.screen.Fini()

	if err := im.loadResults(""); err != nil {
		return err
	}

	for {
		im.draw()

		switch ev := im.screen.PollEvent().(type) {
		case *tcell.EventResize:
			im.screen.Sync()
		case *tcell.EventKey:
			if im.searchMode {
				switch ev.Key() {
				case tcell.KeyEscape:
					im.searchMode = false
					im.searchText = ""
					if err := im.loadResults(""); err != nil {
						return err
					}
				case tcell.KeyEnter:
					im.searchMode = false
					if err := im.loadResults(im.searchText); err != nil {
						return err
					}
				case tcell.KeyBackspace, tcell.KeyBackspace2:
					if len(im.searchText) > 0 {
						im.searchText = im.searchText[:len(im.searchText)-1]
					}
				case tcell.KeyRune:
					im.searchText += string(ev.Rune())
				}
				continue
			}

			switch ev.Key() {
			case tcell.KeyEscape, tcell.KeyCtrlC:
				return nil
			case tcell.KeyUp, tcell.KeyCtrlP:
				im.moveSelection(-1)
			case tcell.KeyDown, tcell.KeyCtrlN:
				im.moveSelection(1)
			case tcell.KeyHome, tcell.KeyCtrlA:
				im.selected = 0
			case tcell.KeyEnd, tcell.KeyCtrlE:
				im.selected = len(im.results) - 1
			case tcell.KeyPgUp:
				im.moveSelection(-10)
			case tcell.KeyPgDn:
				im.moveSelection(10)
			case tcell.KeyEnter, tcell.KeyCtrlV:
				if len(im.results) > 0 {
					return im.pasteSelected()
				}
			case tcell.KeyRune:
				switch ev.Rune() {
				case 'j':
					im.moveSelection(1)
				case 'k':
					im.moveSelection(-1)
				case 'g':
					im.selected = 0
				case 'G':
					im.selected = len(im.results) - 1
				case '/':
					im.searchMode = true
					im.searchText = ""
				case 'q':
					return nil
				}
			}
		}
	}
}

func (im *InteractiveMode) loadResults(query string) error {
	results, err := im.store.Search(storage.SearchOptions{
		Query:     query,
		SortBy:    "last_used",
		SortOrder: "desc",
	})
	if err != nil {
		return fmt.Errorf("failed to load clips: %w", err)
	}
	im.results = results
	im.selected = 0
	im.offset = 0
	return nil
}

func (im *InteractiveMode) pasteSelected() error {
	selected := im.results[im.selected]
	searchCmd := NewSearchCommand(im.store)
	im.screen.Fini()
	return searchCmd.Paste(selected.Clip.ID)
}

func (im *InteractiveMode) moveSelection(delta int) {
	im.selected += delta
	if im.selected < 0 {
		im.selected = 0
	}
	if im.selected >= len(im.results) {
		im.selected = len(im.results) - 1
	}

	// Adjust offset for scrolling
	_, height := im.screen.Size()
	visibleHeight := height - 5 // Account for header and footer

	if im.selected-im.offset >= visibleHeight {
		im.offset = im.selected - visibleHeight + 1
	} else if im.selected < im.offset {
		im.offset = im.selected
	}
}

func (im *InteractiveMode) draw() {
	im.screen.Clear()
	width, height := im.screen.Size()

	// Draw header
	headerStyle := tcell.StyleDefault.Reverse(true)
	header := " Clipboard History "
	drawStringCenter(im.screen, 0, header, headerStyle)

	// Draw help text
	helpStyle := tcell.StyleDefault.Foreground(tcell.ColorYellow)
	help := "↑/k:Up  ↓/j:Down  Enter:Paste  g/G:Top/Bottom  /:Search  Esc/q:Quit"
	drawStringCenter(im.screen, 1, help, helpStyle)

	// Draw search bar if in search mode
	if im.searchMode {
		searchStyle := tcell.StyleDefault.Reverse(true)
		searchPrompt := fmt.Sprintf(" Search: %s█", im.searchText)
		drawString(im.screen, 0, 2, searchPrompt, searchStyle)
	} else {
		// Draw separator
		drawString(im.screen, 0, 2, strings.Repeat("─", width), tcell.StyleDefault)
	}

	// Draw results
	visibleHeight := height - 5
	endIdx := im.offset + visibleHeight
	if endIdx > len(im.results) {
		endIdx = len(im.results)
	}

	for i, result := range im.results[im.offset:endIdx] {
		y := i + 3
		style := tcell.StyleDefault

		if i+im.offset == im.selected {
			style = style.Reverse(true)
		}

		preview := getPreview(result.Clip)
		if len(preview) > width-20 {
			preview = preview[:width-23] + "..."
		}

		line := fmt.Sprintf(" %-3s  %-10s  %s",
			result.Clip.ID,
			truncate(result.Clip.Type, 10),
			preview,
		)
		drawString(im.screen, 0, y, line, style)
	}

	// Draw footer
	if len(im.results) > 0 {
		status := fmt.Sprintf(" %d/%d ", im.selected+1, len(im.results))
		drawString(im.screen, width-len(status), height-1, status, tcell.StyleDefault)
	}

	im.screen.Show()
}

func drawString(s tcell.Screen, x, y int, str string, style tcell.Style) {
	for i, r := range str {
		s.SetContent(x+i, y, r, nil, style)
	}
}

func drawStringCenter(s tcell.Screen, y int, str string, style tcell.Style) {
	w, _ := s.Size()
	x := (w - len(str)) / 2
	if x < 0 {
		x = 0
	}
	drawString(s, x, y, str, style)
}

func truncate(s string, maxLen int) string {
	if len(s) <= maxLen {
		return s + strings.Repeat(" ", maxLen-len(s))
	}
	return s[:maxLen-3] + "..."
}
