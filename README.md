# note

Small CLI for appending and managing notes stored in `.note.md` files.

## Quick start
1. Run `note install [directory]` to link the script somewhere on your `PATH` and create `<directory>/.note.md`. Without an argument it falls back to `~/.note.md`.
2. In any directory, run `note` (or `note -t "title"`) to create an entry. Commands like `note list`, `note show <id>`, `note edit`, `note pop`, and `note search <query>` operate on the nearest `.note.md`.
3. If no `.note.md` exists in the current directory, the tool uses `NOTE_FILE` when set or `~/.note.md` as the fallback.

## Requirements
- POSIX shell with common core utilities (`awk`, `tr`, `mktemp`, `dirname`, `basename`).
- A text editor available via `$VISUAL`, `$EDITOR`, or `vim`.
