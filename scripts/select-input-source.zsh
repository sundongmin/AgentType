# Sourced only by manage.zsh after configuration validation. Never writes settings.
gim_select_source() {
    local listing='' row source_id source_name source_language choice
    local -a ids names chinese_ids chinese_names
    if (( fixture )); then
        # Test data is accepted only with an explicit isolated target directory.
        [[ -n ${GIM_TEST_INPUT_SOURCES:-} && -f $GIM_TEST_INPUT_SOURCES ]] || die '隔离安装需要 GIM_TEST_INPUT_SOURCES 测试清单'
        listing=$(<"$GIM_TEST_INPUT_SOURCES")
    else
        listing=$(/usr/bin/osascript -l JavaScript "$package_dir/scripts/input-sources.js" --all) ||
            die '无法读取本机输入源；未修改配置。请在正常登录的 macOS 会话中重试。'
    fi
    for row in "${(@f)listing}"; do
        [[ -n $row ]] || continue
        source_id=${row%%$'\t'*}
        row=${row#*$'\t'}
        source_name=${row%%$'\t'*}
        source_language=${row##*$'\t'}
        [[ -n $source_id && $source_id != *[^a-zA-Z0-9._-]* && -n $source_name &&
            ($source_language == chinese || $source_language == other) ]] || die '系统输入源数据格式错误；未修改配置'
        ids+=("$source_id")
        names+=("$source_name")
        if [[ $source_language == chinese ]]; then
            chinese_ids+=("$source_id")
            chinese_names+=("$source_name")
        fi
    done
    (( ${#ids} )) || die '没有找到已启用、可切换的键盘输入源。请先在系统设置 → 键盘 → 文本输入中添加。'
    (( ${ids[(Ie)$terminal_source]} )) || die "普通终端输入源未启用或不可切换: $terminal_source。请先添加，或用 --terminal-source 指定。"
    if [[ -n $agent_source ]]; then
        (( ${ids[(Ie)$agent_source]} )) || die "Agent 输入源未启用或不可切换: $agent_source。请先在系统设置中添加。"
        print -r -- "Agent 输入法: ${names[${ids[(Ie)$agent_source]}]} ($agent_source)"
        return
    fi
    (( ${#chinese_ids} )) || die '没有找到已启用、可切换的中文输入法。请到系统设置 → 键盘 → 文本输入中添加后重试；安装输入法 App 本身还不够。'
    print -- '请选择 Agent 中使用的中文输入法（已启用）：'
    local index
    for (( index=1; index <= ${#chinese_ids}; index++ )); do
        print -r -- "  $index) ${chinese_names[$index]}  [${chinese_ids[$index]}]"
    done
    print -- '  q) 取消安装'
    # A preview lists choices without consuming input or selecting a default.
    if (( dry_run )); then
        print -- '预览模式不会选择输入法；正式安装时请输入编号。'
        agent_source=${chinese_ids[1]}
        return
    fi
    [[ -t 0 ]] || die '非交互安装需要 --agent-source ID；不会自动替你选择输入法。'
    while true; do
        printf '输入编号，或 q 取消: '
        IFS= read -r choice || die '输入已结束，安装取消；未修改配置。'
        [[ $choice != [qQ] ]] || die '安装已取消；未修改配置。'
        if [[ $choice == <-> && ${#choice} -le 6 ]] && (( 10#$choice >= 1 && 10#$choice <= ${#chinese_ids} )); then
            index=$(( 10#$choice ))
            agent_source=${chinese_ids[$index]}
            print -r -- "已选择: ${chinese_names[$index]} ($agent_source)"
            return
        fi
        print -- '请输入列表中的编号，或输入 q 取消。'
    done
}
