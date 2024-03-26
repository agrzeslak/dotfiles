abbr -a yr 'cal -y'
abbr -a c cargo
abbr -a e nvim
# abbr -a e helix
abbr -a se sudoedit
abbr -a m make
abbr -a o xdg-open
abbr -a g git
abbr -a gap 'git add -p'
abbr -a gc 'git checkout'
abbr -a gd 'git diff'
abbr -a gdc 'git diff --cached'
abbr -a gl 'git log --graph --pretty=format:"%Cred%h%Creset -%C(yellow)%d%Creset %s %Cgreen(%cr)%Creset" --abbrev-commit --date=relative'
abbr -a gs 'git status'
abbr -a gah 'git stash; and git pull --rebase; and git stash pop'
abbr -a pr 'gh pr create -t (git show -s --format=%s HEAD) -b (git show -s --format=%B HEAD | tail -n+3)'
abbr -a vimdiff 'nvim -d'
abbr -a ct 'cargo t'
abbr -a amz 'env AWS_SECRET_ACCESS_KEY=(pass www/aws-secret-key | head -n1)'
abbr -a ais "aws ec2 describe-instances | jq '.Reservations[] | .Instances[] | {iid: .InstanceId, type: .InstanceType, key:.KeyName, state:.State.Name, host:.PublicDnsName}'"
abbr -a v 'source env/bin/activate.fish'
abbr -a ks 'keybase chat send'
abbr -a kr 'keybase chat read'
abbr -a kl 'keybase chat list'
abbr -a pm pulsemixer
abbr -a bt bluetoothctl
abbr -a cm chezmoi
complete --command paru --wraps pacman

if status --is-interactive
    if test -d ~/dev/others/base16/templates/fish-shell
        set fish_function_path $fish_function_path ~/dev/others/base16/templates/fish-shell/functions
        builtin source ~/dev/others/base16/templates/fish-shell/conf.d/base16.fish
    end
    if ! set -q TMUX
        exec tmux
    end
end

if command -v eza > /dev/null
    abbr -a l 'eza'
    abbr -a ls 'eza'
    abbr -a ll 'eza -l'
    abbr -a lll 'eza -la'
else
    abbr -a l 'ls'
    abbr -a ll 'ls -l'
    abbr -a lll 'ls -la'
end

if type -q zoxide
    zoxide init --cmd j fish | source
end

function apass
    if test (count $argv) -ne 1
        pass $argv
        return
    end

    asend (pass $argv[1] | head -n1)
end

function qrpass
    if test (count $argv) -ne 1
        pass $argv
        return
    end

    qrsend (pass $argv[1] | head -n1)
end

function asend
    if test (count $argv) -ne 1
        echo "No argument given"
        return
    end

    adb shell input text (echo $argv[1] | sed -e 's/ /%s/g' -e 's/\([#[()<>{}$|;&*\\~"\'`]\)/\\\\\1/g')
end

function qrsend
    if test (count $argv) -ne 1
        echo "No argument given"
        return
    end

    qrencode -o - $argv[1] | feh --geometry 500x500 --auto-zoom -
end

function limit
	numactl -C 0,1,2 $argv
end

function remote_alacritty
    # https://gist.github.com/costis/5135502
    set fn (mktemp)
    infocmp alacritty > $fn
    scp $fn $argv[1]":alacritty.ti"
    ssh $argv[1] tic "alacritty.ti"
    ssh $argv[1] rm "alacritty.ti"
end

# Type - to move up to top parent dir which is a repository
function d
    while test $PWD != "/"
        if test -d .git
                break
        end
        cd ..
    end
end

function bind_bang
    switch (commandline -t)[-1]
        case "!"
            commandline -t -- $history[1]
            commandline -f repaint
        case "*"
            commandline -i !
    end
end

function bind_dollar
    switch (commandline -t)[-1]
        case "!"
            commandline -f backward-delete-char history-token-search-backward
        case "*"
            commandline -i '$'
    end
