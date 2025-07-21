# TODO: 实现简单的删除操作
#     read -r http_code speed_download <<< $(curl -sL --connect-timeout ${CONNECT_TIMEOUT} --max-time ${MAX_TIME} -o /dev/null -w "%{http_code} %{speed_download}" "${check_url}")
#         printf "速度: %'d B/s\n" "$speed_download"
#     echo "速度约为: $(numfmt --to=iec-i --suffix=B/s ${MAX_SPEED})"
# latency_ms=$(awk -v ttfb="$ttfb" 'BEGIN { printf "%.2f", ttfb * 1000 }')
# awk -v start="$start_time" -v end="$end_time" 'BEGIN { printf "%.2f", (end - start) * 1000 
    # mapfile -d '' files < <(find /tmp/logs -type f -name "*.log" -print0)


    # 专为删除大文件优化，避免I/O风暴
# 用法: delete_large_files "my_large_files_array"
function delete_large_files() {
    declare -n large_files="$1"

    for file in "${large_files[@]}"; do
        if [ -f "$file" ]; then
            echo "正在处理大文件: $file"
            # 1. 立即将文件大小截断为0，瞬间释放磁盘空间，I/O开销极小
            truncate -s 0 "$file"
            # 2. 删除这个已经为空的文件，操作非常快
            rm -f "$file"
            echo "$file 已被高效删除。"
        else
            echo "警告: $file 不是一个有效的文件。"
        fi
    done
}


extglob	开启扩展模式匹配 ?(), *(), +(), @(), !()	排除文件 !(), 匹配多种后缀 @()
globstar	开启递归匹配 **	替代简单的 find 命令
nullglob	无匹配时扩展为空	编写健壮的脚本，避免 for 循环处理不存在的文件
failglob	无匹配时报错并终止命令	严格模式脚本，确保文件必须存在
dotglob	让 * 匹配隐藏文件	处理用户家目录下的所有配置文件
nocaseglob	匹配不区分大小写	在混合大小写文件名的环境中工作

下面给出一个示例脚本，整合了前面提出的各项改进。此脚本在原有功能基础上，主要增强了以下几点：  
• 增加了一些 Shell 选项来增强鲁棒性。  
• 针对文件名中可能包含逗号或其他特殊字符，改为用制表符 (tab) 作为 CSV 日志分隔符，并在写入 CSV 前对字段进行转义。  
• 防止同名文件在同一时间戳下冲突，为文件名添加随机字符串后缀。  
• 在可能不具备 GNU date/numfmt 等命令的环境下进行简单的兼容性检测。  
• 提供了一个函数 check_command 来检测依赖的外部命令。  
• 在关键操作前进行必要的有效性检查。  

您可根据实际需求对脚本做进一步增删改动。  

────────────────────────────
#!/usr/bin/env bash
#
# srm.sh - Enhanced Safe Remove Script

# ------------------------ Shell Options -------------------------
# 遇到错误立即退出
set -o errexit
# 遇到未定义变量时立即退出
set -o nounset
# 管道中任意一处报错则整条命令报错
set -o pipefail

# --------------------- Minimal Bash Version ---------------------
# 本示例使用到 declare -n，需要 bash>=4.3
if (( BASH_VERSINFO[0] < 4 || ( BASH_VERSINFO[0] == 4 && BASH_VERSINFO[1] < 3 ) )); then
    echo "This script requires bash >= 4.3. Detected version: ${BASH_VERSION}."
    exit 1
fi

# ------------------- External Command Check ---------------------
# 简单检测一些依赖命令是否可用，没有则给出提示
function check_command(){
    local cmd="$1"
    if ! command -v "$cmd" &> /dev/null; then
        echo "Error: '$cmd' command not found, but is required."
        exit 1
    fi
}

# 在脚本中用到的常用外部命令进行检查
check_command "mv"
check_command "rm"
check_command "awk"
check_command "sed"
check_command "file"
check_command "readlink"
check_command "basename"
check_command "dirname"
check_command "stat"
check_command "du"
check_command "xargs"

