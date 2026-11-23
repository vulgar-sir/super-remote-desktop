# NOTICE / 修改声明

super远程桌面（SuperDesk）是 RustDesk 的修改版本（modified version），依据 GNU Affero General Public License v3.0
第 5 条作出以下声明。

## 原作品

- RustDesk 1.5.3 — https://github.com/rustdesk/rustdesk
  Copyright © Purslane Tech Pte. Ltd. and RustDesk contributors, licensed under AGPL-3.0.
- hbb_common（`libs/hbb_common` 子模块）— https://github.com/rustdesk/hbb_common ，RustDesk 项目的一部分。
- rustdesk-server（hbbs / hbbr，服务端补丁的修改对象）— https://github.com/rustdesk/rustdesk-server ，AGPL-3.0。

## 修改

- 修改者：super远程桌面 贡献者
- 修改时间：2026 年 11 月起（基于 RustDesk 1.5.3），持续更新；每项修改的日期与内容以本仓库 git 提交记录为准。
- 修改范围：
  - 新增 `superdesk/`（服务端配置、super控制台、hbbs 补丁、构建 / 发布 / 部署脚本、测试、文档）；
  - 新增 `flutter/lib/superdesk/`、`src/superdesk.rs`、`src/superdesk/`（客户端新界面与新功能）；
  - 对 RustDesk 原有文件的挂接改动、程序名称 / 包名 / 图标的更换，以及 `libs/hbb_common` 中的两处改动，
    逐项列在 [superdesk/README.md](superdesk/README.md#对-rustdesk-源码的改动升级时需保留) 的
    “对 RustDesk 源码的改动”一节。

## 许可

修改与新增部分同样以 AGPL-3.0 授权，全文见 [LICENCE](LICENCE)。本软件不附带任何担保。

“RustDesk”名称与 Logo 属于其权利人；本项目使用自有名称与图标，与 RustDesk 官方无关联。
