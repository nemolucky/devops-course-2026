# Конфигурация виртуальной машины devops-vm

## 1. Параметры машины

- Гипервизор: VirtualBox 7.x, гостевая система Ubuntu Server 24.04 LTS (64-bit).
- Наименование: devops-vm. Оперативная память: 2048 МБ. Процессор: 2 ядра.
- Диск: 25 ГБ, динамически расширяемый, разметка Use an entire disk.
- Установка: язык English, имя узла devops-vm, пользователь student, компонент OpenSSH server, Featured snaps не выбирались.

## 2. Сетевые интерфейсы

- Адаптер 1: NAT, интерфейс enp0s3, адрес 10.0.2.15. Назначение: доступ в Интернет (репозитории пакетов).
- Адаптер 2: Host-only, интерфейс enp0s8, адрес 192.168.56.102 (выдаётся по DHCP, проверять командой `ip -brief address`). Назначение: доступ с хоста к серверу и браузеру.
- Локальное имя: на хосте в файле hosts запись `192.168.56.102 devops.local`. На сервере `sudo hostnamectl set-hostname devops-vm` и в /etc/hosts строка `127.0.1.1 devops-vm.devops.local devops-vm`. Проверка: `hostname -f` возвращает devops-vm.devops.local.

## 3. Правило проброса портов

Адаптер 1 (NAT): правило ssh, протокол TCP, адрес хоста 127.0.0.1, порт хоста 2222, порт гостя 2222 (изначально 22, изменено после перехода sshd на порт 2222).

## 4. Учётные записи

- student: создан установщиком, входит в группу sudo, для удалённого входа не используется.
- devops: `sudo adduser devops`, `sudo usermod -aG sudo devops`. Вход только по ключу ed25519 (пара devops_vm на хосте, открытый ключ в /home/devops/.ssh/authorized_keys, права каталога .ssh 700 и файла 600).
- root: удалённый вход запрещён.

## 5. Служба SSH

- Порт: 2222. Файл конфигурации: /etc/ssh/sshd_config.d/99-hardening.conf (основной sshd_config не изменяется, резервная копия sshd_config.backup).
- Директивы: Port 2222, PermitRootLogin no, PasswordAuthentication no, PubkeyAuthentication yes, PermitEmptyPasswords no, MaxAuthTries 3, LoginGraceTime 30, AllowUsers devops, X11Forwarding no, ClientAliveInterval 300, ClientAliveCountMax 2.
- Конфликтующая директива PasswordAuthentication в /etc/ssh/sshd_config.d/50-cloud-init.conf (если есть) закомментирована.
- Применение: `sudo sshd -t`, `sudo systemctl disable --now ssh.socket`, `sudo systemctl enable --now ssh.service`, `sudo systemctl restart ssh`. Проверка порта: `sudo ss -tlnp | grep sshd` (0.0.0.0:2222).
- Клиент (хост): ~/.ssh/config, блок `Host devops devops.local` (HostName devops.local, Port 2222, User devops, IdentityFile ~/.ssh/devops_vm, IdentitiesOnly yes).

## 6. Правила межсетевого экрана

- Политики: `ufw default deny incoming`, `ufw default allow outgoing`.
- Правила: `ufw limit 2222/tcp` (SSH с ограничением частоты), `ufw allow 80/tcp`, `ufw allow 443/tcp`.
- Порядок: правила создаются до `ufw enable`. Команда `ufw allow ssh` не применяется (открывает порт 22).
- Журналирование: `ufw logging medium`.

## 7. Снимки состояния

- 01-clean-install: 22.10.2026 16:39, чистая установка.
- 02-keys-configured: 22.10.2026 17:10, после настройки ключей.
- 03-ssh-hardened: 22.10.2026 17:29, после усиления защиты SSH.
- 04-nginx-https: 28.10.2026 22:19, после настройки HTTPS.

## 8. Веб-сервер

