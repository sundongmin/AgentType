#!/bin/zsh
# macOS built-in tools only. Stage edits, back up all targets, then commit.
emulate -LR zsh
setopt ERR_EXIT NO_UNSET PIPE_FAIL
umask 077
package_dir=${0:A:h:h}
action=$1
shift
target_home=$HOME
zshrc_option=''
dry_run=0
fixture=0
terminal_source=com.apple.keylayout.ABC
agent_source=''
sources_explicit=0
usage() {
    cat <<'EOF'
用法: ./install.sh [选项] 或 ./uninstall.sh [选项]
  --dry-run               只检查、显示将修改的位置
  --zshrc /绝对路径       使用自定义 zsh 配置文件（默认 $ZDOTDIR/.zshrc 或 ~/.zshrc）
  --terminal-source ID    首次安装的普通终端输入源（默认 ABC）
  --agent-source ID       首次安装的 Agent 输入源（不指定时列出本机中文输入法供选择）
  --target-home /绝对路径 在隔离目录安装，用于测试；不连接正在运行的 Hammerspoon
  --help                 显示帮助
缺少 Hammerspoon 时优先使用 Homebrew 安装；没有 Homebrew 时从官方 GitHub 下载。
预览模式不下载、不安装。不重载 Hammerspoon，不执行或覆盖用户已有 shell 函数。
EOF
}
die() { print -u2 -r -- "$*"; exit 1; }
while (( $# )); do
    case $1 in
        --dry-run) dry_run=1; shift ;;
        --target-home|--zshrc|--terminal-source|--agent-source)
            (( $# >= 2 )) || die "$1 缺少参数"
            case $1 in
                --target-home) target_home=$2; fixture=1 ;;
                --zshrc) zshrc_option=$2 ;;
                --terminal-source) terminal_source=$2; sources_explicit=1 ;;
                --agent-source) agent_source=$2; sources_explicit=1 ;;
            esac
            shift 2
            ;;
        --help|-h) usage; exit 0 ;;
        *) die "未知参数: $1" ;;
    esac
