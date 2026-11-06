#!/usr/bin/env bash
# ==============================================================================
#  ⚡ Установщик yt (macOS Edition)
#  Оптимизировано для macOS (Apple Silicon M1/M2/M3/M4 & Intel)
# ==============================================================================

set -e

# Определение директории скрипта
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BIN_DIR="$SCRIPT_DIR/bin"
mkdir -p "$BIN_DIR"

# Цвета
GREEN='\033[0;32m'
CYAN='\033[0;36m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
BOLD='\033[1m'
GRAY='\033[38;5;244m'
RESET='\033[0m'

clear
echo -e "${CYAN}${BOLD}"
cat << "EOF"
   ╭─────────────────────────────────────────────────────────────╮
   │         ⚡  y t   ( m a c O S   E d i t i o n )  ⚡             │
   │      Оптимизация для macOS & процессоров Apple Silicon      │
   ╰─────────────────────────────────────────────────────────────╯
EOF
echo -e "${RESET}"

echo -e "${YELLOW}🔍 Шаг 1: Проверка аппаратной платформы...${RESET}"
OS="$(uname -s)"
ARCH="$(uname -m)"
CPU_MODEL="$(sysctl -n machdep.cpu.brand_string 2>/dev/null || echo "$ARCH")"

echo -e "   • Платформа: ${GREEN}$OS ($ARCH)${RESET}"
echo -e "   • Процессор: ${CYAN}$CPU_MODEL${RESET}\n"

# ------------------------------------------------------------------------------
# 1. Установка утилит через Homebrew или напрямую
# ------------------------------------------------------------------------------
echo -e "${YELLOW}📦 Шаг 2: Установка зависимостей (yt-dlp, ffmpeg, fzf)...${RESET}"

if [ "$OS" = "Darwin" ]; then
    # Подключение путей brew (Apple Silicon /opt/homebrew или Intel /usr/local)
    if [ -f "/opt/homebrew/bin/brew" ]; then
        eval "$(/opt/homebrew/bin/brew shellenv)"
    elif [ -f "/usr/local/bin/brew" ]; then
        eval "$(/usr/local/bin/brew shellenv)"
    fi

    # Проверка Homebrew
    if ! command -v brew &>/dev/null; then
        echo -e "${YELLOW}Homebrew не обнаружен на вашем Mac.${RESET}"
        echo -e "Выберите способ установки:"
        echo -e "  ${CYAN}1)${RESET} Установить Homebrew и все пакеты автоматически (Рекомендуется)"
        echo -e "  ${CYAN}2)${RESET} Скачать автономный yt-dlp напрямую (Быстро, без Homebrew)"
        read -p "Выберите вариант [1/2, по умолчанию 1]: " brew_choice
        brew_choice=${brew_choice:-1}

        if [ "$brew_choice" = "1" ]; then
            echo -e "\n${CYAN}Установка Homebrew...${RESET}"
            /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
            
            if [ -f "/opt/homebrew/bin/brew" ]; then
                eval "$(/opt/homebrew/bin/brew shellenv)"
            elif [ -f "/usr/local/bin/brew" ]; then
                eval "$(/usr/local/bin/brew shellenv)"
            fi
            
            echo -e "${CYAN}Установка yt-dlp, ffmpeg и fzf через Homebrew...${RESET}"
            brew install yt-dlp ffmpeg fzf || true
        else
            echo -e "\n${CYAN}Скачивание автономного yt-dlp для macOS...${RESET}"
            curl -L "https://github.com/yt-dlp/yt-dlp/releases/latest/download/yt-dlp_macos" -o "$BIN_DIR/yt-dlp"
            chmod +x "$BIN_DIR/yt-dlp"
            echo -e "${GREEN}✓ yt-dlp установлен в $BIN_DIR/yt-dlp${RESET}"

            if ! command -v ffmpeg &>/dev/null; then
                echo -e "${YELLOW}Для объединения 4K видео и конвертации в MP3 устанавливаем Homebrew и ffmpeg...${RESET}"
                /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
                if [ -f "/opt/homebrew/bin/brew" ]; then
                    eval "$(/opt/homebrew/bin/brew shellenv)"
                elif [ -f "/usr/local/bin/brew" ]; then
                    eval "$(/usr/local/bin/brew shellenv)"
                fi
                brew install ffmpeg fzf || true
            fi
        fi
    else
        echo -e "${GREEN}✓ Homebrew обнаружен${RESET}"
        echo -e "${CYAN}Установка / обновление yt-dlp, ffmpeg и fzf...${RESET}"
        brew install yt-dlp ffmpeg fzf || true
    fi