- Пакет: nginx (`sudo apt install -y nginx`), служба включена и запущена.
- Конфигурация ресурса: /etc/nginx/sites-available/devops-site. Активация: `sudo ln -s /etc/nginx/sites-available/devops-site /etc/nginx/sites-enabled/`. Стандартный ресурс отключён: `sudo rm /etc/nginx/sites-enabled/default`.
- Каталог ресурса: /var/www/devops-site, владелец devops:devops, права 755 для каталогов и 644 для файлов. Содержимое доставляется `scripts/deploy.sh` (rsync с `--chmod=D755,F644`).
- Сертификат: /etc/ssl/certs/devops.crt (644, root). Ключ: /etc/ssl/private/devops.key (600, root).
- Команда формирования сертификата (самоподписанный, 365 дней, SAN devops.local):

```bash
sudo openssl req -x509 -nodes -days 365 -newkey rsa:2048 \
  -keyout /etc/ssl/private/devops.key \
  -out /etc/ssl/certs/devops.crt \
  -subj "/CN=devops.local" \
  -addext "subjectAltName=DNS:devops.local"
```

- Содержимое /etc/nginx/sites-available/devops-site:

```nginx
server {
    listen 80;
    listen [::]:80;
    server_name devops.local;
    return 301 https://$host$request_uri;
}

server {
    listen 443 ssl;
    listen [::]:443 ssl;
    server_name devops.local;
    ssl_certificate /etc/ssl/certs/devops.crt;
    ssl_certificate_key /etc/ssl/private/devops.key;
    ssl_protocols TLSv1.2 TLSv1.3;
    root /var/www/devops-site;
    index index.html;
    location / {
        try_files $uri $uri/ =404;
    }
    error_page 404 /404.html;
    access_log /var/log/nginx/devops-site.access.log;
    error_log /var/log/nginx/devops-site.error.log;
}
```

- Применение: `sudo nginx -t && sudo systemctl reload nginx` (только reload). HSTS не используется.
- Межсетевой экран: порты 80 и 443 уже разрешены, новых правил не требуется.


## 9. Контейнеризация

- Docker Engine установлен из официального репозитория Docker (download.docker.com),
  версия: 29.9.2. Пакеты: docker-ce, docker-ce-cli, containerd.io,
  docker-buildx-plugin, docker-compose-plugin. Пакет docker.io не используется.
- Участники группы docker: devops (`sudo usermod -aG docker devops`, затем новая
  SSH-сессия). Участник группы docker фактически получает права root, поэтому
  в группу включаются только учётные записи с правом sudo.
- Проект расположен на сервере в `/home/devops/app` (имя проекта Compose: app),
  доставляется с хоста: `rsync -avz --delete --exclude=.env app/ devops:app/`.
- Файл переменных `/home/devops/app/.env`: права 600, владелец devops, создаётся
  только на сервере из `.env.example` с паролем `openssl rand -hex 16`, в репозиторий
  не добавляется.
- Сервисы: db (postgres:16-alpine, контейнер app-db-1) и app (образ devops-app:1.0,
  контейнер app-app-1). Сеть проекта: app_backend (bridge).
- Публикуемые порты: приложение 127.0.0.1:5000 (только loopback), порт СУБД 5432
  не публикуется.
- Именованный том: app_db_data (данные PostgreSQL), сохраняется при
  `docker compose down`, удаляется при `docker compose down -v`.
- Запуск: `cd ~/app && docker compose up -d --build`.
- Обратный прокси: в блок HTTPS `/etc/nginx/sites-available/devops-site` добавлено

```nginx
    location /app/ {
        proxy_pass http://127.0.0.1:5000/;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
    }
```

  Применение: `sudo nginx -t && sudo systemctl reload nginx`. Статический ресурс
  (`location /`) сохранён.
## 10. Ansible

Практическая работа №11 выполняется после возврата VM к снимку `01-clean-install`.
Приведённые выше разделы описывают предыдущие работы; в текущей конфигурации
SSH использует порт 22, Nginx обслуживает HTTP на порту 80, HTTPS не настраивается.

### Узлы и расположение проекта