# numfmt 与 GNU date 在部分系统上可能没有，如 macOS/BSD
# 简单兼容: 若没有 numfmt，则使用awk做一个简易(B)到字节的转换
function custom_numfmt() {
    local input="$1"
    if command -v numfmt &>/dev/null; then
        # 若系统有 numfmt，直接用
        numfmt --from=iec "$input"
    else
        # 没有 numfmt，就只支持无单位或给定M(做简单乘法)
        # 也可以扩展对GB, KB等进行判断
        if [[ "$input" =~ [0-9]+[Mm]$ ]]; then
            local number="${input//[Mm]/}"
            echo $(( number * 1024 * 1024 ))
        else
            # 如果没有单位，就直接返回
            echo "$input"
        fi
    fi
}

# date --iso-8601=seconds 在部分系统不可用，做一个fallback
function get_iso_datetime(){
    if date --iso-8601=seconds &>/dev/null; then
        date --iso-8601=seconds
    else
        # fallback: RFC-3339 或类似格式
        date "+%Y-%m-%dT%H:%M:%S%z"
    fi
}

# ----------------------- Logging Function ------------------------
function log_message(){
    local level="$1"
    local message="$2"
    local component="${3:-main}"

    printf 'timestamp=%s level=%s component=%s pid=%d message=%s\n' \
        "$(get_iso_datetime)" \
        "$level" \
        "$component" \
        "$$" \
        "$message"
}

# ------------------- CSV Log Management -------------------------
# 改进：这里使用制表符(TAB)作为分隔符，以减少文件名中逗号的干扰。
# 若要更彻底，可增加对制表符的转义，或使用更健壮的CSV库。
function manage_csv_log(){
    local _IFS=$'\t'

    # 统一使用TAB来分隔字段
    function _escape_field(){
        # 若字段内含TAB或换行，就简单替换为" "(空格)或做其它转义处理
        # 这里做一个最简单的替换
        tr '\t' ' ' | tr '\n' ' '
    }

    function _log_write(){
        # 依次对传入参数进行转义，再用TAB拼起来
        local out_fields=()
        for field in "$@"; do
            out_fields+=( "$(echo -n "$field" | _escape_field)" )
        done
        # 这里 >> "$LOG_FILE" 表示追加写入
        ( IFS=$_IFS; printf "%s\n" "${out_fields[*]}" ) >> "$LOG_FILE"
    }

    function _log_read(){
        # 因为我们使用制表符分隔，awk -F'\t' 处理
        local search_string="$1"
        awk -v str="$search_string" -F'\t' 'index($0, str) > 0' "$LOG_FILE"
    }

    function _log_delete(){
        # 用 sed 删除行：注意只要行中出现filename即可
        # 同样地, 因为TAB分隔, 这里还是可能需要前置替换TAB
        local filename_to_delete="$1"
        sed -i "/$filename_to_delete/d" "$LOG_FILE"
    }

    case "$1" in
        _log_delete)
            shift; _log_delete "$1"
            ;;
        _log_read)
            shift; _log_read "$1"
            ;;
        _log_write)
            shift; _log_write "$@"
            ;;
    esac
}

# --------------- Environment Setup & Configuration --------------
function setup_environment(){
    # 配置文件加载
    if [[ -f "$HOME/.config/srm/config" ]]; then
        # shellcheck source=/dev/null
        . "$HOME/.config/srm/config"
    elif [[ -f "$HOME/.srmConfig" ]]; then
        # shellcheck source=/dev/null
        . "$HOME/.srmConfig"
    elif [[ -f ".srmConfig" ]]; then
        # shellcheck source=/dev/null
        . .srmConfig
    fi

    : "${TRASH_DIR:="$HOME/.trash"}"
    : "${SIZE_THRESHOLD_MB:="10M"}"
    : "${LOG_FILE:="$HOME/.trash/trash.csv"}"

    SIZE_THRESHOLD_BYTES="$(custom_numfmt "$SIZE_THRESHOLD_MB")"

    # 若回收站不存在，创建之
    if [[ ! -d "$TRASH_DIR" ]]; then
        mkdir -p "$TRASH_DIR"
    fi

    # 日志文件若不存在或为空，则写入表头。以TAB分隔。
    if [[ ! -f "$LOG_FILE" || ! -s "$LOG_FILE" ]]; then
        touch "$LOG_FILE"
        local csv_header="file_name	original_dir	trashed_filename	mime_type	trashed_time"
        printf "%s\n" "$csv_header" > "$LOG_FILE"
    fi
}

