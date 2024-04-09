abbr -a yr 'cal -y'
abbr -a c cargo
abbr -a e nvim
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
abbr -a pm pulsemixer
abbr -a bt bluetoothctl
abbr -a cm chezmoi

complete --command paru --wraps pacman

# Enable AWS CLI autocompletion: github.com/aws/aws-cli/issues/1079
complete --command aws --no-files --arguments '(begin; set --local --export COMP_SHELL fish; set --local --export COMP_LINE (commandline); aws_completer | sed \'s/ $//\'; end)'

if status --is-interactive
	if test -d ~/dev/others/base16/templates/fish-shell
		set fish_function_path $fish_function_path ~/dev/others/base16/templates/fish-shell/functions
		builtin source ~/dev/others/base16/templates/fish-shell/conf.d/base16.fish
	end
	if ! set -q TMUX
		# Always attach to the same session rather than creating a new
		# one when a new terminal is opened. This is almost always
		# what's intended.
		exec tmux new-session -As "main"
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

# TODO: Programmatically apply this.
# To make Java apps scale correctly on HiDPI displays.
function java_ui_scale
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

function tmux_create_session
	# Search common paths first, then all visited directories
	if not set target_path (find ~/dev ~/dev/others ~/pentests -mindepth 1 -maxdepth 1 -type d  | fzf)
		if not set target_path (zoxide query -i)
			return
		end
	end

	set name (basename $target_path | tr . _)

	# tmux isn't running; create the new session
	if test -z TMUX && test -z (pgrep tmux)
		tmux new-session -c $name -s $target_path
		return
	end

	# tmux is already running; only create the session if it doesn't exist
	if not tmux has-session -t $name 2>/dev/null
		tmux new-session -c $target_path -ds $name
	end

	tmux switch-client -t $name
end

function tmux_switch_session
	if not set chosen_session (tmux list-sessions -F \#S | fzf)
		return
	end

	tmux switch-client -t $chosen_session
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

# Used by AWS CLI to determine which browser to use
set -gx BROWSER "/usr/bin/firefox-developer-edition"

set -gx RUST_BACKTRACE 1

pyenv init - | source

# C-z to fg
# https://github.com/fish-shell/fish-shell/issues/7152#issuecomment-663575001
function fish_user_key_bindings
	bind \cz 'fg 2>/dev/null; commandline -f repaint'
	bind ! bind_bang
	bind '$' bind_dollar
end

function fish_prompt
	set_color blue
	echo -n (hostnamectl hostname)
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

if test -e ~/.config/fish/work.fish
	builtin source ~/.config/fish/work.fish
end
