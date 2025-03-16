# Установка кодировки UTF-8 для вывода
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8

# Функция для установки контейнеров
function Install-Containers {
    Write-Host "Запуск установки контейнеров..." -ForegroundColor Green

    # Прогресс-бар: Начало
    $totalSteps = 9
    $currentStep = 0

    try {
        # Проверка прав администратора
        $currentStep++
        Write-Progress -Activity "Установка контейнеров" -Status "Шаг ${currentStep} из ${totalSteps}: Проверка прав администратора" -PercentComplete (($currentStep / $totalSteps) * 100)
        $isAdmin = ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole] "Administrator")
        if (-not $isAdmin) {
            Write-Host "Ошибка: Требуются права администратора." -ForegroundColor Red
            Write-Host "Решение: Запустите PowerShell от имени администратора и повторите попытку." -ForegroundColor Yellow
            return
        }

        # Проверка наличия Docker
        $currentStep++
        Write-Progress -Activity "Установка контейнеров" -Status "Шаг ${currentStep} из ${totalSteps}: Проверка Docker" -PercentComplete (($currentStep / $totalSteps) * 100)
        if (-not (Get-Command docker -ErrorAction SilentlyContinue)) {
            Write-Host "Docker не установлен. Установка Docker Desktop..." -ForegroundColor Cyan

            # Скачивание Docker Desktop
            $dockerUrl = "https://desktop.docker.com/win/stable/Docker%20Desktop%20Installer.exe"
            $installerPath = "$env:TEMP\DockerDesktopInstaller.exe"
            $attempts = 3
            $success = $false
            for ($i = 1; $i -le $attempts; $i++) {
                Write-Host "Попытка ${i}: Скачивание Docker Desktop..." -ForegroundColor Cyan
                Invoke-WebRequest -Uri $dockerUrl -OutFile $installerPath -ErrorAction Stop
                $success = $true
                break
            }
            if (-not $success) {
                Write-Host "Не удалось скачать Docker после $attempts попыток." -ForegroundColor Red
                return
            }
            Write-Host "Установщик скачан: $installerPath" -ForegroundColor Green

            # Установка Docker Desktop
            Write-Host "Установка Docker Desktop..." -ForegroundColor Cyan
            Start-Process -FilePath $installerPath -ArgumentList "/install", "/quiet", "/norestart" -Wait -NoNewWindow

            # Ожидание установки
            $timeout = 300
            $elapsed = 0
            while (-not (Get-Command docker -ErrorAction SilentlyContinue) -and $elapsed -lt $timeout) {
                Start-Sleep -Seconds 5
                $elapsed += 5
            }
            if ($elapsed -ge $timeout) {
                Write-Host "Ошибка: Docker не установлен в течение $timeout секунд." -ForegroundColor Red
                return
            }
            Write-Host "Docker Desktop успешно установлен!" -ForegroundColor Green
        }

        # Проверка docker-compose
        $currentStep++
        Write-Progress -Activity "Установка контейнеров" -Status "Шаг ${currentStep} из ${totalSteps}: Проверка docker-compose" -PercentComplete (($currentStep / $totalSteps) * 100)
        if (-not (Get-Command docker-compose -ErrorAction SilentlyContinue)) {
            Write-Host "Ошибка: docker-compose не найден." -ForegroundColor Red
            Write-Host "Решение: Перезапустите терминал или переустановите Docker Desktop." -ForegroundColor Yellow
            return
        }

        # Создание рабочей директории на C:\SupersetPostgres
        $currentStep++
        Write-Progress -Activity "Установка контейнеров" -Status "Шаг ${currentStep} из ${totalSteps}: Создание рабочей директории" -PercentComplete (($currentStep / $totalSteps) * 100)
        $projectDir = "C:\SupersetPostgres"
        if (-not (Test-Path $projectDir)) {
            New-Item -ItemType Directory -Path $projectDir -ErrorAction Stop
            Write-Host "Создана директория: $projectDir" -ForegroundColor Green
        }
        Set-Location $projectDir

        # Удаление существующих контейнеров
        $currentStep++
        Write-Progress -Activity "Установка контейнеров" -Status "Шаг ${currentStep} из ${totalSteps}: Удаление старых контейнеров" -PercentComplete (($currentStep / $totalSteps) * 100)
        $existingContainers = docker ps -a --filter "name=superset-postgres" --format "{{.Names}}"
        if ($existingContainers) {
            Write-Host "Удаление существующих контейнеров..." -ForegroundColor Cyan
            docker-compose down -v 2>&1 | Out-Null
        }

        # Генерация SECRET_KEY
        $currentStep++
        Write-Progress -Activity "Установка контейнеров" -Status "Шаг ${currentStep} из ${totalSteps}: Генерация SECRET_KEY" -PercentComplete (($currentStep / $totalSteps) * 100)
        $rng = New-Object System.Security.Cryptography.RNGCryptoServiceProvider
        $bytes = New-Object byte[] 32
        $rng.GetBytes($bytes)
        $secretKey = [Convert]::ToBase64String($bytes)

        # Создание superset_config.py
        $currentStep++
        Write-Progress -Activity "Установка контейнеров" -Status "Шаг ${currentStep} из ${totalSteps}: Создание superset_config.py" -PercentComplete (($currentStep / $totalSteps) * 100)
        $configFile = @"
