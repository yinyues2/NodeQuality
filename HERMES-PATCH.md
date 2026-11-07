# NodeQuality · Hermes 修补版

本分支（`hermes-fixed`）是 [LloydAsp/NodeQuality](https://github.com/LloydAsp/NodeQuality) 的一个修补分支，基线为上游 commit `a92fca6`（2026-03-17，v2026-05-21 脚本）。用途：把「IP 质量」段里几个会误判的检测逻辑修好，其余测试逻辑与上游完全一致。

## 修了什么

上游 NodeQuality 的 IP 质量段实际执行的是 `curl -Ls https://IP.Check.Place`（经核对与 [xykt/IPQuality](https://github.com/xykt/IPQuality) 的 `ip.sh` **字节完全相同**：`sha256 b30df5a3…`，108,641 B，v2026-09-16）。该脚本的流媒体判定基于「单次裸 curl + 关键词匹配」，在带反爬的站点上会误报：

| 项目 | 上游判定 | 真实情况 | 原因 | 修补 |
|---|---|---|---|---|
| AmazonPV | 屏蔽 | 可用（`currentTerritory=ES`） | 裸 curl 拿到 Amazon 反爬页 `Website Temporarily Unavailable`（521 B），找不到 `currentTerritory` 字段 | 加浏览器请求头 + 最多 3 次重试，第 2 次起换 `https://www.primevideo.com/region/eu` |
| Reddit | 屏蔽 | 网页可用 | 只探测 `/svc/shreddit/reddit-chat` 内部接口，对机房/新 IP 一律 403 | 先测 `https://www.reddit.com/`（带浏览器头），非 200 再回退原接口 |
| Netflix | 方式 `DNS` | 原生解锁 | `Check_DNS_2` 把 `dig` 应答记录数 **≤2** 当作 DNS 解锁特征；`netflix.com` 正常就返回 2 条 A 记录 | Netflix/Reddit 的 `Get_Unlock_Type` 剔除该探针，只保留「解析到内网/与 DNS 同段」和「通配符劫持」 |

修补只作用于**检测能力**（请求方式、探测端点、错误启发式），不改任何判定阈值去把「屏蔽」粉饰成「解锁」。每处修补都有独立实测证据：带浏览器头重取 `primevideo.com` 得 200 / 570 KB 且含 `"currentTerritory":"ES"`；`reddit.com` 首页 200 而 `/svc/...` 403；`dig netflix.com` 得 `ANSWER: 2`（且解析到 `207.45.72.1/73.1`，RDAP 归属 NETFL-31 / Netflix 自有网段）。

## 文件

| 文件 | 说明 |
|---|---|
| `NodeQuality.sh` | 上游脚本 + 1 处补丁：`run_ip_quality()` 若存在 `$HERMES_IPQ`（默认 `/root/ipq-hermes.sh`）就拷进 chroot 执行，否则回退上游 `IP.Check.Place` |
| `extras/ipq-hermes.sh` | 修补版 IPQuality（AGPL-3.0，源自 xykt/IPQuality v2026-09-16），版本串标为 `v2026-09-16-hermes` |
| `extras/run_nq_full.sh` | 一条命令跑完整深度模式（`v / y / y / y`：硬件全量 + IP + 网络 + 回程），跑完自动抓报告链接 |

## 用法

```bash
# 深度全量，一条命令（推荐）
curl -fsSL https://raw.githubusercontent.com/yinyues2/NodeQuality/hermes-fixed/extras/run_nq_full.sh -o run_nq_full.sh
curl -fsSL https://raw.githubusercontent.com/yinyues2/NodeQuality/hermes-fixed/NodeQuality.sh -o NodeQuality.sh
curl -fsSL https://raw.githubusercontent.com/yinyues2/NodeQuality/hermes-fixed/extras/ipq-hermes.sh -o ipq-hermes.sh
bash run_nq_full.sh          # 报告链接写在 /root/bench-es01b/status.log
```

或手动：

```bash
printf 'v\ny\ny\ny\n' | env TERM=xterm HERMES_IPQ=/root/ipq-hermes.sh bash NodeQuality.sh -D /root/bench-es01b
```

`HERMES_IPQ` 指向修补版路径；不设置就退回上游行为。`-D` 指定工作目录。

## v2 修订（2026-11-08）：IPQS 分值落盘、IPv4 分支隔离、运行器加固

| 问题 | 现象 | 修补 |
|---|---|---|
| IPQS 分值写错变量 | `save_json` 用 `${ipapi[ipqs]:-null}`，该变量从未赋值，报告里 IPQS 恒为字符串 `"null"`；文本段落用的是 `${ipqs[score]}`，因此出现「文本有分、JSON 无分」 | 改为 `${ipqs[score]}`；`fraud_score` 严格校验为 0–100 的整数，否则记 `null`（缺失不等于低风险） |
| 响应解析过宽 | 非 JSON、空响应、JSON 流都会被 `jq -r '.fraud_score'` 静默吃成空值 | 先 `curl -f`，再 `jq -e -s 'length == 1 and (.[0]|type=="object")'` 只接受单个对象；`jq` 缺失直接报错退出，不再静默出空报告 |
| `-4` 仍在跑 IPv6 | `get_ipv4`/`get_ipv6` 在选项解析之前无条件调用，`-4` 只影响后续模块 | 新增 `preparse_ip_family()`，`-4`/`-6` 设置 `skip_ipv4_probe`/`skip_ipv6_probe`，两个探测函数入口即返回 |
| 错误码被覆盖 | 同时给冲突参数与 `-i/-x` 时，`ERRORcode` 被 40/60 覆盖掉 4/6 | 仅在 `ERRORcode` 不是 4/6 时才写 40/60 |
| 报告生成失败仍返回 0 | `save_json` 失败被忽略 | 显式 `return 1`，主流程打印失败并返回非 0 |
| 运行器不 fail-closed | `run_nq_full.sh` 校验失败仅警告后继续；收尾按 `bench\|BenchOs` 关键词全局卸载挂载 | 校验失败直接退出；只 `findmnt` 精确匹配 `$WORK/BenchOs/{proc,sys,dev}` 再 `umount -R`；新增 `NQ_OPTS` 透传（如 `NQ_OPTS=-4`） |

**诊断**：IPQS 取不到分时，脚本会在 stderr 打印 `IPQS: 请求失败 curl_rc=… http=…` / `IPQS: HTTP 403…` / `IPQS: 响应不是单个 JSON 对象`，报告里同时显示「无」。缺项不再和真实 0 分混在一起，日志里能直接看出是超时、非 200 还是响应格式不对。

**已知边界**：IPQS 数据仍经 `ipinfo.check.place/...?db=ipqualityscore` 代理获取，不是 IPQualityScore 官方 API；没有官方 key 时该分值只能当参考，不能当权威判定。本分支不绕过任何站点的反爬或风控。

---

## 注意

- 上游脚本自身在收尾「安装后清理」阶段会返回 `exit=1`，报告仍完整上传，属上游既有行为。
- 修补版依赖 chroot 内的 `jq curl bc dnsutils` 等，与上游一致（脚本 `-y` 自动装）。
- 许可证：AGPL-3.0（与上游一致，见 `LICENSE`）。`extras/ipq-hermes.sh` 同样 AGPL-3.0，源自 xykt/IPQuality。
- 上游更新时本分支不会自动跟进；需要的话 `git rebase` 到新的上游 commit 再重打这 4 处补丁（位置都在 `run_ip_quality()` 与 `MediaUnlockTest_*` 里，带 `[HERMES-PATCH]` 注释，`grep -n HERMES-PATCH` 可定位）。
