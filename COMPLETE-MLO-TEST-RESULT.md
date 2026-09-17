# Gemtek W1701K MLO 完整测试结果

测试日期：2026-09-17（Asia/Shanghai）

## 结论

诊断固件 `MLO-diag-20260916 r0-94bf0a3-mlodiag1` 已通过稳定性、双向 Link Removal、MLD 完整重建、单频与 MLO 性能、有线回程以及安全恢复测试。测试期间 AP Boot ID 始终为 `<redacted-boot-id>`，关键内核日志新增为 0，未出现 RCU stall、PS-sync 卡死、firmware reset/assert、panic 或 watchdog。

MLO 功能可用且具备链路接管能力，但当前 FastConnect 7800、Windows 驱动与 AP 的协商只允许一个 Link 同时承担主要数据。客户端记录为 `max_simul_links=1`。两条 Link 均能建立，任意移除一条后另一条能维持通信；在单客户端 TCP 吞吐测试中，批量流量几乎全部走 6 GHz Link 2，没有形成 5 GHz 与 6 GHz 的并行吞吐叠加。

Windows 显示的 2882.4 或 5764.8 Mbps 是动态 PHY 协商值，不是两条 Link 的实测总吞吐。相同的 5764.8 Mbps 也出现在 6 GHz/320 MHz 单频连接上，因此不能用这个数字判断 MLO 是否聚合。

## 测试环境

- AP：Gemtek W1701K，`gemtek,w1701k-ubi`
- 固件：ImmortalWrt SNAPSHOT `r0-94bf0a3`，内核 `6.18.38`
- PS-sync 修复：完整 `r2` 修复
- 客户端：Qualcomm FastConnect 7800 Wi-Fi 7 DBS
- Windows 驱动：`3.1.0.1647`，2026-01-21
- AP 上联：`lan1`，2500 Mbps，全双工
- 有线测试服务器：主路由 `192.0.2.1`，iperf3 3.17.1
- Windows iperf3：3.21，8 并行流，15 秒，忽略前 2 秒

## 功能与恢复测试

| 项目 | 结果 | 证据 |
|---|---:|---|
| MLO 初始关联 | 通过 | AP 2 Link，Windows 2 Link |
| 完整拆除 MLD | 通过 | `ap-mld0` 消失 |
| 重建 MLD | 通过 | AP 恢复 2 Link |
| 重建后客户端恢复 | 通过 | Windows 在最长 60 秒窗口内恢复 2 Link；本次约 21.3 秒 |
| 移除 Link 1 | 通过 | Link 2 保留；AP 与主路由各 123/123，零丢包 |
| 移除 Link 2 | 通过 | Link 1 保留；AP 与主路由各 123/123，零丢包 |
| AP 重启检查 | 通过 | Boot ID 未变化 |
| 关键内核日志 | 通过 | 计数 0 |
| 失败路径自动恢复 | 通过 | 每次失败或完成后均恢复已提交的 MLO-off 配置 |

Windows 在保持连接 Redmi 时有时只返回当前 BSS 的扫描缓存，导致 `network is not available`。自动测试已改为先断开当前连接、触发完整扫描，再连接 MLO。此后关联和重建均稳定通过。

## 性能结果

方向定义：上行是 Windows 客户端到主路由；下行是主路由到 Windows 客户端。每组延迟为 50 个样本。

| 模式 | Windows Link | 丢包 | 平均 / P95 延迟 | 上行 | 下行 |
|---|---:|---:|---:|---:|---:|
| 5 GHz / 160 MHz | 1 | 0/50 | 6.86 / 14 ms | 0.232 Gbps | 0.527 Gbps |
| 6 GHz / 320 MHz | 1 | 0/50 | 7.44 / 11 ms | 0.306 Gbps | 0.616 Gbps |
| MLO 160+320，首次 | 2 | 0/50 | 8.10 / 14 ms | 0.226 Gbps | 0.504 Gbps |
| MLO 160+320，复测 1 | 2 | 0/50 | 4.38 / 10 ms | 0.224 Gbps | 0.509 Gbps |
| MLO 160+320，复测 2 | 2 | 0/50 | 4.74 / 10 ms | 0.302 Gbps | 0.648 Gbps |
| MLO 160+160，首次 | 2 | 0/50 | 4.68 / 13 ms | 0.224 Gbps | 0.513 Gbps |
| MLO 160+160，复测 | 2 | 0/50 | 4.64 / 12 ms | 0.227 Gbps | 0.512 Gbps |

