#!/bin/sh
set -eu

separator='----- x ------'
note_file=""
default_note_file="$HOME/.note.md"
editor="${VISUAL:-${EDITOR:-vim}}"

if [ -t 1 ]; then
  color_id=$(printf '\033[37m')
  color_title=$(printf '\033[36m')
  color_match=$(printf '\033[33m')
  color_reset=$(printf '\033[0m')
else
  color_id=""
  color_title=""
  color_match=""
  color_reset=""
fi

usage() {
  cat <<'USAGE' >&2
Usage:
  note <title>
  note -i <id>
  note show <title>
  note show -i <id>
  note pop
  note list
  note search <query>
  note install [path]
USAGE
  exit 1
}

resolve_note_file() {
  cwd_note="$PWD/.note.md"
  if [ -f "$cwd_note" ]; then
    note_file="$cwd_note"
    return 0
  fi

  if [ -n "${NOTE_FILE:-}" ]; then
    note_file="$NOTE_FILE"
    [ -f "$note_file" ] && return 0
    return 1
  fi

  note_file="$default_note_file"
  if [ -f "$note_file" ]; then
    return 0
  fi

  note_file=""
  return 1
}

require_note_file() {
  if [ -n "$note_file" ]; then
    return 0
  fi

  if resolve_note_file; then
    return 0
  fi

  if [ -n "${NOTE_FILE:-}" ]; then
    echo "No .note.md file found here or at ${NOTE_FILE}." >&2
  else
    echo "No .note.md file found here or at $default_note_file." >&2
  fi
  echo 'Run "note install [path]" to create one.' >&2
  exit 1
}

rand_id() {
  LC_ALL=C tr -dc '0-9a-f' </dev/urandom | head -c6
}

unique_id() {
  id="$(rand_id)"
  while fetch_record "$id" >/dev/null 2>&1; do
    id="$(rand_id)"
  done
  printf '%s' "$id"
}

fetch_record() {
  target="$1"
  [ -f "$note_file" ] || return 1
  awk -v sep="$separator" -v target="$target" '
    BEGIN { RS = sep "\n"; ORS=""; last=""; found=0 }
    NR>1 && NF {
      n = split($0, lines, "\n")
      rec_id=""; rec_title=""; body=""
      for (i=1; i<=n; i++) {
        line = lines[i]
        if (rec_id=="" && line ~ /^id: /) { rec_id = substr(line, 5); continue }
        if (rec_title=="" && line ~ /^title: /) { rec_title = substr(line, 8); continue }
        body = body (body=="" ? "" : "\n") line
      }
      if (target=="") {
        last = rec_id "\037" rec_title "\037" body
      } else if (rec_id == target) {
        print rec_id "\037" rec_title "\037" body
        found=1
        exit
      }
    }
    END {
      if (target=="") {
        if (last != "") { print last; exit 0 } else exit 1
      } else {
        if (found) exit 0; else exit 1
      }
    }
  ' "$note_file"
}

fetch_record_by_title() {
  target="$1"
  [ -f "$note_file" ] || return 1
  awk -v sep="$separator" -v target="$target" '
    BEGIN { RS = sep "\n"; ORS=""; found=0 }
    NR>1 && NF {
      n = split($0, lines, "\n")
      rec_id=""; rec_title=""; body=""
      for (i=1; i<=n; i++) {
        line = lines[i]
        if (rec_id=="" && line ~ /^id: /) { rec_id = substr(line, 5); continue }
        if (rec_title=="" && line ~ /^title: /) { rec_title = substr(line, 8); continue }
        body = body (body=="" ? "" : "\n") line
      }
      if (rec_title == target) {
        print rec_id "\037" rec_title "\037" body
        found=1
        exit
      }
    }
    END { if (found) exit 0; else exit 1 }
  ' "$note_file"
}

