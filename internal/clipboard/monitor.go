package clipboard

import (
    "clipboard-manager/pkg/types"
    "github.com/atotto/clipboard"
    "net/http"
)

func readClipboard() (types.Clip, error) {
    data, err := clipboard.ReadAll()
    if err != nil {
        return types.Clip{}, err
    }

    // Convert string to raw bytes
    raw := []byte(data)
    contentType := http.DetectContentType(raw)

    if contentType == "image/png" || contentType == "image/jpeg" || contentType == "image/gif" {
        // Image Clip
        return types.Clip{
            Type:    "image",
            Content: raw,
        }, nil
    }

    // Default: text clip
    return types.Clip{
        Type:    "text",
        Content: raw,
    }, nil
}

