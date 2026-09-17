# FastConnect 7800 终端无线诊断

日期：2026-09-17

## 直接结论

当前 5 GHz + 6 GHz MLO 不叠加吞吐的主要限制来自终端上报的 MLD 能力，而不是 W1701K 未建立两条 Link。

hostapd 的 `max_simul_links=1` 来自 `sta->mld_info.common_info.mld_capa`，即客户端关联信息中的 MLD capability。构建源码 `src/ap/ctrl_iface_ap.c` 明确从 station 数据取值后输出该字段。AP 自身已建立 Link 1 和 Link 2；任一 Link 被移除时，另一 Link 均能继续通信。

最后一次下行测试的驱动按无线电统计为：5 GHz 成功 4 MPDU，6 GHz 成功 776,690 MPDU。当前会话只有一条链路承担主要批量数据，符合 `max_simul_links=1`。

## 当前终端状态

- 电脑：Lenovo XiaoXinPro 16ACH 2021，型号 82L5
- Windows 11 Pro：10.0.26200
- 网卡：Qualcomm FastConnect 7800，PCI ID `VEN_17CB&DEV_1107`，子系统 `8D68103C`
- 实际驱动段：`QcWlan_NCM835_H.ndi.NTamd64`
- 驱动：Qualcomm `3.1.0.1647`，2026-01-21，WHQL 签名
- 板级文件：`bdwlan_wcn785x_2p0_ncm835_QC_revB.elf`
- PCIe：Gen3 x1，8.0 GT/s；无设备错误码
- RSS：Disabled，驱动提供 4 个接收队列
- 无线模式：802.11a/b/g/n/ac/ax/be
- 5 GHz、6 GHz 信道宽度：Auto
- Throughput Acceleration：Enable

Microsoft Update Catalog 中当前最高版本是 `3.1.0.1647`；Windows Update 没有找到未安装的 Qualcomm 无线驱动。当前无需降级或更换来源不明的驱动。

## 驱动和硬件判断

当前物理卡的子系统 ID 属于 HP，INF 正确选择了 HP 专用 NCM835 段。电脑主体是 Lenovo 并不意味着应强制使用 Lenovo NCM835 段；强制改 INF 会使板级文件与实际卡片子系统不匹配。

同一个 Qualcomm 驱动 INF 把 NCM835 命名为 `Dual Band Simultaneous (DBS)`，把 NCM865 命名为 `High Band Simultaneous (HBS)`。当前目标是 5 GHz + 6 GHz 两个高频段同时承担数据，NCM835 与 NCM865 的 SKU 区别是强烈的硬件边界信号。现有证据能确认当前 NCM835 会话只上报一个 simultaneous link，但不能仅凭 INF 名称断言所有平台上的 NCM835 永远如此。

## RSS 检查

尝试启用 RSS 时 Windows 返回 Access Denied，因此设置没有改变，网卡也没有重启。A/B 测试没有在未提权状态下强行继续。

已有 iperf3 JSON 显示，6 GHz 和 MLO 测试时 Windows 端 CPU 总占用约 2.3%–17.6%，远未饱和。RSS 可能改善多核分流，但不负责修改客户端 MLD capability，也不能把 `max_simul_links=1` 变为 2。它不是当前 MLO 单链路调度的主要原因。

## 可行改进顺序

1. 保留当前 `3.1.0.1647` 驱动；它是目前 Catalog 可见的最新版本。
2. 日常性能优先时使用 6 GHz/320 MHz；需要故障接管时使用 MLO 160+320。
3. 后续出现高于 `3.1.0.1647` 的正式驱动时，再核对 `max_simul_links` 并重复逐无线电统计。
4. 若一定要验证 RSS，可在管理员 PowerShell 中启用后只做一次 6 GHz 与 MLO A/B；若提升不足 10%，恢复 Disabled。该测试针对主机处理效率，不针对 MLO 同时链路数。
5. 若目标是 5+6 GHz 真正同时聚合，优先验证明确标注 HBS 的 NCM865/同等客户端及其平台兼容性。更换硬件前应确认 M.2 接口、电气、蓝牙 USB、天线和 BIOS 兼容性。

## 回退资料

当前驱动包和网卡注册表已备份到 `client-driver-backup-3.1.0.1647`。备份仅用于回退，不包含无线密码。

Microsoft Update Catalog：<https://www.catalog.update.microsoft.com/Search.aspx?q=Qualcomm%20FastConnect%207800>

Qualcomm FastConnect 7800：<https://www.qualcomm.com/wi-fi/products/fastconnect/fastconnect-7800>