split_record() {
  record="$1"
  oldifs=$IFS
  IFS=$'\037'
  set -- $record
  IFS=$oldifs
  note_id="$1"
  note_title="$2"
  note_body="$3"
}

ensure_newline() {
  file="$1"
  [ -s "$file" ] || return 0
  last_char=$(tail -c1 "$file" 2>/dev/null || true)
  nl=$(printf '\n')
  [ "$last_char" = "$nl" ] || printf '\n' >>"$file"
}

emit_record() {
  printf '%s\n' "$separator"
  printf 'id: %s\n' "$1"
  printf 'title: %s\n' "$2"
  if [ -n "$3" ]; then
    printf '%s\n' "$3"
  else
    printf '\n'
  fi
}

append_record() {
  ensure_newline "$note_file"
  emit_record "$1" "$2" "$3" >>"$note_file"
}

rewrite_without_last() {
  awk -v sep="$separator" '
    BEGIN { RS = sep "\n"; ORS="" }
    NR>1 && NF {
      rec[++count] = $0
    }
    END {
      for (i=1; i<count; i++) {
        printf("%s\n", sep)
        printf("%s\n", rec[i])
      }
    }
  ' "$note_file"
}

rewrite_with_updated_record() {
  target_id="$1"
  new_title="$2"
  body_file="$3"

  tmpfile=$(mktemp)
  trap 'rm -f "$tmpfile"' EXIT INT TERM
  if awk -v sep="$separator" -v target="$target_id" \
        -v new_title="$new_title" -v body_file="$body_file" '
        function emit_updated(id,    line, body) {
          printf("%s\n", sep)
          printf("id: %s\n", id)
          printf("title: %s\n", new_title)
          body=""
          while ((getline line < body_file) > 0) {
            if (body == "")
              body = line
            else
              body = body "\n" line
          }
          close(body_file)
          if (length(body))
            printf("%s\n", body)
          else
            printf("\n")
        }
        BEGIN { RS = sep "\n"; ORS=""; found=0 }
        NR>1 && NF {
          n = split($0, lines, "\n")
          rec_id=""
          for (i=1; i<=n; i++) {
            line = lines[i]
            if (rec_id=="" && line ~ /^id: /) {
              rec_id = substr(line, 5)
              break
            }
          }
          if (rec_id == target) {
            emit_updated(rec_id)
            found=1
          } else {
            printf("%s\n%s", sep, $0)
          }
        }
        END {
          if (!found) exit 1
        }
      ' "$note_file" >"$tmpfile"; then
    mv "$tmpfile" "$note_file"
    trap - EXIT INT TERM
    return 0
  else
    status=$?
    rm -f "$tmpfile"
    trap - EXIT INT TERM
    return $status
  fi
}

print_note() {
  printf '%sid: %s%s\n' "$color_id" "$note_id" "$color_reset"
  printf '%stitle: %s%s\n\n' "$color_title" "$note_title" "$color_reset"
  [ -n "$note_body" ] && printf '%s\n' "$note_body"
}

create_note() {
  title="${1:-}"

  tmp=$(mktemp)
  trap 'rm -f "$tmp"' EXIT INT TERM
  "$editor" "$tmp"
  content=$(cat "$tmp")
  trap - EXIT INT TERM
  rm -f "$tmp"
  [ -n "$content" ] || { echo 'Note not saved (empty).' >&2; return 1; }

  id=$(unique_id)
  append_record "$id" "$title" "$content"
  printf 'Saved note %s%s%s\n' "$color_id" "$id" "$color_reset"
}

show_note() {
  use_id=0
  OPTIND=1
  while getopts ':i' opt; do
    case "$opt" in
      i) use_id=1 ;;
      *) usage ;;
    esac
  done
  shift $((OPTIND - 1))
  target="${1:-}"

  if [ "$use_id" -eq 1 ]; then
    record=$(fetch_record "$target") || { echo 'Note not found.' >&2; return 1; }
  else
    record=$(fetch_record_by_title "$target") || { echo 'Note not found.' >&2; return 1; }
  fi
  split_record "$record"
  print_note
}

