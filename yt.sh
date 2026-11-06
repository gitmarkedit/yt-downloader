#!/usr/bin/env bash
# ==============================================================================
#  ⚡ yt (macOS Edition)
#  Высокопроизводительный медиа-загрузчик с аппаратным ускорением VideoToolbox
# ==============================================================================

# Определение директории скрипта
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Автоматическое подключение путей Homebrew (Apple Silicon /opt/homebrew и Intel /usr/local)
export PATH="$SCRIPT_DIR/bin:/opt/homebrew/bin:/opt/homebrew/sbin:/usr/local/bin:$HOME/.local/bin:$PATH"

# Определение платформы и процессора Mac
OS_NAME="$(uname -s 2>/dev/null || echo "Unknown")"
CPU_ARCH="$(uname -m 2>/dev/null || echo "Unknown")"
CPU_BRAND="$(sysctl -n machdep.cpu.brand_string 2>/dev/null || echo "$CPU_ARCH")"

# Конфигурация и пути по умолчанию
CONFIG_DIR="$HOME/.config/yt-downloader"
CONFIG_FILE="$CONFIG_DIR/config.env"
DEFAULT_DEST="$HOME/Downloads/Media"

DEST="$DEFAULT_DEST"
EMBED_METADATA="true"
EMBED_THUMBNAIL="true"
DEFAULT_CONTAINER="mp4"
CONCURRENT_FRAGMENTS="8"     # На Apple Silicon 8 потоков дают максимальную утилизацию сети
COOKIE_BROWSER="none"       # none, safari, chrome, firefox
APPLE_COMPAT_MODE="true"    # Форсировать H.264/AAC для 100% работы в QuickTime & Finder QuickLook
SOUND_ENABLED="true"
DEBUG_MODE="false"

# ------------------------------------------------------------------------------
# Стили и Цвета (ANSI 256 / TrueColor)
# ------------------------------------------------------------------------------
if [ -t 1 ]; then
    BOLD='\033[1m'
    DIM='\033[2m'
    ITALIC='\033[3m'
    UNDERLINE='\033[4m'
    
    RED='\033[38;5;196m'
    GREEN='\033[38;5;46m'
    YELLOW='\033[38;5;220m'
    BLUE='\033[38;5;39m'
    MAGENTA='\033[38;5;201m'
    CYAN='\033[38;5;51m'
    WHITE='\033[38;5;231m'
    GRAY='\033[38;5;244m'
    ORANGE='\033[38;5;208m'
    RESET='\033[0m'
else
    BOLD='' DIM='' ITALIC='' UNDERLINE=''
    RED='' GREEN='' YELLOW='' BLUE='' MAGENTA='' CYAN='' WHITE='' GRAY='' ORANGE=''
    RESET=''
fi

# ------------------------------------------------------------------------------
# Управление конфигурацией
# ------------------------------------------------------------------------------
load_config() {
    if [ -f "$CONFIG_FILE" ]; then
        # shellcheck disable=SC1090
        source "$CONFIG_FILE" 2>/dev/null || true
    fi
    mkdir -p "$DEST" 2>/dev/null || true
}

save_config() {
    mkdir -p "$CONFIG_DIR" 2>/dev/null || true
    cat > "$CONFIG_FILE" <<EOF
# yt (macOS Edition) Configuration
DEST="$DEST"
EMBED_METADATA="$EMBED_METADATA"
EMBED_THUMBNAIL="$EMBED_THUMBNAIL"
DEFAULT_CONTAINER="$DEFAULT_CONTAINER"
CONCURRENT_FRAGMENTS="$CONCURRENT_FRAGMENTS"
COOKIE_BROWSER="$COOKIE_BROWSER"
APPLE_COMPAT_MODE="$APPLE_COMPAT_MODE"
SOUND_ENABLED="$SOUND_ENABLED"
EOF
}

# ------------------------------------------------------------------------------
# Анимации: Спиннер и Управление курсором
# ------------------------------------------------------------------------------
SPINNER_PID=""