SECRET_KEY = '$secretKey'
"@
        Set-Content -Path "superset_config.py" -Value $configFile -Encoding UTF8 -Force -ErrorAction Stop
        Write-Host "Файл superset_config.py создан с SECRET_KEY: $secretKey" -ForegroundColor Green

        # Создание docker-compose.yml с монтированием superset_config.py
        $currentStep++
        Write-Progress -Activity "Установка контейнеров" -Status "Шаг ${currentStep} из ${totalSteps}: Создание docker-compose.yml" -PercentComplete (($currentStep / $totalSteps) * 100)
        $composeFile = @"
version: '3.8'
services:
  postgres:
    image: postgres:13
    environment:
      POSTGRES_USER: superset
      POSTGRES_PASSWORD: superset
      POSTGRES_DB: superset
    volumes:
      - pgdata:/var/lib/postgresql/data
    networks:
      - superset-net
  superset:
    image: apache/superset
    depends_on:
      - postgres
    environment:
      SUPERSET_ENV: production
      SUPERSET_DB_URI: postgresql://superset:superset@postgres:5432/superset
    ports:
      - "8088:8088"
    volumes:
      - ./superset_config.py:/app/superset_config.py
    networks:
      - superset-net
volumes:
  pgdata:
networks:
  superset-net:
"@
        Set-Content -Path "docker-compose.yml" -Value $composeFile -Encoding UTF8 -Force -ErrorAction Stop
        Write-Host "Файл docker-compose.yml создан" -ForegroundColor Green

        # Запуск контейнеров
        $currentStep++
        Write-Progress -Activity "Установка контейнеров" -Status "Шаг ${currentStep} из ${totalSteps}: Запуск контейнеров" -PercentComplete (($currentStep / $totalSteps) * 100)
        Write-Host "Запуск контейнеров..." -ForegroundColor Cyan
        docker-compose up -d 2>&1 | Out-Null

        # Ожидание и настройка
        Start-Sleep -Seconds 30
        $containerName = (docker ps --filter "name=superset-postgres-superset" --format "{{.Names}}")
        if ($containerName) {
            Write-Host "Контейнер Superset запущен: $containerName" -ForegroundColor Green
            Write-Host "Настройка Superset..." -ForegroundColor Cyan
            docker exec -it $containerName bash -c "superset db upgrade" 2>&1 | Out-Null
            docker exec -it $containerName bash -c "superset init" 2>&1 | Out-Null
            docker exec -it $containerName bash -c "superset fab create-admin --username admin --firstname Admin --lastname User --email admin@example.com --password admin" 2>&1 | Out-Null
            Write-Host "Superset настроен! Доступ: http://localhost:8088 (admin/admin)" -ForegroundColor Green
        } else {
            Write-Host "Ошибка: Контейнер Superset не запущен." -ForegroundColor Red
            Write-Host "Проверьте логи: docker-compose logs" -ForegroundColor Yellow
        }
    } catch {
        Write-Host "Ошибка: $_" -ForegroundColor Red
    }
    Write-Progress -Activity "Установка контейнеров" -Completed
}