open_note() {
  record="$1"
  split_record "$record"

  tmp=$(mktemp)
  trap 'rm -f "$tmp"' EXIT INT TERM
  printf '%s' "$note_body" >"$tmp"
  "$editor" "$tmp"

  if ! rewrite_with_updated_record "$note_id" "$note_title" "$tmp"; then
    echo 'Failed to update note.' >&2
    rm -f "$tmp"
    trap - EXIT INT TERM
    return 1
  fi
  rm -f "$tmp"
  trap - EXIT INT TERM
}

create_or_open() {
  title="$1"

  if record=$(fetch_record_by_title "$title" 2>/dev/null); then
    open_note "$record"
  else
    tmp=$(mktemp)
    trap 'rm -f "$tmp"' EXIT INT TERM
    "$editor" "$tmp"
    content=$(cat "$tmp")
    trap - EXIT INT TERM
    rm -f "$tmp"
    [ -n "$content" ] || { echo 'Note not saved (empty).' >&2; return 1; }

    id=$(unique_id)
    append_record "$id" "$title" "$content"
    printf 'Saved note %s%s%s\n' "$color_id" "$id" "$color_reset"
  fi
}

open_by_id() {
  target="$1"
  record=$(fetch_record "$target") || { echo 'Note not found.' >&2; return 1; }
  open_note "$record"
}

pop_note() {
  record=$(fetch_record "") || { echo 'No notes to pop.' >&2; return 1; }
  split_record "$record"
  tmpfile=$(mktemp)
  trap 'rm -f "$tmpfile"' EXIT INT TERM
  rewrite_without_last >"$tmpfile"
  mv "$tmpfile" "$note_file"
  trap - EXIT INT TERM
  print_note
}

list_notes() {
  [ -f "$note_file" ] || { echo 'No notes yet.' >&2; return 1; }
  awk -v sep="$separator" -v idc="$color_id" -v titlec="$color_title" -v reset="$color_reset" '
    BEGIN { RS = sep "\n"; ORS=""; any=0 }
    NR>1 && NF {
      n = split($0, lines, "\n")
      id=""; title=""; first=""
      for (i=1; i<=n; i++) {
        line = lines[i]
        if (id=="" && line ~ /^id: /) { id=substr(line,5); continue }
        if (title=="" && line ~ /^title: /) { title=substr(line,8); continue }
        if (first=="" && length(line) > 0) first=line
      }
      summary = (title!="") ? title : first
      if (summary=="") summary="(blank)"
      if (length(summary) > 60) summary = substr(summary,1,60)
      printf("%s%s%s %s%s%s\n", idc, id, reset, titlec, summary, reset)
      any=1
    }
    END { if (!any) exit 1 }
  ' "$note_file" || { echo 'No notes yet.' >&2; return 1; }
}

search_notes() {
  query="$1"
  [ -n "$query" ] || usage
  [ -f "$note_file" ] || { echo 'No notes yet.' >&2; return 1; }
  awk -v sep="$separator" -v q="$query" -v idc="$color_id" -v titlec="$color_title" -v matchc="$color_match" -v reset="$color_reset" '
    BEGIN { RS = sep "\n"; ORS=""; hits=0 }
    NR>1 && NF {
      n = split($0, lines, "\n")
      id=""; title=""
      lines_kept=0
      delete keep
      for (i=1; i<=n; i++) {
        line = lines[i]
        if (id=="" && line ~ /^id: /) { id=substr(line,5); continue }
        if (title=="" && line ~ /^title: /) { title=substr(line,8); continue }
        if (index(line, q)) {
          keep[++lines_kept] = line
        }
      }
      if (lines_kept) {
        printf("%s%s%s", idc, id, reset)
        if (title!="") printf(" %s%s%s", titlec, title, reset)
        printf("\n")
        for (i=1; i<=lines_kept; i++) printf("    %s%s%s\n", matchc, keep[i], reset)
        printf("\n")
        hits=1
      }
    }
    END { if (!hits) exit 1 }
  ' "$note_file" || { echo 'No matches.' >&2; return 1; }
}

