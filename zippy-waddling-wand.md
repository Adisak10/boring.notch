# Implementation Plan: Clipboard + Claude Usage Features

## Context
Adding two new features to boring.notch:
1. **Clipboard History** — on-demand view of clipboard history, positioned as a tab alongside Shelf
2. **Claude Usage Monitor** — real-time API usage stats (5-hour & 7-day utilization), positioned next to Camera in the notch display

Both features follow existing architectural patterns in the codebase and reuse proven patterns from Shelf and WebcamManager implementations.

---

## Feature 1: Clipboard History

### Requirements
- **Display**: Recent clipboard items on-demand (fetch when user taps Clipboard tab)
- **Integration**: Add as a tab in the tab bar (similar to `.shelf` view in coordinator)
- **Data**: Monitor macOS system clipboard, store history locally
- **UX**: Scrollable list, click to copy/restore, delete individual items
- **Storage**: Persist to disk (~50 items limit, FIFO)

### Architecture Overview
Will follow **Shelf** pattern exactly:

```
components/Clipboard/
├── Models/
│   └── ClipboardItem.swift          # (date, content, type [text/image], id, timestamp)
├── ViewModels/
│   ├── ClipboardStateViewModel.swift # Singleton, @Published items, auto-save
│   ├── ClipboardItemViewModel.swift  # Per-item state (thumbnail, actions)
│   └── ClipboardSelectionModel.swift # Multi-select support
├── Views/
│   ├── ClipboardView.swift           # Main scrollable list view
│   └── ClipboardItemView.swift       # Individual item card
└── Services/
    ├── ClipboardMonitorService.swift # NSPasteboard observation
    ├── ClipboardPersistenceService.swift # JSON serialization
    └── ClipboardHistoryService.swift  # History deduplication + limit enforcement
```

### Key Implementation Details

**1. ClipboardItem Model**
```swift
struct ClipboardItem: Identifiable, Codable {
    let id: UUID
    let content: ClipboardContent  // enum: text(String), image(Data)
    let timestamp: Date
    let preview: String            // truncated preview for display
}
```

**2. ClipboardMonitorService** (new)
- Observer on `NSPasteboard.general` via `NSPasteboard.availableTypeNotification`
- Debounce rapid changes (0.5s)
- Extract text/image types only
- Call `ClipboardStateViewModel.add()` on new content

**3. ClipboardStateViewModel**
- Singleton (`.shared`)
- `@Published var items: [ClipboardItem]`
- `didSet` observer → auto-persist via `ClipboardPersistenceService`
- Deduplication via `identityKey` (hash of content + type)
- Limit to 50 items (FIFO removal when exceeded)
- Cleanup task on init to start monitoring

**4. Persistence**
- Location: `~/Library/Application Support/boringNotch/Clipboard/history.json`
- Same pattern as Shelf: graceful loading with fallback
- Automatic save on items change

**5. Views**
- `ClipboardView`: Horizontal scrolling list (similar to ShelfView layout)
- `ClipboardItemView`: Card showing preview + timestamp + delete button
- Long-press to copy, click to expand, swipe to delete

### Integration Points
1. **Coordinator**: Add `.clipboard` case to `NotchViews` enum
2. **ContentView**: Add case to switch statement
3. **TabSelectionView**: Add Clipboard tab button
4. **Settings**: Add toggle `Defaults[.clipboardEnabled]` + history limit preference
5. **Startup**: Initialize `ClipboardMonitorService` in AppDelegate

### Reused Patterns
- `ShelfStateViewModel` → `ClipboardStateViewModel` (singleton, @Published, auto-save)
- `ShelfItemView` → `ClipboardItemView` (card layout, actions)
- `ShelfPersistenceService` → `ClipboardPersistenceService` (JSON codec, Codable)
- `NSPasteboard` monitoring (similar to `NSScreen` observation in AppDelegate)

---

## Feature 2: Claude Usage Monitor

### Requirements
- **Display**: Both 5-hour AND 7-day utilization percentages in tabbed layout
- **Data Source**: Fetch from Anthropic OAuth API using macOS Keychain token
- **Position**: Next to Camera feature (right side of notch when open)
- **Update Frequency**: On-demand poll + periodic refresh (every 5 minutes or on notch open)
- **Error State**: Show "Not logged in" message + link to Settings if no token

