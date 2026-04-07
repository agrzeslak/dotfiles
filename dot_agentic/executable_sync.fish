#!/usr/bin/env fish

# Sync AGENTS.md and skills from ~/.agentic to Codex and Claude.
#
# Source layout:
#   ~/.agentic/
#     AGENTS.md
#     skills/
#       skill-one/
#       skill-two/
#
# Behavior:
# - Copy AGENTS.md to:
#     ~/.codex/AGENTS.md
#     ~/.claude/CLAUDE.md
# - Sync skills by top-level skill directory:
#     - copy/update all skills from source to destination
#     - prompt before deleting stale top-level skill directories in destination
# - If a destination parent directory does not exist, skip that step.
# - Print one line per action, where the status word reflects what actually
#   happened to the destination:
#     [Created  ] <path>   (green)  destination did not previously exist
#     [Updated  ] <path>   (green)  destination existed and was overwritten
#     [Deleted  ] <path>   (green)  destination was removed
#     [Skipped  ] <path>   (yellow) action was deliberately not taken
#     [Unchanged] <path>   (yellow) destination already matched the source
#     [Failed   ] <path>   (red)    action was attempted but errored
#   Paths and skill names are highlighted in light blue so they stand out.

# Colors are emitted only when stdout is a terminal. We resolve them once,
# globally, so both the report function and the callers (which embed BLUE in
# message strings) can reference the same values.
if isatty stdout
    set -g GREEN (set_color green)
    set -g YELLOW (set_color yellow)
    set -g RED (set_color red)
    set -g BLUE (set_color brblue)
    set -g RESET (set_color normal)
else
    set -g GREEN ""
    set -g YELLOW ""
    set -g RED ""
    set -g BLUE ""
    set -g RESET ""
end

# Resolve script directory so this works even if run outside ~/.agentic.
set -l SCRIPT_DIR (cd (dirname (status filename)); and pwd)

set -l SOURCE_AGENTS "$SCRIPT_DIR/AGENTS.md"
set -l SOURCE_SKILLS "$SCRIPT_DIR/skills"

function report
    set -l status_word $argv[1]
    set -l message $argv[2]

    # Keep labels aligned using the longest known status word so the path
    # column is stable even when shorter statuses are emitted.
    set -l label (printf "[%-9s]" "$status_word")
    set -l color

    switch $status_word
        case Created
            set color $GREEN
        case Updated
            set color $GREEN
        case Deleted
            set color $GREEN
        case Skipped
            set color $YELLOW
        case Unchanged
            set color $YELLOW
        case Failed
            set color $RED
        case '*'
            set color ""
    end

    printf "%s%s%s %s\n" "$color" "$label" "$RESET" "$message"
end

function copy_file_if_parent_exists
    set -l source_file $argv[1]
    set -l dest_file $argv[2]

    set -l parent_dir (dirname "$dest_file")

    if not test -d "$parent_dir"
        report Skipped "$BLUE$dest_file$RESET (parent $BLUE$parent_dir$RESET does not exist)"
        return 0
    end

    if not test -f "$source_file"
        report Failed "$BLUE$dest_file$RESET (source $BLUE$source_file$RESET does not exist)"
        return 1
    end

    # Skip the write when the destination already matches the source so the
    # status line reflects that nothing changed on disk.
    if test -f "$dest_file"
        if cmp -s "$source_file" "$dest_file"
            report Unchanged "$BLUE$dest_file$RESET"
            return 0
        end
    end

    # Distinguish a fresh write from an overwrite so the user can see at a
    # glance which destinations were touched on this run.
    set -l action
    if test -e "$dest_file"
        set action Updated
    else
        set action Created
    end

    if cp -f "$source_file" "$dest_file"
        report $action "$BLUE$dest_file$RESET"
        return 0
    else
        report Failed "$BLUE$dest_file$RESET"
        return 1
    end
end

function sync_skills_if_parent_exists
    set -l source_dir $argv[1]
    set -l dest_dir $argv[2]

    set -l parent_dir (dirname "$dest_dir")

    if not test -d "$parent_dir"
        report Skipped "$BLUE$dest_dir$RESET (parent $BLUE$parent_dir$RESET does not exist)"
        return 0
    end

    if not test -d "$source_dir"
        report Failed "$BLUE$dest_dir$RESET (source $BLUE$source_dir$RESET does not exist)"
        return 1
    end

    if not mkdir -p "$dest_dir"
        report Failed "$BLUE$dest_dir$RESET (could not create destination directory)"
        return 1
    end

    # We rsync each top-level skill individually so that we can report
    # Created vs Updated per skill rather than emitting a single status line
    # for the whole batch. --delete inside each skill keeps removed inner
    # files from lingering, while still letting us prompt before nuking
    # entire stale skill directories below.
    set -l source_skill_names
    for src_path in "$source_dir"/*
        if not test -d "$src_path"
            continue
        end

        set -l skill_name (basename "$src_path")
        set -a source_skill_names $skill_name
        set -l dest_path "$dest_dir/$skill_name"

        set -l action
        if test -d "$dest_path"
            set action Updated
        else
            set action Created
        end

        # Probe rsync first so unchanged skills can be reported without doing
        # a no-op sync that looks like an update.
        set -l rsync_probe (rsync -ain --delete "$src_path/" "$dest_path/")
        set -l probe_status $status

        if test $probe_status -ne 0
            report Failed "$BLUE$dest_path$RESET"
            continue
        end

        if test -z "$rsync_probe"
            report Unchanged "$BLUE$dest_path$RESET"
            continue
        end

        if rsync -a --delete "$src_path/" "$dest_path/"
            report $action "$BLUE$dest_path$RESET"
        else
            report Failed "$BLUE$dest_path$RESET"
        end
    end

    # Anything in the destination that no longer exists in the source is a
    # stale skill. We never delete without confirmation, since the user may
    # have hand-installed it.
    for path in "$dest_dir"/*
        if not test -e "$path"
            continue
        end

        if not test -d "$path"
            continue
        end

        set -l skill_name (basename "$path")

        if not contains -- "$skill_name" $source_skill_names
            while true
                read -P "Delete stale skill '$skill_name' from $dest_dir? [y/N] " reply

                switch (string lower -- "$reply")
                    case y yes
                        if rm -rf -- "$path"
                            report Deleted "$BLUE$path$RESET (stale skill)"
                        else
                            report Failed "$BLUE$path$RESET (could not delete stale skill)"
                        end
                        break
                    case '' n no
                        report Skipped "$BLUE$path$RESET (kept stale skill)"
                        break
                    case '*'
                        echo "Please answer y or n."
                end
            end
        end
    end
end

copy_file_if_parent_exists "$SOURCE_AGENTS" "$HOME/.codex/AGENTS.md"
copy_file_if_parent_exists "$SOURCE_AGENTS" "$HOME/.claude/CLAUDE.md"

sync_skills_if_parent_exists "$SOURCE_SKILLS" "$HOME/.codex/skills"
sync_skills_if_parent_exists "$SOURCE_SKILLS" "$HOME/.claude/skills"