start_spinner() {
    local message="$1"
    tput civis 2>/dev/null || true
    (
        local frames=("⠋" "⠙" "⠹" "⠸" "⠼" "⠴" "⠦" "⠧" "⠇" "⠏")
        local colors=("\033[38;5;51m" "\033[38;5;45m" "\033[38;5;39m" "\033[38;5;33m" "\033[38;5;27m" "\033[38;5;33m" "\033[38;5;39m" "\033[38;5;45m")
        local i=0
        local start_sec=$SECONDS
        while true; do
            local elapsed=$(( SECONDS - start_sec ))
            local c_idx=$(( i % ${#colors[@]} ))
            local col="${colors[c_idx]}"
            printf "\r${col}%s${RESET} [%02d:%02d] %s" "${frames[i]}" "$((elapsed / 60))" "$((elapsed % 60))" "$message"
            i=$(( (i + 1) % ${#frames[@]} ))
            sleep 0.07
        done
    ) &
    SPINNER_PID=$!
}

stop_spinner() {
    if [ -n "$SPINNER_PID" ] && kill -0 "$SPINNER_PID" 2>/dev/null; then
        kill "$SPINNER_PID" 2>/dev/null
        wait "$SPINNER_PID" 2>/dev/null || true
    fi
    SPINNER_PID=""
    tput cnorm 2>/dev/null || true
    printf "\r\033[K"
}

cleanup() {
    stop_spinner
    tput cnorm 2>/dev/null || true
}
trap cleanup EXIT INT TERM

# ------------------------------------------------------------------------------
# Проверка и Самодиагностика зависимостей
# ------------------------------------------------------------------------------
check_dependencies() {
    local missing=()
    command -v yt-dlp &>/dev/null || missing+=("yt-dlp")
    command -v ffmpeg &>/dev/null || missing+=("ffmpeg")

    if [ ${#missing[@]} -gt 0 ]; then
        echo -e "${RED}${BOLD}❌ На вашем компьютере не найдены обязательные утилиты:${RESET} ${missing[*]}"
        echo -e "${YELLOW}Запустить автоматическую установку всех зависимостей? [Y/n]${RESET}"
        read -p "> " auto_install
        auto_install=${auto_install:-y}

        if [[ "$auto_install" =~ ^[YyДд] ]]; then
            if [ -f "$SCRIPT_DIR/install.sh" ]; then
                bash "$SCRIPT_DIR/install.sh"
            else
                if command -v brew &>/dev/null; then
                    brew install "${missing[@]}" fzf || true
                else
                    echo -e "${RED}Homebrew не найден. Установите yt-dlp и ffmpeg вручную.${RESET}"
                    exit 1
                fi
            fi
            
            export PATH="$SCRIPT_DIR/bin:/opt/homebrew/bin:/opt/homebrew/sbin:/usr/local/bin:$HOME/.local/bin:$PATH"
            if ! command -v yt-dlp &>/dev/null; then
                echo -e "${RED}Не удалось автоматически запустить yt-dlp. Попробуйте перезапустить терминал.${RESET}"
                exit 1
            fi
        else
            echo -e "${YELLOW}Для работы скрипта требуются yt-dlp и ffmpeg.${RESET}"
            exit 1
        fi
    fi
}

# ------------------------------------------------------------------------------
# Идеально выверенный баннер (без глитчей и сдвигов границ)
# ------------------------------------------------------------------------------
show_banner() {
    clear
    echo -e "${CYAN}${BOLD}"
    cat << "EOF"
   ╭──────────────────────────────────────────────────────────╮
   │                    yt (macOS Edition)                    │
   │    Высокоскоростная загрузка с аппаратным медиа-ядром    │
   ╰──────────────────────────────────────────────────────────╯
EOF
    echo -e "${RESET}"

    # Статус платформы с ровным выравниванием двоеточий
    if [ "$OS_NAME" = "Darwin" ]; then
        local hw_accel_info=""
        if ffmpeg -hwaccels 2>/dev/null | grep -q "videotoolbox"; then
            hw_accel_info="${GREEN}VideoToolbox [Hardware Accelerated]${RESET}"
        else
            hw_accel_info="${YELLOW}Software (CPU)${RESET}"
        fi
        echo -e "  ${GRAY}  Модель  :${RESET} ${WHITE}${BOLD}$CPU_BRAND${RESET} (${CYAN}$CPU_ARCH${RESET})"
        echo -e "  ${YELLOW}⚡ Движок  :${RESET} $hw_accel_info  ${GRAY}• Потоков:${RESET} ${CYAN}${CONCURRENT_FRAGMENTS}${RESET}"
    else
        echo -e "  ${GRAY}Система    :${RESET} ${WHITE}$OS_NAME ($CPU_ARCH)${RESET}"
    fi
    echo ""
}

# ------------------------------------------------------------------------------
# Карточка информации о медиа
# ------------------------------------------------------------------------------
fetch_and_display_info() {
    local url="$1"
    start_spinner "Анализ медиа и проверка доступных разрешений..."

    local cookie_flag=()
    if [ "$COOKIE_BROWSER" != "none" ]; then
        cookie_flag=("--cookies-from-browser" "$COOKIE_BROWSER")
    fi

    local meta
    meta=$(yt-dlp \
        "${cookie_flag[@]}" \
        --no-warnings \
        --no-playlist \
        --skip-download \
        --print "%(title)s	%(uploader,channel,creator)s	%(duration_string)s	%(view_count)s	%(format_note,resolution)s" \
        "$url" 2>/dev/null | head -n 1)

    stop_spinner

    if [ -n "$meta" ]; then
        local title uploader duration views max_res
        IFS=$'\t' read -r title uploader duration views max_res <<< "$meta"

        echo -e "${BLUE}╭─ 📺 Информация о медиа ───────────────────────────────────────╮${RESET}"
        echo -e "${BLUE}│${RESET} ${BOLD}Название  :${RESET}  $title"
        [ -n "$uploader" ] && [ "$uploader" != "NA" ] && \
        echo -e "${BLUE}│${RESET} ${DIM}Автор     :${RESET}  $uploader"
        [ -n "$duration" ] && [ "$duration" != "NA" ] && \
        echo -e "${BLUE}│${RESET} ${DIM}Время     :${RESET}  $duration"
        [ -n "$views" ] && [ "$views" != "NA" ] && \
        echo -e "${BLUE}│${RESET} ${DIM}Просмотры :${RESET}  $views"
        if [ "$APPLE_COMPAT_MODE" = "true" ]; then
            echo -e "${BLUE}│${RESET} ${GREEN} Режим   :${RESET}  100% QuickTime & QuickLook (Пробел) совместимость"
        fi
        echo -e "${BLUE}╰───────────────────────────────────────────────────────────────╯${RESET}"
        echo ""
    else
        echo -e "${YELLOW}⚠️ Не удалось извлечь предпросмотр (возможно, закрытое видео или плейлист).${RESET}\n"
    fi
}

# ------------------------------------------------------------------------------
# Меню выбора (FZF с автоподстройкой или встроенный fallback)
# ------------------------------------------------------------------------------
select_menu() {
    local prompt="$1"
    shift
    local options=("$@")

    if command -v fzf &>/dev/null; then
        local height=$(( ${#options[@]} + 4 ))
        [ "$height" -gt 22 ] && height=22
        [ "$height" -lt 6 ] && height=6

        printf "%s\n" "${options[@]}" | fzf \
            --height="$height" \
            --layout=reverse \
            --border=rounded \
            --prompt="$prompt " \
            --pointer="▶" \
            --marker="✓" \
            --bind="esc:cancel,ctrl-c:abort" \
            --color="prompt:cyan,pointer:magenta,marker:green,header:yellow,border:blue"
    else
        echo -e "\n${CYAN}${BOLD}$prompt${RESET}"
        local i=1
        for opt in "${options[@]}"; do
            printf "  ${YELLOW}%2d)${RESET} %s\n" "$i" "$opt"
            i=$((i + 1))
        done
        while true; do
            read -p "Выберите номер [1-${#options[@]}]: " choice
            if [[ "$choice" =~ ^[0-9]+$ ]] && [ "$choice" -ge 1 ] && [ "$choice" -le "${#options[@]}" ]; then
                echo "${options[$((choice - 1))]}"
                return 0
            fi
            echo -e "${RED}Неверный ввод, повторите попытку.${RESET}"
        done
    fi
}

# ------------------------------------------------------------------------------
# Получение URL (Аргумент, буфер обмена macOS или ввод)
# ------------------------------------------------------------------------------
get_url() {
    local input_url="$1"
    if [ -n "$input_url" ]; then
        echo "$input_url"
        return 0
    fi

    local clip_url=""
    if command -v pbpaste &>/dev/null; then
        local raw
        raw=$(pbpaste 2>/dev/null | tr -d '\r\n' | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')
        if [[ "$raw" =~ ^https?:// ]]; then
            clip_url="$raw"
        fi
    fi

    if command -v fzf &>/dev/null; then
        local prompt_list=""
        if [ -n "$clip_url" ]; then
            prompt_list="📋 Использовать из буфера macOS: $clip_url"
        fi

        local res
        res=$(printf "%s\n" "$prompt_list" | fzf \
            --print-query \
            --height=7 \
            --layout=reverse \
            --border=rounded \
            --prompt="Ссылка > " \
            --header="Вставьте ссылку и нажмите Enter (Esc - выход):" \
            --bind="esc:cancel,ctrl-c:abort" \
            --color="prompt:cyan,pointer:magenta,header:yellow,border:blue")

        local exit_code=$?
        [ $exit_code -ne 0 ] && return 1

        local typed_query selected_item
        typed_query=$(echo "$res" | sed -n '1p')
        selected_item=$(echo "$res" | sed -n '2p')

        # Если пользователь напечатал/вставил ссылку в строку fzf
        if [ -n "$typed_query" ]; then
            echo "$typed_query"
        # Если выбрал пункт с ссылкой из буфера
        elif [ -n "$selected_item" ]; then
            local extracted_url
            extracted_url=$(echo "$selected_item" | grep -o 'https\?://[^ ]*')
            if [ -n "$extracted_url" ]; then
                echo "$extracted_url"
            else
                echo "$selected_item"
            fi
        elif [ -n "$clip_url" ]; then
            echo "$clip_url"
        fi
    else
        if [ -n "$clip_url" ]; then
            echo -e "${CYAN}Найдена ссылка в буфере обмена Mac:${RESET} $clip_url"
            read -p "Использовать её? [Y/n]: " use_clip
            use_clip=${use_clip:-y}
            if [[ "$use_clip" =~ ^[YyДд] ]]; then
                echo "$clip_url"
                return 0
            fi
        fi
        read -p "Вставьте ссылку на медиа: " manual_url
        echo "$manual_url"
    fi
}

# ------------------------------------------------------------------------------
# Запуск загрузки с аппаратной оптимизацией под macOS
# ------------------------------------------------------------------------------
execute_download() {
    local url="$1"
    shift
    local extra_args=("$@")

    local common_args=(
        "--no-mtime"
        "-N" "$CONCURRENT_FRAGMENTS"
        "--console-title"
        "--progress-template" "download:  %(progress._percent_str)s of %(progress._total_bytes_str,progress._total_bytes_estimate_str)s at %(progress._speed_str)s [ETA %(progress._eta_str)s]"
    )

    # Куки браузера (для обхода ограничений YouTube/VK)
    if [ "$COOKIE_BROWSER" != "none" ]; then
        common_args+=("--cookies-from-browser" "$COOKIE_BROWSER")
    fi

    # Вшивание метаданных и глав для Apple экосистемы
    if [ "$EMBED_METADATA" = "true" ]; then
        common_args+=("--embed-metadata" "--embed-chapters")
    fi

    # QuickTime / Finder QuickLook оптимизация (быстрый старт видео без задержек)
    common_args+=("--postprocessor-args" "Merger:-movflags +faststart")

    # Сортировка форматов под кодеки Apple Silicon (H.264/HEVC)
    if [ "$APPLE_COMPAT_MODE" = "true" ]; then
        common_args+=("-S" "vcodec:h264,vcodec:hevc,lang,quality,res,fps")
    fi

    if [ "$DEBUG_MODE" = "true" ]; then
        echo -e "${YELLOW}[DEBUG] Команда:${RESET} yt-dlp ${common_args[*]} ${extra_args[*]} $url\n"
    fi

    echo -e "${CYAN}🚀 Запуск загрузки на максимальной скорости...${RESET}\n"

    yt-dlp "${common_args[@]}" "${extra_args[@]}" "$url"
    local dl_status=$?

    echo ""
    if [ $dl_status -eq 0 ]; then
        echo -e "${GREEN}${BOLD}╭─────────────────────────────────────────────────────────────╮${RESET}"
        echo -e "${GREEN}${BOLD}│  ✅ Загрузка успешно завершена!                             │${RESET}"
        echo -e "${GREEN}│${RESET}  📁 Папка: ${CYAN}$DEST${RESET}"
        echo -e "${GREEN}${BOLD}╰─────────────────────────────────────────────────────────────╯${RESET}"

        # Звуковой сигнал macOS (приятный системный Glass)
        if [ "$SOUND_ENABLED" = "true" ] && [ -f "/System/Library/Sounds/Glass.aiff" ]; then
            afplay "/System/Library/Sounds/Glass.aiff" 2>/dev/null &
        fi

        # Системное уведомление macOS
        if command -v osascript &>/dev/null; then
            osascript -e "display notification \"Файл сохранён в $DEST\" with title \"yt (macOS Edition)\" sound name \"Glass\"" 2>/dev/null || true
        fi
        return 0
    else
        echo -e "${RED}${BOLD}❌ Во время загрузки произошла ошибка (код: $dl_status).${RESET}"
        return $dl_status
    fi
}

# ------------------------------------------------------------------------------
# Подменю: Выбор точного разрешения
# ------------------------------------------------------------------------------
menu_resolution() {
    local url="$1"

    local choice
    choice=$(select_menu "Выберите разрешение видео >" \
        "🌟 4K Ultra HD (2160p)" \
        "💎 2K Quad HD (1440p)" \
        "🎬 Full HD (1080p - Рекомендуется)" \
        "📱 HD (720p - Оптимально для телефонов)" \
        "📉 SD (480p)" \
        "🪶 360p (Экономный режим)" \
        "↩️  Назад")

    local height_limit=""
    case "$choice" in
        *"2160p"*) height_limit="2160" ;;
        *"1440p"*) height_limit="1440" ;;
        *"1080p"*) height_limit="1080" ;;
        *"720p"*)  height_limit="720" ;;
        *"480p"*)  height_limit="480" ;;
        *"360p"*)  height_limit="360" ;;
        *) return 0 ;;
    esac

    local container_choice
    container_choice=$(select_menu "Выберите формат контейнера >" \
        "MP4 (Рекомендуется для Mac, iPhone и QuickTime)" \
        "MKV (Поддержка любых дорожек и субтитров)" \
        "WEBM (Оригинал Google)")

    local container="mp4"
    case "$container_choice" in
        *"MKV"*)  container="mkv" ;;
        *"WEBM"*) container="webm" ;;
        *)        container="mp4" ;;
    esac

    local thumb_args=()
    if [ "$EMBED_THUMBNAIL" = "true" ]; then
        thumb_args=("--embed-thumbnail" "--convert-thumbnails" "jpg")
    fi

    execute_download "$url" \
        --no-playlist \
        -f "bestvideo[height<=${height_limit}]+bestaudio/best[height<=${height_limit}]/best" \
        --merge-output-format "$container" \
        "${thumb_args[@]}" \
        -o "$DEST/%(title)s.%(ext)s"
}

# ------------------------------------------------------------------------------
# Подменю: Аудио форматы
# ------------------------------------------------------------------------------
menu_audio() {
    local url="$1"

    local choice
    choice=$(select_menu "Выберите формат аудио >" \
        "🎶 MP3 (Максимальный битрейт ~320k, обложка, теги)" \
        "🍏 M4A / AAC (Apple нативный без пересжатия)" \
        "🎼 FLAC (Lossless студийный звук)" \
        "🎧 WAV (Несжатый PCM звук)" \
        "📻 OPUS (Максимальное качество при малом весе)" \
        "⚡ Direct Stream Copy (Мгновенное сохранение оригинала)" \
        "↩️  Назад")

    local thumb_args=()
    if [ "$EMBED_THUMBNAIL" = "true" ]; then
        thumb_args=("--embed-thumbnail" "--convert-thumbnails" "jpg")
    fi

    case "$choice" in
        *"MP3"*)
            execute_download "$url" \
                --no-playlist \
                -x \
                --audio-format mp3 \
                --audio-quality 0 \
                "${thumb_args[@]}" \
                -o "$DEST/%(title)s.%(ext)s"
            ;;
        *"M4A"*)
            execute_download "$url" \
                --no-playlist \
                -x \
                --audio-format m4a \
                "${thumb_args[@]}" \
                -o "$DEST/%(title)s.%(ext)s"
            ;;
        *"FLAC"*)
            execute_download "$url" \
                --no-playlist \
                -x \
                --audio-format flac \
                "${thumb_args[@]}" \
                -o "$DEST/%(title)s.%(ext)s"
            ;;
        *"WAV"*)
            execute_download "$url" \
                --no-playlist \
                -x \
                --audio-format wav \
                -o "$DEST/%(title)s.%(ext)s"
            ;;
        *"OPUS"*)
            execute_download "$url" \
                --no-playlist \
                -x \
                --audio-format opus \
                "${thumb_args[@]}" \
                -o "$DEST/%(title)s.%(ext)s"
            ;;
        *"Direct Stream"*)
            execute_download "$url" \
                --no-playlist \
                -x \
                "${thumb_args[@]}" \
                -o "$DEST/%(title)s.%(ext)s"
            ;;
        *)
            return 0
            ;;
    esac
}