# Функция для создания архива
function Create-Archive {
    Write-Host "Создание архива..." -ForegroundColor Green

    # Прогресс-бар: Начало
    $totalSteps = 3
    $currentStep = 0

    try {
        $currentStep++
        Write-Progress -Activity "Создание архива" -Status "Шаг ${currentStep} из ${totalSteps}: Проверка тома" -PercentComplete (($currentStep / $totalSteps) * 100)
        $volume = docker volume ls -q --filter name=pgdata
        if (-not $volume) {
            Write-Host "Ошибка: Том pgdata не найден." -ForegroundColor Red
            return
        }

        $currentStep++
        Write-Progress -Activity "Создание архива" -Status "Шаг ${currentStep} из ${totalSteps}: Создание архива" -PercentComplete (($currentStep / $totalSteps) * 100)
        $archivePath = "C:\SupersetPostgres\pgdata_backup.tar.gz"
        docker run --rm -v pgdata:/data -v "C:\SupersetPostgres:/backup" ubuntu tar czf /backup/pgdata_backup.tar.gz /data 2>&1 | Out-Null

        $currentStep++
        Write-Progress -Activity "Создание архива" -Status "Шаг ${currentStep} из ${totalSteps}: Проверка результата" -PercentComplete (($currentStep / $totalSteps) * 100)
        if (Test-Path $archivePath) {
            Write-Host "Архив создан: $archivePath" -ForegroundColor Green
            explorer.exe "C:\SupersetPostgres"
        } else {
            Write-Host "Ошибка: Архив не создан." -ForegroundColor Red
        }
    } catch {
        Write-Host "Ошибка: $_" -ForegroundColor Red
    }
    Write-Progress -Activity "Создание архива" -Completed
}

# Функция для распаковки архива
function Extract-Archive {
    Write-Host "Распаковка архива..." -ForegroundColor Green

    # Прогресс-бар: Начало
    $totalSteps = 4
    $currentStep = 0

    try {
        $currentStep++
        Write-Progress -Activity "Распаковка архива" -Status "Шаг ${currentStep} из ${totalSteps}: Выбор архива" -PercentComplete (($currentStep / $totalSteps) * 100)
        Write-Host "Выберите архив в открывшемся окне." -ForegroundColor Yellow
        explorer.exe "C:\SupersetPostgres"
        $archivePath = Read-Host "Введите полный путь к архиву (например, C:\SupersetPostgres\pgdata_backup.tar.gz)"

        $currentStep++
        Write-Progress -Activity "Распаковка архива" -Status "Шаг ${currentStep} из ${totalSteps}: Проверка пути" -PercentComplete (($currentStep / $totalSteps) * 100)
        if (-not (Test-Path $archivePath)) {
            Write-Host "Ошибка: Архив не найден." -ForegroundColor Red
            return
        }

        $currentStep++
        Write-Progress -Activity "Распаковка архива" -Status "Шаг ${currentStep} из ${totalSteps}: Подготовка тома" -PercentComplete (($currentStep / $totalSteps) * 100)
        docker volume rm pgdata -f 2>$null
        docker volume create pgdata 2>&1 | Out-Null

        $currentStep++
        Write-Progress -Activity "Распаковка архива" -Status "Шаг ${currentStep} из ${totalSteps}: Распаковка" -PercentComplete (($currentStep / $totalSteps) * 100)
        docker run --rm -v pgdata:/data -v "${archivePath}:/backup/pgdata_backup.tar.gz" ubuntu tar xzf /backup/pgdata_backup.tar.gz -C /data 2>&1 | Out-Null
        Write-Host "Архив распакован в том pgdata." -ForegroundColor Green
    } catch {
        Write-Host "Ошибка: $_" -ForegroundColor Red
    }
    Write-Progress -Activity "Распаковка архива" -Completed
}

