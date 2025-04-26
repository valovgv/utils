#!/bin/bash

# Выходим при первой ошибке
set -e

# Цвета для вывода
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# Директория для хранения профилей
PROFILES_DIR="$HOME/.fpv_profiles"

# Создаем директорию для профилей, если ее нет
mkdir -p "$PROFILES_DIR"

# Функция для вывода заголовка
print_header() {
    echo -e "${BLUE}==> ${1}${NC}"
}

# Функция для вывода успешного статуса
print_success() {
    echo -e "${GREEN}[✓] ${1}${NC}"
}

# Функция для вывода предупреждения
print_warning() {
    echo -e "${YELLOW}[!] ${1}${NC}"
}

# Функция для вывода ошибки
print_error() {
    echo -e "${RED}[✗] ${1}${NC}" >&2
}

print_info() { 
    echo -e "${CYAN}➜ ${1}${NC}"
}

# Функция для выбора профиля
select_profile() {
    local profiles=()
    while IFS= read -r -d $'\0' file; do
        profiles+=("$file")
    done < <(find "$PROFILES_DIR" -maxdepth 1 -type f -name "*.profile" -print0)
    
    if [ ${#profiles[@]} -eq 0 ]; then
        print_warning "Нет сохраненных профилей"
        return 1
    fi
    
    echo -e "${GREEN}Доступные профили:${NC}"
    for i in "${!profiles[@]}"; do
        echo "  $((i+1)). $(basename "${profiles[$i]}" .profile)"
    done
    
    read -p "Выберите профиль (1-${#profiles[@]}): " choice
    if [[ "$choice" =~ ^[0-9]+$ ]] && [ "$choice" -ge 1 ] && [ "$choice" -le ${#profiles[@]} ]; then
        local selected="${profiles[$((choice-1))]}"
        print_success "Выбран профиль: $(basename "$selected" .profile)"
        # Загружаем профиль
        source "$selected"
        # Проверяем, что переменная установлена
        if [ -z "$R_FPV_SOURCE" ]; then
            print_error "Профиль поврежден: R_FPV_SOURCE не установлен"
            return 1
        fi
        return 0
    else
        print_error "Неверный выбор"
        return 1
    fi
}

# Функция для создания нового профиля
create_profile() {
    while true; do
        read -p "Введите имя профиля: " profile_name
        profile_name=$(echo "$profile_name" | tr ' ' '_' | tr -cd '[:alnum:]._-')
        
        if [ -z "$profile_name" ]; then
            print_error "Имя профиля не может быть пустым"
            continue
        fi
        
        local profile_file="$PROFILES_DIR/$profile_name.profile"
        break
    done
    
    if [ -f "$profile_file" ]; then
        read -p "Профиль уже существует. Перезаписать? (y/n): " overwrite
        if [[ ! "$overwrite" =~ ^[YyДд]$ ]]; then
            return 1
        fi
    fi
    
    while true; do
        read -p "Введите имя пользователя: " username
        if [ -z "$username" ]; then
            print_error "Имя пользователя не может быть пустым"
            continue
        fi
        break
    done
    
    while true; do
        read -p "Введите IP адрес или хост: " host
        if [ -z "$host" ]; then
            print_error "Хост не может быть пустым"
            continue
        fi
        break
    done
    
    while true; do
        read -p "Введите путь к директории на удаленном хосте: " remote_path
        if [ -z "$remote_path" ]; then
            print_error "Путь не может быть пустым"
            continue
        fi
        break
    done
    
    # Формируем строку подключения
    R_FPV_SOURCE="${username}@${host}:${remote_path}"
    
    # Сохраняем в файл профиля
    echo "export R_FPV_SOURCE=\"$R_FPV_SOURCE\"" > "$profile_file"
    print_success "Профиль '$profile_name' сохранен"
    return 0
}

# Функция для настройки подключения
setup_connection() {
    # Пытаемся выбрать существующий профиль
    if select_profile; then
        echo -e "${GREEN}Используются настройки подключения:${NC}"
        echo -e "  ${CYAN}Источник: $R_FPV_SOURCE${NC}"
        return 0
    fi
    
    # Если профиль не выбран, предлагаем создать новый
    print_warning "Необходимо настроить подключение к источнику"
    while true; do
        echo -e "${YELLOW}Выберите действие:${NC}"
        echo "  1. Создать новый профиль"
        echo "  2. Ввести настройки без сохранения"
        echo "  3. Выход"
        
        read -p "Ваш выбор (1-3): " choice
        case $choice in
            1)
                if create_profile; then
                    source "$PROFILES_DIR/$(ls -t "$PROFILES_DIR" | head -n1)"
                    break
                fi
                ;;
            2)
                while true; do
                    read -p "Введите имя пользователя: " username
                    read -p "Введите IP адрес или хост: " host
                    read -p "Введите путь к директории на удаленном хосте: " remote_path
                    
                    if [ -z "$username" ] || [ -z "$host" ] || [ -z "$remote_path" ]; then
                        print_error "Все поля должны быть заполнены"
                        continue
                    fi
                    
                    export R_FPV_SOURCE="${username}@${host}:${remote_path}"
                    break
                done
                break
                ;;
            3)
                exit 0
                ;;
            *)
                print_error "Неверный выбор"
                ;;
        esac
    done
    
    echo -e "${GREEN}Настройки подключения установлены:${NC}"
    echo -e "  ${CYAN}Источник: $R_FPV_SOURCE${NC}"
    return 0
}