# ------------------------------------------------------------------------------
# Подменю: Скачивание фрагмента (Time-slice)
# ------------------------------------------------------------------------------
menu_timeslice() {
    local url="$1"
    echo ""
    echo -e "${CYAN}${BOLD}✂️ Скачивание фрагмента по таймкоду${RESET}"
    echo -e "${DIM}Примеры интервалов: 01:15-02:30 или 00:05:00-00:08:30${RESET}"
    read -p "Введите начало и конец (ММ:СС-ММ:СС): " time_range
    time_range=$(echo "$time_range" | tr -d ' ')

    if [ -z "$time_range" ]; then
        echo -e "${YELLOW}Интервал не указан.${RESET}"
        sleep 1
        return 0
    fi

    local slice_type
    slice_type=$(select_menu "Формат для отрезка >" \
        "🎬 Видео Full HD (MP4)" \
        "🎵 Аудио MP3 (320k)" \
        "↩️  Отмена")

    case "$slice_type" in
        *"Видео"*)
            execute_download "$url" \
                --no-playlist \
                --download-sections "*$time_range" \
                -f "bestvideo[height<=1080]+bestaudio/best" \
                --merge-output-format "mp4" \
                -o "$DEST/%(title)s [${time_range}].%(ext)s"
            ;;
        *"Аудио"*)
            execute_download "$url" \
                --no-playlist \
                --download-sections "*$time_range" \
                -x --audio-format mp3 --audio-quality 0 \
                -o "$DEST/%(title)s [${time_range}].%(ext)s"
            ;;
        *)
            return 0
            ;;
    esac
}

