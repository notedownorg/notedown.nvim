# User Commands

### `:NotedownWorkspaceStatus`

Check the workspace status for the current buffer:

```
Notedown Workspace Status:
  File: /Users/username/notes/ideas.md
  In Notedown Workspace: Yes
  Should Use Notedown Parser: Yes
  Matched Workspace: /Users/username/notes
  Detection Method: Auto-detected (.notedown directory)
```

### `:NotedownReload`

Reload the plugin and restart the LSP server:
- Stops existing LSP clients
- Clears module cache
- Reloads configuration
- Restarts language server

### `:NotedownMoveUp`

Move the current list item up (swaps with previous sibling).

### `:NotedownMoveDown`

Move the current list item down (swaps with next sibling).

### `:NotedownExecuteCode [language]`

Execute code blocks in the current document:
- Without arguments: Executes all code blocks
- With language argument (e.g., `:NotedownExecuteCode go`): Executes only blocks of that language

