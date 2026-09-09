# Sourced by manage.zsh after user configuration has passed validation.
gim_find_hammerspoon() {
    local candidate
    for candidate in /Applications/Hammerspoon.app "$target_home/Applications/Hammerspoon.app"; do
        if [[ -e $candidate || -L $candidate ]]; then
            [[ -x "$candidate/Contents/MacOS/Hammerspoon" && -x "$candidate/Contents/Frameworks/hs/hs" ]] ||
                die "Hammerspoon 已存在但不完整，请先修复，安装器不会覆盖它: $candidate"
            REPLY=$candidate
            return 0
        fi
    done
    return 1
}
gim_find_brew() {
    local candidate
    candidate=$(whence -p brew 2>/dev/null) || candidate=''
    if [[ -n $candidate && -x $candidate ]]; then REPLY=$candidate; return 0; fi
    for candidate in /opt/homebrew/bin/brew /usr/local/bin/brew; do
        if [[ -x $candidate ]]; then REPLY=$candidate; return 0; fi
    done
    return 1
}
gim_application_dir() {
    if [[ -d /Applications && -w /Applications ]]; then REPLY=/Applications
    else REPLY="$target_home/Applications"; fi
}
gim_fetch() {
    /usr/bin/curl --fail --location --show-error --silent --proto '=https' --proto-redir '=https' \
        --connect-timeout 15 --max-time 300 --retry 2 \
        --header 'Accept: application/vnd.github+json' \
        --user-agent 'AgentType/0.1.3' --output "$2" "$1"
}
gim_validate_app() {
    local app=$1 bundle_id minimum current
    [[ ! -L $app && -d $app && -x "$app/Contents/MacOS/Hammerspoon" &&
        -x "$app/Contents/Frameworks/hs/hs" ]] || die '下载包内的 Hammerspoon.app 不完整'
    bundle_id=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$app/Contents/Info.plist") || die '无法读取应用标识'
    [[ $bundle_id == org.hammerspoon.Hammerspoon ]] || die '下载包的应用标识不符合 Hammerspoon'
    /usr/bin/codesign --verify --deep --strict \
        -R '=anchor apple generic and identifier "org.hammerspoon.Hammerspoon" and certificate leaf[subject.OU] = "VQCYSNZB89"' \
        "$app" || die 'Hammerspoon 官方签名校验失败；未安装应用'
    minimum=$(/usr/libexec/PlistBuddy -c 'Print :LSMinimumSystemVersion' "$app/Contents/Info.plist") || die '无法读取最低 macOS 版本'
    current=$(/usr/bin/sw_vers -productVersion)
    autoload -Uz is-at-least
    is-at-least "$minimum" "$current" || die "此 Hammerspoon 版本需要 macOS $minimum 或更高；本机为 $current"
}
gim_install_github() {
    local app_parent=$1 download_dir="$stage_dir/hammerspoon-download" metadata version url expected actual entry
    local -a release
    mkdir "$download_dir"
    print -- '正在读取 Hammerspoon 官方 GitHub 最新稳定版…'
    gim_fetch 'https://api.github.com/repos/Hammerspoon/hammerspoon/releases/latest' "$download_dir/release.json" ||
        die '无法读取官方 GitHub 发行信息，请检查网络或 GitHub 访问限制后重试；未修改配置。'
    metadata=$(/usr/bin/osascript -l JavaScript "$package_dir/scripts/release-asset.js" "$download_dir/release.json") ||
        die '官方发行信息无法识别；未修改配置。'
    release=("${(@f)metadata}")
    (( ${#release} == 3 )) || die '官方发行信息格式错误'
    version=$release[1]; url=$release[2]; expected=$release[3]
    print -r -- "正在下载 Hammerspoon $version…"
    gim_fetch "$url" "$download_dir/Hammerspoon.zip" || die 'Hammerspoon 下载失败；未修改配置。'
    actual=$(/usr/bin/shasum -a 256 "$download_dir/Hammerspoon.zip")
    actual=${actual%% *}
    [[ $actual == $expected ]] || die 'Hammerspoon 下载文件的 SHA-256 不匹配；未安装应用。'
    /usr/bin/unzip -Z1 "$download_dir/Hammerspoon.zip" > "$download_dir/entries.txt" || die '无法读取 Hammerspoon ZIP'
    while IFS= read -r entry; do
        [[ -n $entry && $entry != /* && $entry != '..' && $entry != ../* && $entry != */../* && $entry != */.. ]] ||
            die 'Hammerspoon ZIP 含不安全路径；未解压。'
    done < "$download_dir/entries.txt"
    /usr/bin/ditto -x -k "$download_dir/Hammerspoon.zip" "$download_dir/extracted" || die 'Hammerspoon 解压失败'
    local app="$download_dir/extracted/Hammerspoon.app"
    gim_validate_app "$app"
    gim_copy_app "$app" "$app_parent"
}
gim_copy_app() (
    # A private sibling staging directory keeps a failed copy from looking installed.
    local app=$1 app_parent=$2 pending=''
    mkdir -p "$app_parent"
    [[ ! -e "$app_parent/Hammerspoon.app" && ! -L "$app_parent/Hammerspoon.app" ]] ||
        die '安装过程中发现已有 Hammerspoon.app；未覆盖，请重新运行安装工具。'
    pending=$(mktemp -d "$app_parent/.GhosttyInputMethod-Hammerspoon.XXXXXXXX")
    trap 'rm -rf -- "$pending"' EXIT
    trap 'exit 130' INT
    trap 'exit 143' HUP TERM
    /usr/bin/ditto "$app" "$pending/Hammerspoon.app" || die '复制 Hammerspoon 失败'
    # Foundation move fails if the destination exists; it never nests or overwrites it.
    /usr/bin/osascript -l JavaScript "$package_dir/scripts/move-app.js" \
        "$pending/Hammerspoon.app" "$app_parent/Hammerspoon.app" || die '安装 Hammerspoon 失败；没有覆盖已有应用。'
)
gim_ensure_hammerspoon() {
    local brew_bin='' app_parent
    if gim_find_hammerspoon; then
        print -r -- "复用已安装的 Hammerspoon: $REPLY"
        return
    fi
    gim_find_brew && brew_bin=$REPLY
    gim_application_dir
    app_parent=$REPLY
    if (( dry_run )); then
        if [[ -n $brew_bin ]]; then
            print -r -- "预览：缺少 Hammerspoon，正式安装将使用 Homebrew: $brew_bin"
        else
            print -- '预览：缺少 Hammerspoon 和 Homebrew，正式安装将从官方 GitHub Release 下载。'
        fi
        print -r -- "预览安装位置: $app_parent/Hammerspoon.app（未下载、未安装）"
        return
    fi
    if [[ -n $brew_bin ]]; then
        print -- '未找到 Hammerspoon，正在通过 Homebrew 安装…'
        "$brew_bin" install --cask --appdir="$app_parent" hammerspoon ||
            die 'Homebrew 安装 Hammerspoon 失败；请按上方错误修复后重试。插件配置未修改。'
    else
        print -- '未找到 Homebrew，将从 Hammerspoon 官方 GitHub Release 安装。'
        gim_install_github "$app_parent"
    fi
    gim_find_hammerspoon || die '安装命令结束，但未找到完整的 Hammerspoon.app；插件配置未修改。'
    print -r -- "Hammerspoon 已安装: $REPLY"
}