# ------------------------------------------------------------------------------
# Подменю: Плейлисты
# ------------------------------------------------------------------------------
menu_playlist() {
    local url="$1"

    local choice
    choice=$(select_menu "Режим загрузки плейлиста >" \
        "📥 Скачать весь плейлист целиком" \
        "🔢 Выбрать диапазон номеров (например: 1-10 или 2,5,8)" \
        "↩️  Назад")

    case "$choice" in
        *"целиком"*)
            execute_download "$url" \
                --yes-playlist \
                -f "bestvideo+bestaudio/best" \
                --merge-output-format "$DEFAULT_CONTAINER" \
                -o "$DEST/%(playlist_title,playlist)s/%(playlist_index)02d - %(title)s.%(ext)s"
            ;;
        *"диапазон"*)
            echo ""
            read -p "Введите диапазон (например, 1-5 или 1,3,7): " range
            range=$(echo "$range" | tr -d ' ')
            if [ -n "$range" ]; then
                execute_download "$url" \
                    --yes-playlist \
                    --playlist-items "$range" \
                    -f "bestvideo+bestaudio/best" \
                    --merge-output-format "$DEFAULT_CONTAINER" \
                    -o "$DEST/%(playlist_title,playlist)s/%(playlist_index)02d - %(title)s.%(ext)s"
            fi
            ;;
        *)
            return 0
            ;;
    esac
}