# Функция для проверки и остановки ruby_controller
check_and_stop_ruby_controller() {
    if pgrep -x "ruby_controller" >/dev/null; then
        print_warning "Обнаружен запущенный ruby_controller"
        local stop_script="/home/radxa/ruby/stop_all.sh"
        
        if [ -f "$stop_script" ]; then
            print_info "Запускаем скрипт остановки: $stop_script"
            if ! bash "$stop_script"; then
                print_error "Ошибка при выполнении скрипта остановки!"
                exit 1
            fi
            print_success "ruby_controller успешно остановлен"
        else
            print_error "Скрипт остановки $stop_script не найден!"
            exit 1
        fi
        
        # Дополнительная проверка, что процесс действительно остановился
        sleep 2
        if pgrep -x "ruby_controller" >/dev/null; then
            print_error "Не удалось остановить ruby_controller!"
            exit 1
        fi
    else
        print_success "ruby_controller не запущен, можно продолжать"
    fi
}

# Функция для копирования исполняемых файлов
copy_executables() {
    print_header "КОПИРОВАНИЕ ИСПОЛНЯЕМЫХ ФАЙЛОВ"
    local target_dir="/home/radxa/ruby"
    
    # Проверяем существование целевой директории
    if [ ! -d "$target_dir" ]; then
        print_warning "Целевая директория не существует"
        echo -e "${YELLOW}Создаем: $target_dir${NC}"
        mkdir -p "$target_dir"
        print_success "Директория создана"
    fi
    
    # Ищем все исполняемые файлы ruby_* в текущей директории
    local executables=($(find . -maxdepth 1 -type f -name 'ruby_*' -executable))
    
    if [ ${#executables[@]} -eq 0 ]; then
        print_warning "Исполняемые файлы ruby_* не найдены в текущей директории"
        return
    fi
    
    echo -e "${CYAN}Найдены следующие исполняемые файлы:${NC}"
    printf '  %s\n' "${executables[@]}"
    
    read -p -n 1 "Копировать эти файлы в $target_dir? (y/n): " choice
    if [[ $choice =~ ^[YyДд]$ ]]; then
        echo -e "${YELLOW}Копируем файлы...${NC}"
        if ! cp -v "${executables[@]}" "$target_dir"; then
            print_error "Ошибка при копировании файлов!"
            exit 1
        fi
        print_success "Файлы успешно скопированы в $target_dir"
        
        # Проверяем права на выполнение в целевой директории
        for file in "${executables[@]}"; do
            local target_file="$target_dir/$(basename "$file")"
            if [ ! -x "$target_file" ]; then
                print_warning "Файл $target_file не исполняемый"
                chmod +x "$target_file"
                print_success "Права на выполнение добавлены для $target_file"
            fi
        done
    else
        print_info "Копирование отменено пользователем"
    fi
}

# Настраиваем подключение
print_header "НАСТРОЙКА ПОДКЛЮЧЕНИЯ"
if ! setup_connection; then
    print_error "Не удалось настроить подключение"
    exit 1
fi

# Проверяем, что R_FPV_SOURCE установлен
if [ -z "$R_FPV_SOURCE" ]; then
    print_error "Не указан источник для копирования (R_FPV_SOURCE)"
    exit 1
fi

# Проверяем и останавливаем ruby_controller если нужно
print_header "ПРОВЕРКА ЗАПУЩЕННЫХ ПРОЦЕССОВ"
check_and_stop_ruby_controller

TARGET_DIR="/home/radxa/r_fpv_link"

print_header "1. ПОДГОТОВКА ЦЕЛЕВОЙ ДИРЕКТОРИИ"
if [ ! -d "$TARGET_DIR" ]; then
    print_warning "Целевая директория не существует"
    echo -e "${YELLOW}Создаем: $TARGET_DIR${NC}"
    mkdir -p "$TARGET_DIR"
    print_success "Директория создана"
else
    print_success "Целевая директория существует"
fi

print_header "2. КОПИРОВАНИЕ ФАЙЛОВ (RSYNC)"
echo -e "${BLUE}Источник: $R_FPV_SOURCE${NC}"
echo -e "${BLUE}Назначение: /home/radxa${NC}"

if ! rsync -avz "$R_FPV_SOURCE" /home/radxa; then
    print_error "Ошибка при выполнении rsync!"
    exit 1
fi
print_success "Файлы успешно скопированы"

print_header "3. ПЕРЕХОД В РАБОЧУЮ ДИРЕКТОРИЮ"
echo -e "${BLUE}Директория: $TARGET_DIR${NC}"

cd "$TARGET_DIR" || {
    print_error "Не удалось перейти в директорию $TARGET_DIR!"
    exit 1
}
print_success "Успешный переход в директорию"

print_header "4. ПРОВЕРКА СКРИПТА make_radxa.sh"
if [ ! -f "make_radxa.sh" ]; then
    print_error "Файл make_radxa.sh не найден!"
    exit 1
fi
print_success "Файл make_radxa.sh найден"

if [ ! -x "make_radxa.sh" ]; then
    print_warning "Скрипт не исполняемый"
    echo -e "${YELLOW}Добавляем права на выполнение...${NC}"
    chmod +x "make_radxa.sh"
    print_success "Права на выполнение добавлены"
else
    print_success "Скрипт исполняемый"
fi

print_header "5. СБОРКА"
echo -e "${BLUE}Запускаем ./make_radxa.sh...${NC}"

if ! ./make_radxa.sh; then
    print_error "Ошибка при выполнении make_radxa.sh!"
    exit 1
fi
print_success "Сборка выполнена успешно"

print_header "6. ПРОВЕРКА И ЗАПУСК"
BUILD_DIR=.
print_info "Проверяем наличие ruby_controller в $BUILD_DIR"

if [ -f "$BUILD_DIR/ruby_controller" ]; then
    print_success "Файл ruby_controller найден"

    if [ -x "$BUILD_DIR/ruby_controller" ]; then
        print_header "6. ЗАПУСК RUBY_CONTROLLER"
        print_info "Запускаем: $BUILD_DIR/ruby_controller"
        if ! ./ruby_controller; then
            print_error "Ошибка при выполнении ruby_controller!"
            exit 1
        fi
        print_success "ruby_controller завершил работу"
        
        # Предлагаем скопировать исполняемые файлы
        copy_executables
    else
        print_warning "Файл ruby_controller не исполняемый"
        chmod +x "$BUILD_DIR/ruby_controller" && print_success "Права на выполнение добавлены"
    fi
else
    print_warning "Файл ruby_controller не найден в директории сборки"
fi

echo -e "\n${GREEN}========================================${NC}"
echo -e "${GREEN}       ВСЕ ОПЕРАЦИИ УСПЕШНО ЗАВЕРШЕНЫ      ${NC}"
echo -e "${GREEN}========================================${NC}"