### Architecture Overview
New manager + simple card view (simpler than Shelf/Camera):

```
components/ClaudeUsage/
├── Models/
│   └── UsageData.swift              # (five_hour_pct, seven_day_pct, resets_at)
├── ViewModels/
│   └── ClaudeUsageViewModel.swift    # Manager (@Published, fetch logic)
├── Views/
│   └── ClaudeUsageView.swift         # Card with tabbed utilization display
└── Services/
    └── AnthropicUsageService.swift   # OAuth API + Keychain integration
```

### Key Implementation Details

**1. AnthropicUsageService** (new)
- Fetch from `https://api.anthropic.com/api/oauth/usage` endpoint
- Extract access token from macOS Keychain:
  ```swift
  security find-generic-password -s "Claude Code-credentials" -w
  ```
- Handle token expiry gracefully (skip if <30s remaining)
- Parse JSON response → `UsageData` struct
- Implement caching (don't fetch too frequently, respect API limits)

**2. ClaudeUsageViewModel**
- `@Published var usageData: UsageData?`
- `@Published var isLoading: Bool`
- `@Published var error: String?` (for error display)
- `func refresh()` → async call to `AnthropicUsageService`
- Auto-refresh on timer (5 minute interval when app active)

**3. ClaudeUsageView**
- Two-tab layout: "5hr" and "7day" tabs
- Each tab shows: `45% / 5hr` or `65% / 7d`
- Progress ring/bar visual
- "Not logged in" state with Settings button
- Loading spinner during fetch
- Tap to manually refresh

**4. Error Handling**
- No Keychain token → "Log in via Claude app or Claude Code CLI first"
- API 401/403 → "Authentication failed, please re-login"
- Network timeout → "Unable to fetch usage (check internet)"
- Show cached value if available
- Retry button for manual refresh

**5. Integration with Keychain**
- Use `Security.framework` to query: `find-generic-password -s "Claude Code-credentials"`
- Parse JSON from Keychain password field
- Extract `oauth.accessToken` or `accessToken`
- Do NOT store tokens in app defaults (use Keychain only, read-only)

### Integration Points
1. **ContentView**: Add `ClaudeUsageView` next to `CameraPreviewView` in NotchHomeView HStack
2. **BoringViewModel**: Add `@Published usageData` property (or observe via environment)
3. **AppDelegate**: Initialize `ClaudeUsageViewModel.shared` on app start
4. **Timer**: Start refresh timer on app launch, pause on window close
5. **Settings**: Add toggle `Defaults[.showClaudeUsage]` (default: false)

### Reused Patterns
- `WebcamManager` → `ClaudeUsageViewModel` (singleton, @Published, periodic refresh)
- NSView layout pattern from Camera (side-by-side horizontal positioning)
- Error state handling (similar to permission-denied camera state)

---

## Implementation Order (Recommended)

### Phase 1: Clipboard (Simpler, no external API)
1. Create ClipboardItem model + tests
2. Create ClipboardStateViewModel + ClipboardMonitorService
3. Create persistence service
4. Create views (ClipboardView, ClipboardItemView)
5. Integrate into coordinator + ContentView
6. Add Settings toggle

### Phase 2: Claude Usage (Requires external API)
1. Create AnthropicUsageService (Keychain + API fetch)
2. Create ClaudeUsageViewModel
3. Create views (tabbed layout)
4. Integrate next to Camera in NotchHomeView
5. Add Settings toggle
6. Test Keychain integration + error states

---

## File Locations & New Files

### Clipboard Feature
```
boringNotch/
└── components/
    └── Clipboard/
        ├── Models/
        │   └── ClipboardItem.swift
        ├── ViewModels/
        │   ├── ClipboardStateViewModel.swift
        │   ├── ClipboardItemViewModel.swift
        │   └── ClipboardSelectionModel.swift
        ├── Views/
        │   ├── ClipboardView.swift
        │   └── ClipboardItemView.swift
        └── Services/
            ├── ClipboardMonitorService.swift
            ├── ClipboardPersistenceService.swift
            └── ClipboardHistoryService.swift
```

**Modified Files:**
- `models/Constants.swift` — add `.clipboardEnabled`, `.clipboardHistoryLimit` keys
- `BoringViewCoordinator.swift` — add `.clipboard` case to `NotchViews`
- `ContentView.swift` — add switch case for `.clipboard`
- `components/Settings/SettingsView.swift` — add Clipboard section
- `boringNotchApp.swift` AppDelegate — initialize `ClipboardMonitorService`

### Claude Usage Feature
```
boringNotch/
└── components/
    └── ClaudeUsage/
        ├── Models/
        │   └── UsageData.swift
        ├── ViewModels/
        │   └── ClaudeUsageViewModel.swift
        ├── Views/
        │   └── ClaudeUsageView.swift
        └── Services/
            └── AnthropicUsageService.swift
```

**Modified Files:**
- `models/Constants.swift` — add `.showClaudeUsage` key
- `components/Notch/NotchHomeView.swift` — add `ClaudeUsageView` next to Camera (conditional rendering)
- `components/Settings/SettingsView.swift` — add Claude Usage section
- `boringNotchApp.swift` AppDelegate — initialize timer for periodic refresh

---

## Verification & Testing

### Clipboard Feature
1. ✅ Launch app, copy text/image multiple times → verify items in Clipboard tab
2. ✅ Kill app, relaunch → verify history persisted
3. ✅ Click item → verify copy to system clipboard
4. ✅ Delete item → verify removed from list
5. ✅ Exceed 50 items → verify FIFO removal
6. ✅ Duplicate detection → verify same content not added twice
7. ✅ Toggle in Settings → verify appears/disappears from tab bar

### Claude Usage Feature
1. ✅ (Requires Claude app logged in) → verify Keychain token found + usage displayed
2. ✅ Logout from Claude app → verify "Not logged in" state
3. ✅ Tap refresh button → verify API call + new data displayed
4. ✅ Network offline → verify graceful error message
5. ✅ Click Settings link → verify opens Settings app or Settings window
6. ✅ 5-hour tab → verify percentage + "resets at" time
7. ✅ 7-day tab → verify percentage + "resets at" time
8. ✅ Auto-refresh every 5 min → verify (check timestamps)
9. ✅ Toggle in Settings → verify appears/disappears from notch

### Edge Cases
- Clipboard with very long text → truncate in preview
- Clipboard with binary image data → show thumbnail or placeholder
- Claude Usage API returns rate-limited error → show appropriate message
- Anthropic API schema changes → graceful fallback to "unable to fetch"

---

## Technical Notes

### Clipboard Monitoring
- Use `NSPasteboard.availableTypeNotification` (lightweight, non-blocking)
- Debounce with 0.5s delay to avoid storing every keystroke
- Support text + image types; exclude other types

### OAuth API Endpoint
- Endpoint: `https://api.anthropic.com/api/oauth/usage`
- Header: `Authorization: Bearer {accessToken}`
- Beta header: `anthropic-beta: oauth-2025-04-20`
- Timeout: 15 seconds
- Response schema: `{ five_hour: { utilization: 0.45, resets_at: "..." }, seven_day: { ... } }`

### Keychain Query
```bash
security find-generic-password -s "Claude Code-credentials" -w
```
Returns JSON with structure: `{ claudeAiOauth: { accessToken, expiresAt } }`

### Concurrency Model
- Clipboard monitoring: MainActor (NSPasteboard observer)
- API fetch: async/await (background thread)
- Keychain queries: blocking (fast, minimal overhead)
- UI updates: MainActor via @Published

---

## Dependencies & Imports

**Clipboard:**
- `Foundation` (UUID, JSONEncoder, NotificationCenter)
- `Defaults` (user preferences)
- `AppKit` (NSPasteboard, NSImage)

**Claude Usage:**
- `Foundation` (URLSession, JSONDecoder, Timer)
- `Security` (Keychain API)
- `Defaults` (user preferences)

No new external dependencies required (all built-in or already used).

---

## Rollback Plan (if needed)

- Clipboard: Delete `components/Clipboard/` folder, remove `.clipboard` case from coordinator, revert Settings/Constants changes
- Claude Usage: Delete `components/ClaudeUsage/` folder, revert NotchHomeView/Settings/Constants changes
- Both: Clean up `~/Library/Application Support/boringNotch/Clipboard/` directory

---

## Notes
- Start with Clipboard (easier, no external API) to establish pattern
- Claude Usage can be built in parallel or after Clipboard is merged
- Both features are optional (feature flags in Settings) — won't break existing functionality
- Follow existing code style: MainActor, weak captures in closures, cleanup in deinit