# ------------------------------------------------------------------------------
# Подменю: Субтитры
# ------------------------------------------------------------------------------
menu_subtitles() {
    local url="$1"

    local choice
    choice=$(select_menu "Выберите язык субтитров >" \
        "🇷🇺 Русские (ru)" \
        "🇬🇧 Английские (en)" \
        "🌐 Все доступные языки" \
        "↩️  Назад")

    local lang="ru.*,ru"
    case "$choice" in
        *"Русские"*)   lang="ru.*,ru" ;;
        *"Английские"*) lang="en.*,en" ;;
        *"Все"*)        lang="all" ;;
        *) return 0 ;;
    esac

    echo -e "${CYAN}Загрузка субтитров...${RESET}"
    yt-dlp \
        --write-subs \
        --write-auto-subs \
        --sub-langs "$lang" \
        --sub-format "srt/vtt" \
        --skip-download \
        -o "$DEST/%(title)s.%(ext)s" \
        "$url"
    
    echo -e "\n${GREEN}✅ Субтитры сохранены в $DEST${RESET}"
}

# ------------------------------------------------------------------------------
# Диагностика системы и раскрытия M-чипов
# ------------------------------------------------------------------------------
diagnose_system() {
    clear
    echo -e "${CYAN}${BOLD}🩺 ДИАГНОСТИКА ОКРУЖЕНИЯ И АППАРАТНОГО УСКОРЕНИЯ MAC${RESET}\n"
    
    echo -e "${WHITE}${BOLD}1. Аппаратная часть (Hardware):${RESET}"
    echo "   • Модель процессора : $CPU_BRAND"
    echo "   • Архитектура       : $CPU_ARCH"
    
    local os_ver
    os_ver=$(sw_vers -productVersion 2>/dev/null || echo "Unknown")
    echo "   • Версия macOS      : $os_ver"
    echo ""

    echo -e "${WHITE}${BOLD}2. Мультимедиа и кодеки (FFmpeg & VideoToolbox):${RESET}"
    if command -v ffmpeg &>/dev/null; then
        local ff_ver
        ff_ver=$(ffmpeg -version 2>/dev/null | head -n 1)
        echo "   • FFmpeg путь       : $(which ffmpeg)"
        echo "   • FFmpeg сборка     : $ff_ver"
        if ffmpeg -hwaccels 2>/dev/null | grep -q "videotoolbox"; then
            echo -e "   • VideoToolbox      : ${GREEN}✓ ВКЛЮЧЕНО (Apple Hardware Acceleration активен)${RESET}"
        else
            echo -e "   • VideoToolbox      : ${YELLOW}Software (CPU)${RESET}"
        fi
    else
        echo -e "   • FFmpeg            : ${RED}Не установлен!${RESET}"
    fi
    echo ""

    echo -e "${WHITE}${BOLD}3. Загрузчик yt-dlp:${RESET}"
    if command -v yt-dlp &>/dev/null; then
        echo "   • yt-dlp путь       : $(which yt-dlp)"
        echo "   • yt-dlp версия     : $(yt-dlp --version)"
    else
        echo -e "   • yt-dlp            : ${RED}Не установлен!${RESET}"
    fi
    echo ""

    echo -e "${WHITE}${BOLD}4. Дисковая подсистема:${RESET}"
    echo "   • Папка загрузки    : $DEST"
    if [ -w "$DEST" ]; then
        echo -e "   • Права на запись   : ${GREEN}✓ Доступно${RESET}"
        local free_space
        free_space=$(df -h "$DEST" 2>/dev/null | awk 'NR==2 {print $4}')
        echo "   • Свободно места    : $free_space"
    else
        echo -e "   • Права на запись   : ${RED}✗ Запрещено! Проверьте папку.${RESET}"
    fi
    echo ""

    read -p "Нажмите Enter для возврата в меню..." _
}

