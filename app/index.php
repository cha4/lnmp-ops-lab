<?php
declare(strict_types=1);

// ---- 请求计数（写本地文件，不依赖 Redis）----
$cf = '/tmp/req_total';
$cfp = @fopen($cf, 'c+');
if ($cfp) {
    if (flock($cfp, LOCK_EX)) {
        $cur = (int)stream_get_contents($cfp);
        ftruncate($cfp, 0);
        rewind($cfp);
        fwrite($cfp, (string)($cur + 1));
        fflush($cfp);
        flock($cfp, LOCK_UN);
    }
    fclose($cfp);
}

$rows   = [];
$status = '';
$redis  = null;

// ---- 熔断器：Redis 失败后 30 秒内不再尝试 ----
$cbFile    = '/tmp/redis_down_until';
$now       = time();
$downUntil = is_readable($cbFile) ? (int)@file_get_contents($cbFile) : 0;

if ($now >= $downUntil) {
    try {
        $redis = new Redis();
        $redis->connect('redis', 6379, 0.2);
        $cached = $redis->get('products');
        if ($cached !== false) {
            $rows   = json_decode($cached, true) ?: [];
            $status = '缓存命中（Redis）';
        }
    } catch (Throwable $e) {
        @file_put_contents($cbFile, (string)($now + 30));  // 打开熔断 30 秒
        $redis = null;
    }
}

// ---- 缓存未命中或不可用 → 回退查 MySQL（降级）----
if ($rows === []) {
    try {
        $dbHost = getenv('DB_HOST') ?: 'mysql';
        $dbName = getenv('DB_NAME') ?: 'shop';
        $dbUser = getenv('DB_USER') ?: 'root';
        $dbPass = getenv('DB_PASS') ?: '';

        $pdo = new PDO(
            sprintf('mysql:host=%s;dbname=%s;charset=utf8mb4', $dbHost, $dbName),
            $dbUser,
            $dbPass,
            [
                PDO::ATTR_ERRMODE    => PDO::ERRMODE_EXCEPTION,
                PDO::ATTR_PERSISTENT => true,
            ]
        );
        $rows = $pdo->query('SELECT id, name, price FROM products')->fetchAll(PDO::FETCH_ASSOC);

        if ($redis !== null) {
            try {
                $redis->setex('products', 60, json_encode($rows, JSON_UNESCAPED_UNICODE));
                $status = '回源查询（MySQL）并写入缓存';
            } catch (Throwable $e) {
                $status = '回源查询（MySQL），写缓存失败';
            }
        } else {
            $status = '缓存不可用，已降级直查 MySQL';
        }
    } catch (Throwable $e) {
        $status = '数据库不可用：' . $e->getMessage();
    }
}
?>
<!doctype html>
<meta charset="utf-8">
<title>LNMP 环境</title>
<h1>LNMP 环境已打通</h1>
<p>容器：<?= gethostname() ?> ｜ PHP：<?= PHP_VERSION ?></p>
<p>状态：<?= htmlspecialchars($status) ?></p>
<ul>
<?php foreach ($rows as $r): ?>
    <li><?= $r['id'] ?> - <?= htmlspecialchars($r['name']) ?> - ￥<?= $r['price'] ?></li>
<?php endforeach; ?>
</ul>
