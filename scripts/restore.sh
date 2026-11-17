#!/bin/bash
# MySQL 恢复：指定备份文件（默认最新）
set -euo pipefail

# 从 .env 读取凭证（不硬编码）
set -a
[ -f /opt/lnmp/.env ] && . /opt/lnmp/.env
set +a
DB_PASS="${MYSQL_ROOT_PASSWORD:?未设置 MYSQL_ROOT_PASSWORD}"

FILE="${1:-$(ls -1t /backup/mysql/shop_*.sql.gz | head -1)}"
echo "使用备份: $FILE"
echo "恢复前条数:"; docker exec mysql mysql -uroot -p"$DB_PASS" --default-character-set=utf8mb4 -N -e "select count(*) from shop.products;" 2>/dev/null || true
gunzip -c "$FILE" | sed -e '/GTID_PURGED/d' -e '/SQL_LOG_BIN/d' | \
  docker exec -i mysql mysql -uroot -p"$DB_PASS" --default-character-set=utf8mb4
echo "恢复后条数:"; docker exec mysql mysql -uroot -p"$DB_PASS" --default-character-set=utf8mb4 -N -e "select count(*) from shop.products;" 2>/dev/null