elif [ "$OS" = "Linux" ]; then
    if command -v apt-get &>/dev/null; then
        echo -e "${CYAN}Установка пакетов через apt-get...${RESET}"
        sudo apt-get update
        sudo apt-get install -y ffmpeg fzf curl python3
        sudo curl -L https://github.com/yt-dlp/yt-dlp/releases/latest/download/yt-dlp -o /usr/local/bin/yt-dlp
        sudo chmod a+rx /usr/local/bin/yt-dlp
    elif command -v pacman &>/dev/null; then
        sudo pacman -Sy --noconfirm yt-dlp ffmpeg fzf
    elif command -v dnf &>/dev/null; then
        sudo dnf install -y yt-dlp ffmpeg fzf
    fi
fi

# ------------------------------------------------------------------------------
# 2. Проверка VideoToolbox аппаратного ускорения
# ------------------------------------------------------------------------------
echo -e "\n${YELLOW}⚡ Шаг 3: Проверка аппаратного ускорения Apple Silicon...${RESET}"
if command -v ffmpeg &>/dev/null; then
    if ffmpeg -hwaccels 2>/dev/null | grep -q "videotoolbox"; then
        echo -e "${GREEN}✓ VideoToolbox аппаратное ускорение АКТИВИРОВАНО!${RESET}"
        echo -e "   ${GRAY}Медиа-ядро вашего $CPU_MODEL будет аппаратно обрабатывать видео.${RESET}"
    else
        echo -e "${YELLOW}⚠️ VideoToolbox не активен, будет использоваться стандартный CPU.${RESET}"
    fi
fi

# ------------------------------------------------------------------------------
# 3. Настройка прав запуска
# ------------------------------------------------------------------------------
echo -e "\n${YELLOW}⚙️ Шаг 4: Настройка прав запуска...${RESET}"
chmod +x "$SCRIPT_DIR/yt.sh" "$SCRIPT_DIR/start.sh" 2>/dev/null || true
echo -e "${GREEN}✓ Права на исполнение выданы!${RESET}"

# ------------------------------------------------------------------------------
# 4. Настройка глобальной команды 'yt'
# ------------------------------------------------------------------------------
echo -e "\n${YELLOW}🔗 Шаг 5: Настройка быстрого запуска команды 'yt'${RESET}"

if [ -d "/opt/homebrew/bin" ] && [ -w "/opt/homebrew/bin" ]; then
    ln -sf "$SCRIPT_DIR/yt.sh" /opt/homebrew/bin/yt 2>/dev/null && \
    echo -e "${GREEN}✓ Создана системная ссылка: /opt/homebrew/bin/yt${RESET}"
elif [ -d "/usr/local/bin" ] && [ -w "/usr/local/bin" ]; then
    ln -sf "$SCRIPT_DIR/yt.sh" /usr/local/bin/yt 2>/dev/null && \
    echo -e "${GREEN}✓ Создана системная ссылка: /usr/local/bin/yt${RESET}"
fi

SHELL_RC=""
if [ -f "$HOME/.zshrc" ] || [ "$SHELL" = "/bin/zsh" ]; then
    SHELL_RC="$HOME/.zshrc"
    [ ! -f "$SHELL_RC" ] && touch "$SHELL_RC"
elif [ -f "$HOME/.bashrc" ] || [ "$SHELL" = "/bin/bash" ]; then
    SHELL_RC="$HOME/.bashrc"
fi

if [ -n "$SHELL_RC" ]; then
    if ! grep -q "alias yt=" "$SHELL_RC" 2>/dev/null; then
        echo "" >> "$SHELL_RC"
        echo "# YT-DLP Ultimate Downloader" >> "$SHELL_RC"
        echo "alias yt=\"$SCRIPT_DIR/yt.sh\"" >> "$SHELL_RC"
        echo -e "${GREEN}✓ Добавлен алиас 'yt' в $SHELL_RC${RESET}"
    else
        echo -e "${GREEN}✓ Алиас 'yt' уже присутствует в $SHELL_RC${RESET}"
    fi
fi

echo -e "\n${GREEN}${BOLD}🎉 УСТАНОВКА И ОПТИМИЗАЦИЯ ЗАВЕРШЕНЫ!${RESET}"
echo -e "─────────────────────────────────────────────────────────────"
echo -e "${BOLD}Как запускать программу:${RESET}"
echo -e "  1. Из любой папки терминала :  ${CYAN}yt${RESET}"
echo -e "  2. Или из папки проекта    :  ${CYAN}bash start.sh${RESET}"
echo -e "─────────────────────────────────────────────────────────────\n"