# --------------------- Trash & Delete Logic ----------------------
# 将小于等于阈值的文件放入trash_queue，其余放入delete_queue
function process_targets(){
    declare -n trash_queue_ref="$1"
    declare -n delete_queue_ref="$2"

    for target_path in "${TARGET_FILE[@]}"; do
        local absolute_path
        absolute_path="$(readlink -f "$target_path")" || {
            log_message "ERROR" "Failed to get absolute path: $target_path"
            exit 1
        }

        # 判断是否存在
        if [[ ! -e "$absolute_path" ]]; then
            log_message "ERROR" "File/Dir not found: $absolute_path"
            exit 1
        fi

        # 获取文件/目录大小
        local size_bytes=0
        if [[ -f "$absolute_path" ]]; then
            size_bytes="$(stat -c%s "$absolute_path")"
        elif [[ -d "$absolute_path" ]]; then
            size_bytes="$(du -bs "$absolute_path" | awk '{print $1}')"
        fi

        # 比较大小
        if (( size_bytes <= SIZE_THRESHOLD_BYTES )); then
            trash_queue_ref+=( "$absolute_path" )
        else
            delete_queue_ref+=( "$absolute_path" )
        fi
    done

    # 将trash_queue_ref中的文件/目录移动到回收站
    for file_to_trash in "${trash_queue_ref[@]}"; do
        local original_basename
        original_basename="$(basename "$file_to_trash")"
        local original_dirname
        original_dirname="$(dirname "$file_to_trash")"
        local timestamp
        timestamp="$(date +%s)"  # 只取秒级的即可
        local random_suffix
        # 生成随机字符串以减少命名冲突
        random_suffix="$(head -c 8 /dev/urandom | base64 | tr -dc 'A-Za-z0-9' 2>/dev/null || true)"
        local trashed_filename="${original_basename}_${timestamp}_${random_suffix}"
        local mime_type
        mime_type="$(file -b --mime-type "$file_to_trash")"
        local trashed_time
        trashed_time="$(date "+%Y-%m-%d %H:%M:%S" -d "@$timestamp" 2>/dev/null || date "+%Y-%m-%d %H:%M:%S")"

        if mv "$file_to_trash" "${TRASH_DIR}/${trashed_filename}"; then
            manage_csv_log _log_write "$original_basename" "$original_dirname" "$trashed_filename" "$mime_type" "$trashed_time"
            printf "."
        else
            log_message "ERROR" "Failed to move file to trash: $file_to_trash"
        fi
    done
    printf "\n"
}

# ------------------ Permanently Delete Large Files ----------------
function delete_large_files(){
    declare -n delete_queue_ref="$1"

    # 避免误删根目录或$HOME等高危位置
    for item in "${delete_queue_ref[@]}"; do
        if [[ "$item" == "/" || "$item" == "$HOME" ]]; then
            log_message "ERROR" "Refuse to delete dangerous path: $item"
            return 1
        fi
    done

    if (( "${#delete_queue_ref[@]}" > 0 )); then
        printf "%s\0" "${delete_queue_ref[@]}" | xargs -0 rm -rf
    fi
}

