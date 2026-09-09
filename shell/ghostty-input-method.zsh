# Loaded by the managed block in .zshrc. Only local interactive Ghostty shells.
[[ -o interactive && -n ${GHOSTTY_RESOURCES_DIR:-} && -z ${SSH_CONNECTION:-} && -z ${TMUX:-} ]] || return 0
[[ ${GHOSTTY_IM_DISABLED:-0} == 1 ]] && return 0

typeset -g _GIM_SHELL_DIR=${${(%):-%N}:A:h}
typeset -g _GIM_CLI="$_GIM_SHELL_DIR/ghostty-im"
typeset -g _GIM_TERMINAL_ID=${_GIM_TERMINAL_ID:-}
typeset -g _GIM_NEEDS_REPAIR=1
typeset -g _GIM_RETRY_AT=0
typeset -g _GIM_WARNED=0

_gim_warn() {
    if (( ! _GIM_WARNED )); then
        print -u2 -- 'GhosttyInputMethod: 状态通知失败；Agent 仍正常运行。请执行 ghostty-im doctor。'
        _GIM_WARNED=1
    fi
}
_gim_resolve() {
    [[ -n $_GIM_TERMINAL_ID ]] && return 0
    [[ ${TTY:-} =~ '^/dev/ttys[[:alnum:]]+$' ]] || return 1
    local reply
    reply=$("$_GIM_CLI" resolve "$TTY" 2>/dev/null) || return 1
    [[ -n $reply && $reply != *[^a-zA-Z0-9-]* ]] || return 1
    _GIM_TERMINAL_ID=$reply
}
_gim_notify() {
    [[ -n $_GIM_TERMINAL_ID ]] || return 1
    "$_GIM_CLI" set "$_GIM_TERMINAL_ID" "$1" >/dev/null 2>&1
}

# Public entry point for custom functions: ghostty_im_run codex "$@"
ghostty_im_run() {
    local agent_cmd=$1
    shift
    local agent_result=0
    _GIM_NEEDS_REPAIR=1
    if _gim_resolve && _gim_notify agent; then
        _GIM_WARNED=0
    else
        _gim_warn
    fi
    {
        if command "$agent_cmd" "$@"; then agent_result=0; else agent_result=$?; fi
    } always {
        if _gim_notify terminal; then
            _GIM_NEEDS_REPAIR=0
            _GIM_WARNED=0
        else
            _gim_warn
        fi
    }
    return $agent_result
}
_gim_prompt() {
    (( _GIM_NEEDS_REPAIR )) || return 0
    zmodload zsh/datetime
    (( EPOCHSECONDS >= _GIM_RETRY_AT )) || return 0
    if _gim_resolve && _gim_notify terminal; then
        _GIM_NEEDS_REPAIR=0
        _GIM_WARNED=0
    else
        _GIM_RETRY_AT=$(( EPOCHSECONDS + 10 ))
    fi
    return 0
}

# Avoid replacing aliases/functions owned by the user or another plugin.
typeset -ga _GIM_OWNED_COMMANDS
local _gim_command
for _gim_command in claude codex pi; do
    if (( ${+aliases[$_gim_command]} )) || { (( ${+functions[$_gim_command]} )) && [[ ${_GIM_OWNED_COMMANDS[(Ie)$_gim_command]} == 0 ]]; }; then
        print -u2 -- "GhosttyInputMethod: 保留已有 $_gim_command 别名/函数；可在其中使用 ghostty_im_run。"
    else
        # Command names come only from the fixed list above.
        functions[$_gim_command]="ghostty_im_run $_gim_command \"\$@\""
        (( ${_GIM_OWNED_COMMANDS[(Ie)$_gim_command]} )) || _GIM_OWNED_COMMANDS+=($_gim_command)
    fi
done
autoload -Uz add-zsh-hook
add-zsh-hook -d precmd _gim_prompt 2>/dev/null
add-zsh-hook precmd _gim_prompt
if (( ! ${+aliases[ghostty-im]} && ! ${+functions[ghostty-im]} )); then
    functions[ghostty-im]='"$_GIM_CLI" "$@"'
fi
