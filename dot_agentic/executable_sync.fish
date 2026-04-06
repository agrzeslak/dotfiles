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
# - Print:
#     [Succeeded] - <What>
#     [  Skipped] - <What>
#     [   Failed] - <What>
#   with colored status words.

set -l GREEN (set_color green)
set -l YELLOW (set_color yellow)
set -l RED (set_color red)
set -l RESET (set_color normal)

# Resolve script directory so this works even if run outside ~/.agentic.
set -l SCRIPT_DIR (cd (dirname (status filename)); and pwd)

set -l SOURCE_AGENTS "$SCRIPT_DIR/AGENTS.md"
set -l SOURCE_SKILLS "$SCRIPT_DIR/skills"

function report
    set -l status_word $argv[1]
    set -l message $argv[2]

    # Keep bracketed status width fixed at 11 chars inside the brackets.
    # "Succeeded" is 9 chars, so:
    #   [Succeeded]
    #   [  Skipped]
    #   [   Failed]
    set -l label ""

    switch $status_word
        case Succeeded
            set label "[Succeeded]"
        case Skipped
            set label "[  Skipped]"
        case Failed
            set label "[   Failed]"
        case '*'
            set label "[$status_word]"
    end

    # Only emit ANSI color if writing to a terminal.
    if isatty stdout
        switch $status_word
            case Succeeded
                printf "%s%s%s - %s\n" (set_color green) "$label" (set_color normal) "$message"
            case Skipped
                printf "%s%s%s - %s\n" (set_color yellow) "$label" (set_color normal) "$message"
            case Failed
                printf "%s%s%s - %s\n" (set_color red) "$label" (set_color normal) "$message"
            case '*'
                printf "%s - %s\n" "$label" "$message"
        end
    else
        printf "%s - %s\n" "$label" "$message"
    end
end

function copy_file_if_parent_exists
    set -l source_file $argv[1]
    set -l dest_file $argv[2]
    set -l label $argv[3]

    set -l parent_dir (dirname "$dest_file")

    if not test -d "$parent_dir"
        report Skipped "$label (parent directory $parent_dir does not exist)"
        return 0
    end

    if not test -f "$source_file"
        report Failed "$label (source file $source_file does not exist)"
        return 1
    end

    if cp -f "$source_file" "$dest_file"
        report Succeeded "$label"
        return 0
    else
        report Failed "$label"
        return 1
    end
end

function sync_skills_if_parent_exists
    set -l source_dir $argv[1]
    set -l dest_dir $argv[2]
    set -l label $argv[3]

    set -l parent_dir (dirname "$dest_dir")

    if not test -d "$parent_dir"
        report Skipped "$label (parent directory $parent_dir does not exist)"
        return 0
    end

    if not test -d "$source_dir"
        report Failed "$label (source directory $source_dir does not exist)"
        return 1
    end

    if not mkdir -p "$dest_dir"
        report Failed "$label (could not create destination directory $dest_dir)"
        return 1
    end

    if rsync -a "$source_dir/" "$dest_dir/"
        report Succeeded "$label"
    else
        report Failed "$label"
        return 1
    end

    set -l source_skill_names
    for path in "$source_dir"/*
        if test -d "$path"
            set -a source_skill_names (basename "$path")
        end
    end

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
                            report Succeeded "Deleted stale skill $path"
                        else
                            report Failed "Delete stale skill $path"
                        end
                        break
                    case '' n no
                        report Skipped "Deleted stale skill $path"
                        break
                    case '*'
                        echo "Please answer y or n."
                end
            end
        end
    end
end

copy_file_if_parent_exists "$SOURCE_AGENTS" "$HOME/.codex/AGENTS.md" "Copy AGENTS.md to ~/.codex/AGENTS.md"
copy_file_if_parent_exists "$SOURCE_AGENTS" "$HOME/.claude/CLAUDE.md" "Copy AGENTS.md to ~/.claude/CLAUDE.md"

sync_skills_if_parent_exists "$SOURCE_SKILLS" "$HOME/.codex/skills" "Sync skills to ~/.codex/skills"
sync_skills_if_parent_exists "$SOURCE_SKILLS" "$HOME/.claude/skills" "Sync skills to ~/.claude/skills"