# ---------------------- Restore from Trash ------------------------
function restore_from_trash(){
    local search_term="$1"
    local -a trash_items
    # 读取 CSV 里所有能匹配到用户搜索字符串的行
    mapfile -t trash_items < <( manage_csv_log _log_read "$search_term" )

    if (( "${#trash_items[@]}" == 0 )); then
        log_message "ERROR" "No files found to restore matching '$search_term'"
        exit 1
    fi

    for i in "${!trash_items[@]}"; do
        local line="${trash_items[$i]}"
        # 根据制表符分割
        IFS=$'\t' read -r original_name original_dir trashed_name mime_type trashed_time <<< "$line"
        printf '%d) %s (from %s, trashed on %s)\n' "$i" "$original_name" "$original_dir" "$trashed_time"
    done

    read -r -p "Please enter the number of the file you want to restore: " user_choice

    if ! [[ "$user_choice" =~ ^[0-9]+$ ]] || (( user_choice < 0 || user_choice >= ${#trash_items[@]} )); then
        log_message "ERROR" "Invalid selection: $user_choice"
        exit 1
    fi

    local selected_item_csv="${trash_items[$user_choice]}"
    local selected_original_name selected_original_dir selected_trashed_name selected_mime_type

    IFS=$'\t' read -r selected_original_name selected_original_dir selected_trashed_name selected_mime_type _ <<< "$selected_item_csv"

    local src="${TRASH_DIR}/${selected_trashed_name}"
    local dst="${selected_original_dir}/${selected_original_name}"

    # 还原文件
    if mv -i "$src" "$dst"; then
        manage_csv_log _log_delete "$selected_trashed_name"
        log_message "INFO" "Successfully restored '$dst'"
    else
        log_message "ERROR" "Failed to restore '$src' -> '$dst'"
    fi
}

# ---------------------- Empty Trash Bin ---------------------------
function empty_trash_bin(){
    # 确认清空回收站
    read -r -p "Are you sure you want to empty the Recycle Bin?[y/n]: " input
    if ! [[ "$input" == "y" || "$input" == "Y" ]]; then
        return 0
    fi

    # 做一下简单的风险检查
    if [[ -z "$TRASH_DIR" || "$TRASH_DIR" == "/" || "$TRASH_DIR" == "$HOME" ]]; then
        log_message "ERROR" "Empty trash aborted: TRASH_DIR is '$TRASH_DIR' (protected location)"
        return 1
    fi

    if rm -rf "$TRASH_DIR"/*; then
        log_message "INFO" "Trash bin has been emptied successfully"
    else
        log_message "ERROR" "Failed to empty the trash bin"
        return 1
    fi
}

# ------------------ Clean Old Files from Trash --------------------
function clean_old_trash_files(){
    local days_old="${1:?Please provide the number of days.}"
    # 注意：-mindepth 1 避免删除自己目录
    # 这里使用 find -mtime 判断文件最后修改时间大于days_old
    # 若需要按照创建时间或atime，需要改用 -ctime 或 -atime 参数
    find "$TRASH_DIR" -mindepth 1 -mtime +"${days_old}" -exec rm -rf {} +
}

# ------------------------ Print Usage -----------------------------
function print_usage(){
    echo -e "
Usage: $(basename "$0") [OPTION]... [FILE]...
Safely removes file(s) by moving them to a trash bin.

  -e        Empty the trash bin completely.
  -c DAYS   Clean trash files older than DAYS.
  -r NAME   Restore a file from trash. NAME can be a partial filename.
  -f FILE   Forcefully and permanently delete FILE (bypasses trash).
  -h        Show this help message.

If no options are given, any FILE arguments will be moved to the trash bin.
"
}

# --------------------------- Main Logic ---------------------------
function main(){
    TARGET_FILE=("$@")
    if  (( "${#TARGET_FILE[@]}" == 0 )); then
        print_usage
        exit 0
    fi

    setup_environment

    declare -a trash_queue=()
    declare -a direct_delete_queue=()

    process_targets trash_queue direct_delete_queue
    delete_large_files direct_delete_queue
}

# ------------------------- Parse Options --------------------------
declare -a force_delete_queue=()

while getopts "hec:r:f:" opt; do
    case "$opt" in
        h)
            print_usage
            exit 0
            ;;
        e)
            setup_environment
            empty_trash_bin
            exit $?
            ;;
        c)
            setup_environment
            clean_old_trash_files "$OPTARG"
            exit $?
            ;;
        r)
            setup_environment
            restore_from_trash "$OPTARG"
            exit $?
            ;;
        f)
            force_delete_queue+=( "$OPTARG" )
            ;;
        *)
            print_usage
            exit 1
            ;;
    esac
done
shift $((OPTIND - 1))

if (( "${#force_delete_queue[@]}" > 0 )); then
    printf "Forcefully delete %d item(s)...\n" "${#force_delete_queue[@]}"
    printf "%s\0" "${force_delete_queue[@]}" | xargs -0 rm -rf
    exit 0
fi

main "$@"
────────────────────────────

上述脚本主流程与原脚本类似，只是在各重要函数中添加了若干改进，以增强在日常使用可能出现的边界场景下的正常运行和错误提示。若您的使用环境中 GNU 工具比较齐全，可相应地简化这段超兼容逻辑。  

若您有更多定制化需求(例如日志记录需要 JSON 格式、对文件名进行更复杂的转义或对多操作系统支持等等)，都可以以此为基础进一步扩展。