# Функция для отображения данных по работе
function Show-WorkData {
    Write-Host "Данные по работе:" -ForegroundColor Green

    # Проверка рабочей директории
    $projectDir = "C:\SupersetPostgres"
    if (-not (Test-Path $projectDir)) {
        Write-Host "Ошибка: Контейнеры не установлены. Сначала выполните установку (пункт 1)." -ForegroundColor Red
        return
    }
    Set-Location $projectDir

    # Информация о подключении к Superset
    Write-Host "`n--- Superset ---" -ForegroundColor Cyan
    Write-Host "URL: http://localhost:8088" -ForegroundColor Yellow
    Write-Host "Логин: admin" -ForegroundColor Yellow
    Write-Host "Пароль: admin" -ForegroundColor Yellow
    Write-Host "Порт: 8088" -ForegroundColor Yellow

    # Информация о подключении к базе данных PostgreSQL
    Write-Host "`n--- PostgreSQL ---" -ForegroundColor Cyan
    Write-Host "Хост: localhost (или 'postgres' внутри сети контейнеров)" -ForegroundColor Yellow
    Write-Host "Порт: 5432 (внутри сети контейнеров)" -ForegroundColor Yellow
    Write-Host "Имя базы данных: superset" -ForegroundColor Yellow
    Write-Host "Логин: superset" -ForegroundColor Yellow
    Write-Host "Пароль: superset" -ForegroundColor Yellow
    Write-Host "Строка подключения: postgresql://superset:superset@postgres:5432/superset" -ForegroundColor Yellow

    # Проверка статуса контейнеров
    Write-Host "`n--- Статус контейнеров ---" -ForegroundColor Cyan
    $supersetContainer = docker ps --filter "name=superset-postgres-superset" --format "{{.Names}} {{.Status}}"
    $postgresContainer = docker ps --filter "name=superset-postgres-postgres" --format "{{.Names}} {{.Status}}"
    if ($supersetContainer) {
        Write-Host "Superset: $supersetContainer" -ForegroundColor Green
    } else {
        Write-Host "Superset: Не запущен" -ForegroundColor Red
    }
    if ($postgresContainer) {
        Write-Host "PostgreSQL: $postgresContainer" -ForegroundColor Green
    } else {
        Write-Host "PostgreSQL: Не запущен" -ForegroundColor Red
    }

    # Проверка SECRET_KEY
    if (Test-Path "superset_config.py") {
        $secretKey = Get-Content "superset_config.py" | Where-Object { $_ -match "SECRET_KEY" } | ForEach-Object { $_.Split("'")[1] }
        Write-Host "`n--- Безопасность ---" -ForegroundColor Cyan
        Write-Host "SECRET_KEY: $secretKey" -ForegroundColor Yellow
    }

    Write-Host "`nДля проверки логов используйте: docker-compose logs" -ForegroundColor Magenta
}

# Основное меню
while ($true) {
    Write-Host "`nВыберите действие:" -ForegroundColor Cyan
    Write-Host "1) Установка контейнеров" -ForegroundColor Yellow
    Write-Host "2) Создание архива" -ForegroundColor Yellow
    Write-Host "3) Распаковка архива" -ForegroundColor Yellow
    Write-Host "4) Данные по работе" -ForegroundColor Yellow
    Write-Host "5) Выход" -ForegroundColor Yellow
    $choice = Read-Host "Введите номер действия"
    switch ($choice) {
        1 { Install-Containers }
        2 { Create-Archive }
        3 { Extract-Archive }
        4 { Show-WorkData }
        5 { Write-Host "Выход..." -ForegroundColor Green; break }
        default { Write-Host "Ошибка: Неверный выбор." -ForegroundColor Red }
    }
    if ($choice -eq 5) { break }
}