end

function strip_ansi
    if test (count $argv) -ne 1
        echo "strip_ansi <source file>"
        return
    end
    sed -e 's/\x1b\[[0-9;]*m//g' $argv[1] > $argv[1].tmp
    mv $argv[1].tmp $argv[1]
end

function java_ui_scale
# TODO: Programmatically apply this.
# To make Java apps scale correctly on HiDPI displays.
    if test (count $argv) -ne 1
        echo "java_ui_scale <scale>"
        return
    end
    set -gx _JAVA_OPTIONS '-Dsun.java2d.uiScale='$argv[1]
end

function ssh_via_socks
    if test (count $argv) -ne 4
        echo "ssh-via-socks <proxy> <proxy user> <proxy pass> <ssh user@server>"
        return
    end
    ssh -o ProxyCommand='nc --proxy-type socks5 --proxy '$argv[1]' --proxy-auth '$argv[2]':'$argv[3]' %h %p' $argv[4]
end

function retry
    while true;
        eval $argv && break
        sleep 1
    end
end

if test -e ~/.config/fish/work.fish
    builtin source ~/.config/fish/work.fish
end

# Fish git prompt
set __fish_git_prompt_showuntrackedfiles 'yes'
set __fish_git_prompt_showdirtystate 'yes'
set __fish_git_prompt_showstashstate ''
set __fish_git_prompt_showupstream 'none'

# Fish prompt: truncate intermediate directories to 3 characters
set -g fish_prompt_pwd_dir_length 3

# colored man output
# from http://linuxtidbits.wordpress.com/2009/03/23/less-colors-for-man-pages/
setenv LESS_TERMCAP_mb \e'[01;31m'       # begin blinking
setenv LESS_TERMCAP_md \e'[01;38;5;74m'  # begin bold
setenv LESS_TERMCAP_me \e'[0m'           # end mode
setenv LESS_TERMCAP_se \e'[0m'           # end standout-mode
setenv LESS_TERMCAP_so \e'[38;5;246m'    # begin standout-mode - info box
setenv LESS_TERMCAP_ue \e'[0m'           # end underline
setenv LESS_TERMCAP_us \e'[04;38;5;146m' # begin underline

setenv FZF_DEFAULT_COMMAND 'fd --type file --follow'
setenv FZF_CTRL_T_COMMAND 'fd --type file --follow'
setenv FZF_DEFAULT_OPTS '--height 20%'

# Fish should not add things to clipboard when killing
# See https://github.com/fish-shell/fish-shell/issues/772
set FISH_CLIPBOARD_CMD "cat"

# Otherwise tmux doesn't print UTF-8 chars since it's set to C lang mode.
# Can also run tmux -u, but this seems better.
set -gx LC_ALL en_US.UTF-8


# Make Java apps work with some window managers like BSPWM. Non-reparenting WMs
# are hardcoded and so if you're not on the list then it won't work. Here we
# specifically say that we are a non-reparenting WM.
# Also works to use `wmname LG3D`.
set -gx _JAVA_AWT_WM_NONREPARENTING 1

# Used by commands such as sudoedit to determine which editor to use.
set -gx EDITOR "/usr/bin/nvim"

set -gx RUST_BACKTRACE 1

pyenv init - | source

# FIXME: Missing the fzf_key_bindings file (symlink to a file which doesn't exist on jonhoo's repo) file.
function fish_user_key_bindings
	bind \cz 'fg>/dev/null ^/dev/null'
	if functions -q fzf_key_bindings
		fzf_key_bindings
	end
    bind ! bind_bang
    bind '$' bind_dollar
end

function fish_prompt
	set_color blue
	echo -n (hostname)
	if [ $PWD != $HOME ]
		set_color brblack
		echo -n ':'
		set_color yellow
		echo -n (basename $PWD)
	end
	set_color green
	printf '%s ' (__fish_git_prompt)
	set_color red
	echo -n '| '
	set_color normal
end

function fish_greeting
end