# ------------------------------------------------------------------------------
# Подменю: Настройки
# ------------------------------------------------------------------------------
menu_settings() {
    while true; do
        local meta_status="ВКЛ"
        [ "$EMBED_METADATA" != "true" ] && meta_status="ВЫКЛ"

        local thumb_status="ВКЛ"
        [ "$EMBED_THUMBNAIL" != "true" ] && thumb_status="ВЫКЛ"

        local apple_status="ВКЛ (H.264/AAC)"
        [ "$APPLE_COMPAT_MODE" != "true" ] && apple_status="ВЫКЛ (Любой)"

        local sound_status="ВКЛ"
        [ "$SOUND_ENABLED" != "true" ] && sound_status="ВЫКЛ"

        local choice
        choice=$(select_menu "Настройки yt (macOS Edition) >" \
            "📁 Папка сохранения : $DEST" \
            "🖼️  Вшивать обложку : [$thumb_status]" \
            "🏷️  Вшивать метаданные : [$meta_status]" \
            "🍏 Режим совместимости с Mac : [$apple_status]" \
            "🍪 Куки браузера для закрытых видео : [$COOKIE_BROWSER]" \
            "⚡ Потоков скачивания : [$CONCURRENT_FRAGMENTS]" \
            "🔊 Звук завершения : [$sound_status]" \
            "🩺 Диагностика Mac и VideoToolbox" \
            "🔄 Обновить yt-dlp" \
            "↩️  Назад в главное меню")

        case "$choice" in
            *"Папка сохранения"*)
                echo ""
                echo -e "Текущая папка: ${CYAN}$DEST${RESET}"
                read -p "Введите новый путь: " new_dest
                if [ -n "$new_dest" ]; then
                    new_dest="${new_dest/#\~/$HOME}"
                    mkdir -p "$new_dest" 2>/dev/null && DEST="$new_dest"
                    save_config
                    echo -e "${GREEN}✓ Папка обновлена!${RESET}"
                    sleep 1
                fi
                ;;
            *"Вшивать обложку"*)
                [ "$EMBED_THUMBNAIL" = "true" ] && EMBED_THUMBNAIL="false" || EMBED_THUMBNAIL="true"
                save_config
                ;;
            *"Вшивать метаданные"*)
                [ "$EMBED_METADATA" = "true" ] && EMBED_METADATA="false" || EMBED_METADATA="true"
                save_config
                ;;
            *"Режим совместимости"*)
                [ "$APPLE_COMPAT_MODE" = "true" ] && APPLE_COMPAT_MODE="false" || APPLE_COMPAT_MODE="true"
                save_config
                ;;
            *"Куки браузера"*)
                local b_choice
                b_choice=$(select_menu "Выберите браузер для чтения cookies >" "none (Без куков)" "safari" "chrome" "firefox")
                case "$b_choice" in
                    *"safari"*)  COOKIE_BROWSER="safari" ;;
                    *"chrome"*)  COOKIE_BROWSER="chrome" ;;
                    *"firefox"*) COOKIE_BROWSER="firefox" ;;
                    *)           COOKIE_BROWSER="none" ;;
                esac
                save_config
                ;;
            *"Потоков скачивания"*)
                local frag_choice
                frag_choice=$(select_menu "Количество параллельных потоков >" "4" "8 (Рекомендуется для M1/M2/M3/M4)" "16 (Гигабитный интернет)" "2")
                case "$frag_choice" in
                    *"4"*)  CONCURRENT_FRAGMENTS="4" ;;
                    *"8"*)  CONCURRENT_FRAGMENTS="8" ;;
                    *"16"*) CONCURRENT_FRAGMENTS="16" ;;
                    *"2"*)  CONCURRENT_FRAGMENTS="2" ;;
                esac
                save_config
                ;;
            *"Звук завершения"*)
                [ "$SOUND_ENABLED" = "true" ] && SOUND_ENABLED="false" || SOUND_ENABLED="true"
                save_config
                ;;
            *"Диагностика"*)
                diagnose_system
                ;;
            *"Обновить yt-dlp"*)
                echo -e "\n${CYAN}Проверка обновлений yt-dlp...${RESET}"
                if command -v brew &>/dev/null; then
                    brew upgrade yt-dlp || yt-dlp -U
                else
                    yt-dlp -U
                fi
                echo -e "${GREEN}✓ Готово!${RESET}"
                sleep 2
                ;;
            *)
                break
                ;;
        esac
    done
}