- Управляющий узел: WSL 2 Ubuntu, пользователь `denis`.
- Проект: `~/projects/devops/devops-course-2026/ansible` в файловой системе WSL.
- Управляемый узел: VirtualBox VM `devops-vm`, Ubuntu Server 24.04 amd64.
- Host-only IP: `192.168.56.102`, SSH-порт: `22`.
- Все команды Ansible ниже выполняются из каталога `ansible/`.

### Inventory и доступ

- `inventory/bootstrap.ini`: первоначальный вход от `student` по паролю с sudo.
- `inventory/prod.ini`: последующий вход от `devops` по ключу `~/.ssh/devops_vm`.
- Открытый ключ берётся из `~/.ssh/devops_vm.pub` на управляющем узле.
- Пользователь и ключ создаются до отключения парольной аутентификации.
- Для учебной автоматизации devops получает `NOPASSWD:ALL`; это полный
  административный доступ, поэтому закрытый ключ хранится вне репозитория.
- `ansible.cfg` выбирает prod inventory и содержит `force_handlers = True`.

### Роли

- `base`: проверка платформы, базовые пакеты, зависимости `python3-debian`
  и `python3-requests`, Docker Engine из официального репозитория.
- `ssh`: пользователь devops, открытый ключ, sudoers, hardening SSH и UFW.
- `nginx`: reverse proxy, отключение default site; handlers проверяют
  `nginx -t` перед reload.
- `app`: загрузка проверенного образа, запуск контейнера и проверка `/health`.

### Версия приложения и сеть

- Образ: `ghcr.io/nemolucky/devops-ci-app` (публичный GHCR-пакет).
- Полный SHA: `9851e7074462ac93ad629ea71b227ca9f57802d0`.
- Digest проверенного образа:
  `sha256:98c1ee623b2d68cfd0c45bb16d0fcfdccf811a851afa7a06e25d74372f3c59c9`.
- Имя контейнера: `devops-ci-app`.
- Публикация порта: `127.0.0.1:5000:5000`, прямой внешний доступ исключён.
- Nginx: `http://192.168.56.102/`, health: `http://192.168.56.102/health`.
- Версия задаётся через `app_tag` в `group_vars/all.yml`, тег latest не используется.
- На VM приложение не собирается: загружается готовый образ из CI работы №10.

### Команды установки и запусков

```bash
cd ~/projects/devops/devops-course-2026
ansible-galaxy collection install -r ansible/requirements.yml
cd ansible
ansible-playbook -i inventory/bootstrap.ini site.yml --syntax-check
ansible-playbook site.yml --syntax-check

# Первичная настройка: пароли вводятся интерактивно и не записываются в файлы.
ansible-playbook -i inventory/bootstrap.ini site.yml --ask-pass --ask-become-pass

# Последующие запуски: ключ и sudo без интерактивного ввода.
ansible all -m ping
ansible-playbook site.yml

# Read-only аудит состояния.
ansible-playbook verify.yml
curl --fail http://192.168.56.102/health
```

Повторный запуск site.yml без drift и оба запуска verify.yml дают `changed=0`.
Аудит проверяет эффективные настройки SSH, запущенный контейнер и health-ответ.
Остановка контейнера обнаруживается аудитом, восстановление выполняется site.yml.

### Инциденты и восстановление

- Ручное удаление контейнера и изменение upstream Nginx на порт 5001 дают HTTP 502.
  Запуск site.yml восстанавливает шаблон, контейнер и выполняет reload Nginx.
- Несуществующий app_tag вызывает отказ загрузки до изменения контейнера:
  прежний контейнер остаётся доступен. После возврата корректного SHA повторный
  запуск завершается без изменений.
- Во время работы возник отказ DNS, полученного VM через DHCP (`172.22.0.1`).
  Доступ по IP сохранялся. Временно на NAT-интерфейсе заданы DNS командой
  `sudo resolvectl dns enp0s3 1.1.1.1 8.8.8.8`; это настройка времени выполнения,
  после перезапуска сети её следует проверить повторно.
