#!/bin/bash
# NodeQuality 深度全量（Hermes 修补版）
# 硬件 v（所有测试细节）+ IP 质量 + 网络质量 + 回程路由 全部跑，跑完打印报告链接。
# 用法: bash run_nq_full.sh [工作目录]，默认 /root/bench-es01b
set -u
REPO_RAW="${REPO_RAW:-https://raw.githubusercontent.com/yinyues2/NodeQuality/hermes-fixed}"
BENCH="${1:-${BENCH:-/root/bench-es01b}}"
WORK="$BENCH"

mkdir -p "$WORK" || exit 1
cd "$WORK" || exit 1

echo "=== [$(date -Is)] 下载脚本（$REPO_RAW）" > status.log
curl -fsSL --retry 3 "$REPO_RAW/NodeQuality.sh"       -o /root/NodeQuality.sh   || { echo "NodeQuality.sh 下载失败" >> status.log; exit 1; }
curl -fsSL --retry 3 "$REPO_RAW/extras/ipq-hermes.sh" -o /root/ipq-hermes.sh   || { echo "ipq-hermes.sh 下载失败" >> status.log; exit 1; }
chmod +x /root/NodeQuality.sh /root/ipq-hermes.sh

# 可选完整性校验（仓库内 SHA256SUMS，取不到就跳过）
if curl -fsSL --max-time 10 "$REPO_RAW/SHA256SUMS" -o /tmp/nq-SHA256SUMS 2>/dev/null; then
  (cd /root && grep -E "NodeQuality\.sh|ipq-hermes\.sh" /tmp/nq-SHA256SUMS | sha256sum -c --status) \
    && echo "sha256 校验通过" >> status.log || echo "警告：sha256 校验未通过（继续执行）" >> status.log
fi

echo "=== [$(date -Is)] NQ 开始（深度全量 v/y/y/y）" >> status.log
printf 'v\ny\ny\ny\n' | env TERM=xterm LANG=C.UTF-8 HERMES_IPQ=/root/ipq-hermes.sh \
  bash /root/NodeQuality.sh -D "$WORK" > nq.log 2>&1
echo "NQ exit=$? [$(date -Is)]" >> status.log

# 清理 NQ 可能残留的 bind mount
for m in $(mount | awk '/bench|BenchOs/{print $3}'); do umount -l "$m" 2>/dev/null; done

echo "--- NQ 报告链接:" >> status.log
grep -aoE 'https://nodequality\.com/r/[A-Za-z0-9_-]+' nq.log | tail -1 >> status.log
echo "--- 分段静态报告（可直接打开）:" >> status.log
grep -aoE 'Report\.Check\.Place/(hardware|ip|net)/[A-Za-z0-9_-]+\.svg' nq.log | sort -u >> status.log

echo "=== [$(date -Is)] 完成" >> status.log
cat status.log
touch "$WORK/.done"