resolve_install_note_path() {
  target_dir="$1"
  if [ -z "$target_dir" ]; then
    printf '%s\n' "$default_note_file"
    return 0
  fi

  case "$target_dir" in
    */) target_dir=${target_dir%/} ;;
  esac

  [ -n "$target_dir" ] || target_dir="/"

  printf '%s/.note.md\n' "$target_dir"
}

ensure_note_storage() {
  requested="$1"
  note_target=$(resolve_install_note_path "$requested")
  target_dir=$(dirname "$note_target")
  mkdir -p "$target_dir" || {
    echo "Unable to create directory $target_dir." >&2
    return 1
  }
  abs_dir=$(cd "$target_dir" && pwd)
  abs_target="$abs_dir/$(basename "$note_target")"

  if [ ! -f "$abs_target" ]; then
    if ! touch "$abs_target"; then
      echo "Unable to create $abs_target." >&2
      return 1
    fi
    printf 'Created note file -> %s%s%s\n' "$color_title" "$abs_target" "$color_reset"
  else
    printf 'Note file already exists -> %s%s%s\n' "$color_title" "$abs_target" "$color_reset"
  fi
}

install_note() {
  note_target_arg="${1-}"
  script_dir=$(cd "$(dirname "$0")" && pwd)
  script_path="$script_dir/$(basename "$0")"

  if [ ! -x "$script_path" ]; then
    chmod +x "$script_path" 2>/dev/null || {
      echo "Could not make $script_path executable." >&2
      return 1
    }
  fi

  oldifs=$IFS
  IFS=:
  target_dir=""
  for dir in $PATH; do
    [ -n "$dir" ] || continue
    case "$dir" in
      "$HOME"/*)
        if [ -d "$dir" ] && [ -w "$dir" ]; then
          target_dir="$dir"
          break
        fi
        ;;
    esac
  done
  IFS=$oldifs

  if [ -z "$target_dir" ]; then
    target_dir="$HOME/.local/bin"
    mkdir -p "$target_dir" || {
      echo "Unable to create $target_dir." >&2
      return 1
    }
  fi

  target="$target_dir/note"

  ln -sf "$script_path" "$target" 2>/dev/null || {
    cp "$script_path" "$target" || {
      echo "Failed to place note at $target." >&2
      return 1
    }
  }

  case ":$PATH:" in
    *":$target_dir:"*)
      printf 'Installed note -> %s%s%s\n' "$color_title" "$target" "$color_reset"
      ;;
    *)
      printf 'Installed note -> %s%s%s\n' "$color_title" "$target" "$color_reset"
      echo "Add \"$target_dir\" to your PATH to use it everywhere."
      ;;
  esac

  ensure_note_storage "$note_target_arg"
}

cmd=${1-}
case "$cmd" in
  "")
    require_note_file
    create_note
    ;;
  show)
    shift
    require_note_file
    show_note "$@"
    ;;
  pop)
    shift
    require_note_file
    pop_note
    ;;
  list)
    shift
    [ $# -eq 0 ] || usage
    require_note_file
    list_notes
    ;;
  search)
    shift
    [ $# -ge 1 ] || usage
    require_note_file
    query="$1"
    search_notes "$query"
    ;;
  install)
    shift
    [ $# -le 1 ] || usage
    install_note "$@"
    ;;
  help|--help|-h)
    usage
    ;;
  -i)
    shift
    [ $# -eq 1 ] || usage
    require_note_file
    open_by_id "$1"
    ;;
  -*)
    usage
    ;;
  *)
    [ $# -eq 1 ] || usage
    require_note_file
    create_or_open "$1"
    ;;
esac
