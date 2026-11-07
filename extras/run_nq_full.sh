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

# 完整性校验：必须通过，否则不执行（fail-closed）
if ! curl -fsSL --max-time 10 "$REPO_RAW/SHA256SUMS" -o /tmp/nq-SHA256SUMS; then
  echo "SHA256SUMS 下载失败，拒绝执行" >> status.log; exit 1
fi
if ! ( cd /root && grep -E "NodeQuality\.sh|ipq-hermes\.sh" /tmp/nq-SHA256SUMS \
         | sed 's|  extras/|  |' | sha256sum -c - ) >> status.log 2>&1; then
  echo "sha256 校验未通过，拒绝执行" >> status.log; exit 1
fi

echo "=== [$(date -Is)] NQ 开始（深度全量 v/y/y/y）" >> status.log
printf 'v\ny\ny\ny\n' | env TERM=xterm LANG=C.UTF-8 HERMES_IPQ=/root/ipq-hermes.sh \
  bash /root/NodeQuality.sh ${NQ_OPTS:-} -D "$WORK" > nq.log 2>&1
echo "NQ exit=$? [$(date -Is)]" >> status.log

# 只清理本次工作目录下的挂载，不做全局关键词卸载
for m in "$WORK/BenchOs/proc" "$WORK/BenchOs/sys" "$WORK/BenchOs/dev"; do
  findmnt -rn -M "$m" >/dev/null 2>&1 && { umount -R "$m" || echo "卸载失败：$m，请手工处理" >> status.log; }
done

echo "--- NQ 报告链接:" >> status.log
grep -aoE 'https://nodequality\.com/r/[A-Za-z0-9_-]+' nq.log | tail -1 >> status.log
echo "--- 分段静态报告（可直接打开）:" >> status.log
grep -aoE 'Report\.Check\.Place/(hardware|ip|net)/[A-Za-z0-9_-]+\.svg' nq.log | sort -u >> status.log

echo "=== [$(date -Is)] 完成" >> status.log
cat status.log
touch "$WORK/.done"