done
[[ $action == install || $action == uninstall ]] || die '未知操作'
[[ $target_home == /* && $target_home != / && -d $target_home ]] || die '用户目录必须是已存在的绝对路径，且不能是 /'
[[ $target_home != *$'\n'* && $target_home != *$'\r'* ]] || die '目录名不能含换行'
target_home=${target_home:A}
support_hint="$target_home/.hammerspoon/GhosttyInputMethod"
if [[ -n $zshrc_option ]]; then
    zshrc_file=$zshrc_option
elif [[ $action == uninstall && -f "$support_hint/.managed-v1" && -f "$support_hint/zshrc-path" ]]; then
    zshrc_file=$(<"$support_hint/zshrc-path")
elif (( fixture )); then
    zshrc_file="$target_home/.zshrc"
else
    zshrc_file="${ZDOTDIR:-$target_home}/.zshrc"
fi
[[ $zshrc_file == /* && $zshrc_file != *$'\n'* && $zshrc_file != *$'\r'* ]] || die 'zsh 配置必须是无换行的绝对路径'
[[ -d ${zshrc_file:h} ]] || die 'zsh 配置父目录不存在'
zshrc_file=${zshrc_file:a}
hs_dir="$target_home/.hammerspoon"
support_dir="$hs_dir/GhosttyInputMethod"
spoon_dir="$hs_dir/Spoons/GhosttyInputMethod.spoon"
init_file="$hs_dir/init.lua"
[[ $zshrc_file != $init_file ]] || die 'zsh 配置不能指向 Hammerspoon 配置'
case $zshrc_file in
    "$support_dir"|"$support_dir"/*|"$spoon_dir"|"$spoon_dir"/*|"$hs_dir/GhosttyInputMethod-backups"/*)
        die 'zsh 配置不能位于插件安装或备份目录内' ;;
esac
for source_id in "$terminal_source" "$agent_source"; do
    [[ -n $source_id ]] || continue
    [[ -n $source_id && $source_id != *[^a-zA-Z0-9._-]* ]] || die "输入源 ID 不合法: $source_id"
done
# Do not silently replace symlink-managed dotfiles or traverse symlinked install dirs.
for item in "$hs_dir" "$hs_dir/Spoons" "$support_dir" "$spoon_dir" "$init_file" "$zshrc_file"; do
    [[ ! -L $item ]] || die "检测到符号链接，请按 README 手动集成，避免破坏配置管理: $item"
done
for item in "$init_file" "$zshrc_file"; do
    [[ ! -e $item || -f $item ]] || die "不是普通文件: $item"
done
if [[ $action == install ]]; then
    if (( ! fixture )); then
        [[ $(uname -s) == Darwin ]] || die '仅支持 macOS'
        (( EUID != 0 )) || die '请以普通用户运行，不要使用 sudo'
    fi
    [[ -f "$package_dir/GhosttyInputMethod.spoon/init.lua" && -f "$package_dir/shell/ghostty-im" ]] || die '分发包不完整'
    if [[ -d $support_dir && ! -f "$support_dir/.managed-v1" ]]; then die "目标目录不属于本安装工具: $support_dir"; fi
    if [[ -f "$support_dir/zshrc-path" && $(<"$support_dir/zshrc-path") != $zshrc_file ]]; then
        die '已有安装使用了其他 zsh 配置路径。请先卸载原安装，再更换路径。'
    fi
    if [[ -d $spoon_dir && ! -f "$support_dir/.managed-v1" ]]; then die '已存在手动安装的同名 Spoon，请按 README 手动集成或先移走该 Spoon'; fi
    if [[ -f "$support_dir/config.lua" ]] && (( sources_explicit )); then
        die "已有配置会保留。更改输入法请编辑 $support_dir/config.lua，然后重载 Hammerspoon。"
    fi
fi
stage_dir=$(mktemp -d "${TMPDIR:-/tmp}/ghostty-im.XXXXXXXX")
commit_started=0
committed=0
backup_dir=''
typeset -a targets existed
targets=("$init_file" "$zshrc_file" "$spoon_dir" "$support_dir")
cleanup() {
    local result=$?
    trap - EXIT HUP INT TERM
    if (( commit_started && ! committed )); then
        print -u2 -- '安装未完成，正在恢复本次操作前的文件。'
        local index
        for index in {1..4}; do
            if [[ ${existed[$index]} == yes ]]; then
                rm -rf -- "${targets[$index]}"
                cp -Rp -- "$backup_dir/$index" "${targets[$index]}" || print -u2 -- "恢复失败，请从备份恢复: ${targets[$index]}"
            else
                rm -rf -- "${targets[$index]}"
            fi
        done
    fi
    rm -rf -- "$stage_dir"
    return $result
}
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' HUP TERM

# Refuse malformed or repeated managed blocks before writing anything.
strip_block() {
    local input=$1 output=$2 prefix=$3
    if [[ ! -e $input ]]; then : > "$output"; return; fi
    awk -v begin="$prefix BEGIN GhosttyInputMethod managed v1" -v end="$prefix END GhosttyInputMethod managed v1" '
        $0 == begin { if (inside || seen) exit 41; inside=1; seen=1; next }
        $0 == end { if (!inside) exit 42; inside=0; next }
        !inside { print }
        END { if (inside) exit 43 }
    ' "$input" > "$output" || die "托管标记损坏或重复，请手动检查: $input"
}
strip_block "$init_file" "$stage_dir/init.lua" '--'
strip_block "$zshrc_file" "$stage_dir/zshrc" '#'

if [[ $action == install ]]; then
    if grep -Eq 'ghosttyIM|ghosttyIMResolveTTY|ghosttyIMSet|GhosttyInputMethod' "$stage_dir/init.lua" || \
       grep -Eq '_ai_agent_im_|_ai_agent_run|ghostty-input-method[.]zsh|ghostty_im_run' "$stage_dir/zshrc"; then
        die '检测到旧教程配置或手动集成。未修改文件。请先移除旧输入法代码，保留其他设置，再安装。'
    fi
    if [[ ! -f "$support_dir/config.lua" ]]; then
        source "$package_dir/scripts/select-input-source.zsh"
        gim_select_source
    else
        print -- '已有安装：保留选择的输入法；旧版默认轮询 0.25 秒将更新为 0.15 秒。'
    fi
    cat >> "$stage_dir/init.lua" <<'EOF'
-- BEGIN GhosttyInputMethod managed v1
do
    hs.loadSpoon("GhosttyInputMethod")
    local config = dofile(hs.configdir .. "/GhosttyInputMethod/config.lua")
    for key, value in pairs(config) do spoon.GhosttyInputMethod[key] = value end
    spoon.GhosttyInputMethod:start()
end
-- END GhosttyInputMethod managed v1
EOF
    # Quote as a single zsh word; handles spaces, quotes, $, and backticks in paths.
    shell_file="$support_dir/ghostty-input-method.zsh"
    print -r -- '# BEGIN GhosttyInputMethod managed v1' >> "$stage_dir/zshrc"
    print -r -- "[[ ! -f ${(q)shell_file} ]] || source ${(q)shell_file}" >> "$stage_dir/zshrc"
    print -r -- '# END GhosttyInputMethod managed v1' >> "$stage_dir/zshrc"
    mkdir "$stage_dir/support"
    cp -p "$package_dir/shell/ghostty-im" "$package_dir/shell/ghostty-input-method.zsh" "$stage_dir/support/"
    : > "$stage_dir/support/.managed-v1"
    print -r -- "$zshrc_file" > "$stage_dir/support/zshrc-path"
    if [[ -f "$support_dir/config.lua" ]]; then
        awk '{ if ($0 ~ /^[[:space:]]*pollInterval[[:space:]]*=[[:space:]]*0\.25[[:space:]]*,/) sub(/0\.25/, "0.15"); print }' \
            "$support_dir/config.lua" > "$stage_dir/support/config.lua"
    else
        cat > "$stage_dir/support/config.lua" <<EOF
-- Change IDs using: ghostty-im sources. Reload Hammerspoon after editing.
return {
    terminalSource = "$terminal_source",
    agentSource = "$agent_source",
    pollInterval = 0.15,
    queryTimeout = 3,
    cleanupInterval = 30,
}
EOF
    fi
    chmod 700 "$stage_dir/support/ghostty-im"
fi
/bin/zsh -n "$stage_dir/zshrc" || die '修改后的 zsh 配置语法检查失败；未修改文件'
print -r -- "操作: $action"
print -r -- "Hammerspoon: $init_file"
print -r -- "zsh: $zshrc_file"
print -r -- "Spoon: $spoon_dir"
print -r -- "集成与设置: $support_dir"
if [[ $action == install ]] && (( ! fixture )); then
    source "$package_dir/scripts/ensure-hammerspoon.zsh"
    gim_ensure_hammerspoon
fi
if (( dry_run )); then print -- '检查完成，未修改配置。'; exit 0; fi
if [[ $action == uninstall && ! -f "$support_dir/.managed-v1" ]]; then
    die '未发现本安装工具的安装标记；不删除手动安装内容。'
fi
# Backups contain dotfiles, so the directory is private to the current user.
mkdir -p "$hs_dir/GhosttyInputMethod-backups" "$hs_dir/Spoons"
backup_dir=$(mktemp -d "$hs_dir/GhosttyInputMethod-backups/$(date +%Y%m%d-%H%M%S).XXXXXXXX")
for index in {1..4}; do
    print -r -- "$index: ${targets[$index]}" >> "$backup_dir/paths.txt"
    if [[ -e ${targets[$index]} ]]; then
        existed[$index]=yes
        cp -Rp -- "${targets[$index]}" "$backup_dir/$index"
    else
        existed[$index]=no
        print -r -- "$index" >> "$backup_dir/previously-absent.txt"
    fi
done
commit_started=1
# Write existing dotfiles in place to retain their permissions.
cat "$stage_dir/init.lua" > "$init_file"
cat "$stage_dir/zshrc" > "$zshrc_file"
rm -rf -- "$spoon_dir" "$support_dir"
if [[ $action == install ]]; then
    cp -Rp "$package_dir/GhosttyInputMethod.spoon" "$spoon_dir"
    cp -Rp "$stage_dir/support" "$support_dir"
fi
committed=1
print -r -- "完成。备份: $backup_dir"
if [[ $action == install ]]; then
    print -- '下一步：打开 Hammerspoon（已运行则 Reload Config）；允许所需权限；退出 Agent 后重新打开 Ghostty 终端。'
    print -r -- "诊断: ${(q)support_dir}/ghostty-im doctor"
    print -- '若使用 KeyboardHolder，请在它的排除应用中加入 Ghostty。'
else
    print -- '下一步：Hammerspoon → Reload Config；退出 Agent 后重新打开终端以移除旧 shell 函数。'
    print -- '备份及 Hammerspoon 内的历史状态保留；清理方法见 README。'
fi