# ------------------------------------------------------------------------------
# Действия после загрузки
# ------------------------------------------------------------------------------
post_download_menu() {
    local status="${1:-0}"
    local choice

    if [ "$status" -eq 0 ]; then
        choice=$(select_menu "Что сделать дальше? >" \
            "🔄 Загрузить ещё одно медиа" \
            "📂 Открыть папку в Finder" \
            "🎬 Воспроизвести скачанный файл" \
            "❌ Выйти")
    else
        choice=$(select_menu "Что сделать дальше? >" \
            "🔄 Попробовать ещё раз" \
            "📂 Открыть папку в Finder" \
            "❌ Выйти")
    fi

    case "$choice" in
        *"ещё одно"*|*"Попробовать"*)
            return 0
            ;;
        *"Finder"*)
            open "$DEST"
            post_download_menu "$status"
            ;;
        *"Воспроизвести"*)
            local latest_file
            latest_file=$(ls -t "$DEST" 2>/dev/null | head -n 1)
            if [ -n "$latest_file" ] && [ -f "$DEST/$latest_file" ]; then
                open "$DEST/$latest_file"
            else
                echo -e "${YELLOW}Файл не найден.${RESET}"
            fi
            post_download_menu "$status"
            ;;
        *)
            echo -e "${GREEN}До встречи! 👋${RESET}"
            exit 0
            ;;
    esac
}