MLO 160+320 的复测范围为上行 0.224–0.302 Gbps、下行 0.504–0.648 Gbps。它与 6 GHz/320 单频的 0.306/0.616 Gbps 基本处于同一水平。MLO 160+160 两次结果高度一致，但没有吞吐优势。

## 逐 Link 调度证据

`hostapd_cli -l1/-l2 all_sta` 的 `rx_bytes/tx_bytes` 是镜像的 MLD 汇总计数，不能解释为两条 Link 各占 50%。该证据已明确标为无效，未用于结论。

mt7996 驱动的按无线电统计显示，在最后一次 MLO 160+320 测试中：

| 阶段 | 5 GHz Link 1 成功 MPDU | 6 GHz Link 2 成功 MPDU |
|---|---:|---:|
| 上行阶段 AP 发送活动 | 114 | 55,574 |
| 下行批量数据 | 4 | 776,690 |

下行批量数据几乎全部由 6 GHz Link 2 发送。5 GHz Link 1 保持关联并可在 Link 2 被移除后接管，但没有与 Link 2 同时叠加这次 TCP 吞吐。

`hostapd` 客户端信息同时报告 `max_simul_links=1`。这说明当前客户端、驱动和 AP 会话协商出的并行能力为一个 Link，符合上述无线电统计。该结果描述当前组合，不等同于 FastConnect 7800 硬件永远不能实现其他 MLO 模式。

## 有线回程

| 方向 | 吞吐 |
|---|---:|
| AP → 主路由 | 2.355 Gbps |
| 主路由 → AP | 1.757 Gbps |

AP 到主路由的有线路径明显高于无线实测，2.5G 端口和网线不是当前 0.5–0.65 Gbps 的主要瓶颈。

## 终端无线诊断

进一步检查确认 `max_simul_links=1` 是客户端关联信息中的能力值。当前 NCM835 使用最新 Catalog 驱动 `3.1.0.1647`，没有可见的 MLO/STR/EMLSR 开关；PCIe 与 CPU 也未形成吞吐瓶颈。详细分析和硬件升级边界见 `CLIENT-WIFI-DIAGNOSIS.md`。

## 推荐配置

1. 若优先追求当前单客户端吞吐，保留 6 GHz `EHT320`。MLO 使用 `5 GHz/160 + 6 GHz/320` 即可；改成 160+160 没有性能收益。
2. 若优先追求链路接管，可启用 MLO。双向 Link Removal 已证明任一 Link 可独立维持通信。
3. 若目标是两条 Link 同时叠加吞吐，需要让会话协商出至少两个 simultaneous links。优先尝试更新 OEM/Qualcomm 驱动和 Windows 无线组件，再检查 `max_simul_links`。当前驱动高级属性没有暴露单独的 MLO、STR 或 DBS 开关。
4. 客户端高级属性中 RSS 当前为 Disabled；可在单独的可回退 A/B 测试中尝试启用，但它只能改善主机处理并行度，不能保证把 `max_simul_links=1` 变成双 Link 同时传输。
5. 当前固件启用了诊断测试接口 `CONFIG_TESTING_OPTIONS`。日常使用前应构建同一修复、同一硬件配置但不含测试接口的生产固件，再做一次短回归测试。

## 当前安全状态

- Windows 已连接 Redmi 备用 AP `Gemtek_W1701K`
- W1701K：`wireless.mlo1.disabled=1`、`wireless.mlo1.mlo=0`
- `radio2.htmode=EHT320`
- `ap-mld0` 不存在
- 未提交无线改动：0
- Boot ID 未变化
- 关键日志计数：0
- 主路由临时 iperf3 服务已停止，PID 文件不存在
- `lan1`：2500 Mbps、full duplex；RX/TX error 为 0
- 2.4 GHz 隐藏设置保留

## 测试边界

结果来自一台客户端、一个位置、当前信道和 15 秒 TCP 窗口。它足以判断稳定性、故障接管、当前调度方式和大致吞吐，但不是多客户端容量、远距离覆盖、邻频干扰或长期老化测试。没有 UART，因此所有测试都保持物理 Reset、完整备份和备用 AP 可用。



