#!/bin/bash
# MySQL 全量备份：mysqldump + gzip + 保留 7 天
set -euo pipefail

BACKUP_DIR=/backup/mysql
KEEP_DAYS=7
TS=$(date +%Y%m%d_%H%M%S)
FILE="${BACKUP_DIR}/shop_${TS}.sql.gz"
LOG=/var/log/mysql-backup.log

log() { echo "[$(date '+%F %T')] $*" >> "$LOG"; }

log "========== 全量备份开始 =========="

# 备份前切分 binlog，便于增量恢复定位
docker exec mysql mysql -uroot -pRoot@123456 -e "FLUSH LOGS;" 2>/dev/null || true

# 全量导出（--single-transaction 不锁表；--set-gtid-purged=ON 带 GTID）
if docker exec mysql mysqldump -uroot -pRoot@123456 \
     --single-transaction --quick --set-gtid-purged=ON \
     --default-character-set=utf8mb4 \
     --databases shop 2>/dev/null | gzip > "$FILE"; then
    SIZE=$(du -h "$FILE" | cut -f1)
    log "全量备份成功: $FILE ($SIZE)"
else
    log "全量备份失败"
    exit 1
fi

# 备份当前 binlog（增量基础）
docker exec mysql sh -c 'ls /var/lib/mysql/mysql-bin.[0-9]* 2>/dev/null' | while read -r f; do
    base=$(basename "$f")
    docker cp "mysql:$f" "${BACKUP_DIR}/binlog/${base}" 2>/dev/null && log "binlog: $base"
done

# 清理超过保留期的文件
find "$BACKUP_DIR" -name "shop_*.sql.gz" -mtime +${KEEP_DAYS} -delete 2>/dev/null || true

COUNT=$(ls -1 ${BACKUP_DIR}/shop_*.sql.gz 2>/dev/null | wc -l)
log "当前保留备份数: $COUNT"
log "========== 全量备份结束 =========="