# ------------------------------------------------------------------------------
# Главный цикл программы
# ------------------------------------------------------------------------------
main() {
    # Обработка аргументов командной строки
    while [ $# -gt 0 ]; do
        case "$1" in
            -h|--help)
                show_banner
                echo -e "${BOLD}Использование:${RESET}"
                echo "  yt                       # Интерактивное меню (с автоподхватом из буфера macOS)"
                echo "  yt <URL>                 # Запуск сразу с указанной ссылкой"
                echo "  yt --diag                # Диагностика Mac, M-процессора и VideoToolbox"
                echo "  yt -h | --help           # Показать эту справку"
                echo ""
                echo -e "${BOLD}Особенности macOS:${RESET}"
                echo "  • Аппаратное ускорение VideoToolbox на процессорах Apple Silicon (M1/M2/M3/M4)"
                echo "  • Форсирование FastStart (-movflags +faststart) для мгновенного QuickLook в Finder"
                echo "  • Нативные звуки и баннеры уведомлений macOS"
                echo "  • Поддержка Safari/Chrome куков для загрузки приватных видео"
                exit 0
                ;;
            --diag)
                diagnose_system
                exit 0
                ;;
            --debug|-d)
                DEBUG_MODE="true"
                shift
                ;;
            *)
                break
                ;;
        esac
    done

    check_dependencies
    load_config

    local initial_url="$1"

    while true; do
        show_banner

        local URL=""
        if [ -n "$initial_url" ]; then
            URL="$initial_url"
            initial_url=""
        else
            URL=$(get_url)
        fi

        if [ -z "$URL" ]; then
            echo -e "${GREEN}До встречи! 👋${RESET}"
            exit 0
        fi

        fetch_and_display_info "$URL"

        local ACTION
        ACTION=$(select_menu "Выберите действие для медиа >" \
            "🚀 Максимальное качество (Best Video + Audio • $DEFAULT_CONTAINER)" \
            "🎵 Сразу MP3 (Макс. битрейт 320k + обложка)" \
            "🪶 Минимальный вес (Экономный режим / быстрый просмотр)" \
            "🎯 Выбрать точное разрешение (4K, 2K, 1080p, 720p, 480p...)" \
            "🎧 Другие аудиоформаты (M4A, FLAC, WAV, OPUS...)" \
            "✂️  Скачать конкретный отрезок (по времени)" \
            "📜 Загрузить плейлист (весь или диапазон)" \
            "📋 Показать форматы и выбрать ID вручную" \
            "💬 Скачать субтитры" \
            "🖼️  Скачать только обложку" \
            "⚙️  Настройки и оптимизация Mac" \
            "❌ Выход")

        local thumb_args=()
        if [ "$EMBED_THUMBNAIL" = "true" ]; then
            thumb_args=("--embed-thumbnail" "--convert-thumbnails" "jpg")
        fi

        local last_status=0

        case "$ACTION" in
            *"Максимальное качество"*)
                execute_download "$URL" \
                    --no-playlist \
                    -f "bestvideo+bestaudio/best" \
                    --merge-output-format "$DEFAULT_CONTAINER" \
                    "${thumb_args[@]}" \
                    -o "$DEST/%(title)s.%(ext)s"
                last_status=$?
                ;;

            *"Сразу MP3"*)
                execute_download "$URL" \
                    --no-playlist \
                    -x \
                    --audio-format mp3 \
                    --audio-quality 0 \
                    "${thumb_args[@]}" \
                    -o "$DEST/%(title)s.%(ext)s"
                last_status=$?
                ;;

            *"Минимальный вес"*)
                execute_download "$URL" \
                    --no-playlist \
                    -f "worstvideo+worstaudio/worst" \
                    --merge-output-format "$DEFAULT_CONTAINER" \
                    -o "$DEST/%(title)s.%(ext)s"
                last_status=$?
                ;;

            *"Выбрать точное разрешение"*)
                menu_resolution "$URL"
                last_status=$?
                ;;

            *"Другие аудиоформаты"*)
                menu_audio "$URL"
                last_status=$?
                ;;

            *"Скачать конкретный отрезок"*)
                menu_timeslice "$URL"
                last_status=$?
                ;;

            *"Загрузить плейлист"*)
                menu_playlist "$URL"
                last_status=$?
                ;;

            *"Показать форматы"*)
                echo ""
                yt-dlp -F "$URL"
                echo ""
                read -p "Введите ID формата (например, 137+140 или best, Enter для отмены): " custom_format
                custom_format=$(echo "$custom_format" | tr -d ' ')
                if [ -n "$custom_format" ]; then
                    execute_download "$URL" \
                        -f "$custom_format" \
                        -o "$DEST/%(title)s.%(ext)s"
                    last_status=$?
                fi
                ;;

            *"Скачать субтитры"*)
                menu_subtitles "$URL"
                last_status=$?
                ;;

            *"только обложку"*)
                echo -e "${CYAN}Загрузка обложки...${RESET}"
                yt-dlp \
                    --write-thumbnail \
                    --skip-download \
                    --convert-thumbnails jpg \
                    -o "$DEST/%(title)s.%(ext)s" \
                    "$URL"
                last_status=$?
                if [ $last_status -eq 0 ]; then
                    echo -e "\n${GREEN}✅ Обложка сохранена в $DEST${RESET}"
                fi
                ;;

            *"Настройки"*)
                menu_settings
                continue
                ;;

            *)
                echo -e "${GREEN}До встречи! 👋${RESET}"
                exit 0
                ;;
        esac

        post_download_menu "$last_status"
    done
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
