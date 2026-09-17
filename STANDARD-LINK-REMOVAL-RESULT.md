# W1701K 标准 MLO Link Removal 实测结果

日期：2026-09-17

## 结论

**Link 1 和 Link 2 的标准移除与剩余 Link 接管均通过。**

两个方向的 `remove_link 20` 都使 AP 的活动 Link 从 2 条变为 1 条，剩余 Link 全程维持通信。每轮 AP 与主路由各采集 123 个连续样本，均为零丢包、最长中断 0 ms；Boot ID 未变化，关键内核日志为 0。

## 测试条件

- 固件：`MLO-diag-20260916 r0-94bf0a3-mlodiag1`
- Boot ID：`<redacted-boot-id>`
- 客户端：Qualcomm FastConnect 7800
- 初始 Link 1：5 GHz / 160 MHz
- 初始 Link 2：6 GHz / 320 MHz
- 初始协商速率：5764.8 Mbps
- 命令：`hostapd_cli -p /var/run/hostapd -i ap-mld0 -l<id> remove_link 20`
- 首次测试前 MLO 已连续关联约 2 小时 43 分钟，未出现关键错误

## Link 1 移除

- `remove_link 20`：返回 `OK`
- AP Link 数：2 → 1
- 被移除：Link 1，5 GHz
- 保留：Link 2，6 GHz
- AP 连通性：123/123，丢包 0，最长中断 0 ms
- 主路由连通性：123/123，丢包 0，最长中断 0 ms
- Boot ID：未变化
- 新增关键日志：0

hostapd 日志在 00:22:45 记录 5 GHz 接口 `phy0.1-ap0` 下线。AP `iw dev ap-mld0 info` 随后只显示 Link 2。

Windows `netsh` 在 15 秒观察窗内仍缓存两条 Link，因此旧脚本产生假失败。Windows Link 列表不再作为真实活动 Link 数的硬判据。

## Link 2 移除

- 初始 AP Link 数：2；Windows Link 数：2
- `remove_link 20`：返回 `OK`
- AP Link 数：2 → 1
- 被移除：Link 2，6 GHz
- 保留：Link 1，5 GHz / 160 MHz
- AP 连通性：123/123，丢包 0，最长中断 0 ms
- 主路由连通性：123/123，丢包 0，最长中断 0 ms
- Boot ID：未变化
- 新增关键日志：0

AP `iw dev ap-mld0 info` 明确只剩 Link 1。因此 6 GHz Link 移除后由 5 GHz Link 接管也通过。

## 恢复行为

普通 `wifi reload` 没有把已移除的 Link 加回 MLD，因此不能作为 Link Removal 后的恢复方法。

已验证的新恢复方式：

1. 完整关闭测试 MLD；
2. 确认 `ap-mld0` 消失；
3. 重新启用测试 MLD；
4. 确认 AP 两条 Link 均恢复；
5. 最终关闭 MLO并提交安全状态。

AP 侧完整重建已验证为 `2 Link → MLD 消失 → 2 Link`。Link 2 测试的重建后，AP 已恢复两条 Link，但 Windows 刚完成关联时只显示一条。探针现已增加最多 45 秒的 Windows 双 Link 收敛等待；本轮没有为了验证该等待逻辑而重复 Link Removal。

## 探针修正

新版 `g3-mlo-single-link-probe.ps1` 已改为：

- 使用 AP `iw dev ap-mld0 info` 判断真实 Link 数和 Link ID；
- 要求目标 Link 消失、另一 Link 保留；
- Windows Link 列表只作客户端侧参考；
- 从已提交的 MLO 关闭状态临时启用测试 MLO；
- MLD 创建后每 5 秒重试 Windows 连接；
- 初次连接与重建后最多等待 45 秒双 Link 收敛；
- Link Removal 后完整拆除并重建 MLD；
- 无论测试成功或失败，最终提交 `disabled=1`、`mlo=0` 并切回 Redmi 备用 AP。

旧版实际运行脚本保存在 `evidence/g3-mlo-single-link-probe-v1.ps1`。

## 尚未验证

- 多轮连续 Link Removal；
- 完整 MLD 重建后 Windows 双 Link 在 45 秒内恢复；
- 受控干扰或真实射频遮挡条件下的接管；
- 5 GHz 160 + 6 GHz 160 与 6 GHz 320 的完整吞吐/时延 A/B。

## 最终安全状态

- MLO：`disabled=1`、`mlo=0`
- 未提交无线改动：0
- `ap-mld0`：不存在
- 电脑：连接 Redmi 备用 AP
- lan1：2500 Mbps、全双工、RX/TX error 为 0
- 关键日志计数：0
- Boot ID：未变化

