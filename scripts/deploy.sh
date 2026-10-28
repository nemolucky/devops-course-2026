#!/usr/bin/env bash
# Доставка статического ресурса на devops-vm
# Использование: scripts/deploy.sh [--dry-run]
set -euo pipefail

REMOTE="devops"
REMOTE_DIR="/var/www/devops-site"
SITE_URL="https://devops.local"
CA_CERT="${HOME}/devops.crt"
REPO_ROOT="$(git rev-parse --show-toplevel)"
LOCAL_DIR="${REPO_ROOT}/site/"

# 1. Разбор аргумента
DRY_RUN=0
case "${1:-}" in
  "") ;;
  --dry-run) DRY_RUN=1 ;;
  *) echo "Использование: $0 [--dry-run]" >&2; exit 2 ;;
esac

# 2. Проверки (требования 4 и 5)
if [[ ! -f "${LOCAL_DIR}index.html" ]]; then
  echo "Ошибка: site/index.html отсутствует, доставка отменена" >&2
  exit 1
fi
if [[ -n "$(git -C "${REPO_ROOT}" status --porcelain)" ]]; then
  echo "Ошибка: есть незафиксированные изменения, доставка отменена" >&2
  exit 1
fi

# 3. Синхронизация: одно SSH-соединение, без запроса пароля
RSYNC_OPTS=(-avz --delete --chmod=D755,F644
  -e "ssh -o BatchMode=yes -o ConnectTimeout=5 -o ConnectionAttempts=3")
if (( DRY_RUN )); then
  RSYNC_OPTS+=(--dry-run)
fi
if ! rsync "${RSYNC_OPTS[@]}" "${LOCAL_DIR}" "${REMOTE}:${REMOTE_DIR}/"; then
  echo "Ошибка: синхронизация не выполнена" >&2
  exit 1
fi

# 4. Для --dry-run на этом всё
if (( DRY_RUN )); then
  echo "dry-run завершён, сервер не изменён"
  exit 0
fi

# 5. Проверка доступности с проверкой сертификата (без -k)
if ! curl -fsS --cacert "${CA_CERT}" --max-time 10 -o /dev/null "${SITE_URL}/"; then
  echo "Ошибка: ${SITE_URL} недоступен после доставки" >&2
  exit 1
fi

echo "Деплой выполнен, коммит $(git -C "${REPO_ROOT}" rev-parse --short HEAD)"
