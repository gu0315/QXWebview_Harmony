# 打包、分发与集成手册(鸿蒙)

本文讲清楚 `qx-hybrid` HAR 怎么打包、怎么发给其他团队、对方怎么引入。是 iOS `pod` / Android `aar` 在鸿蒙上的等价流程。

---

## 0. 概念对照(一句话)

- **HAR** = 鸿蒙的 `.aar`(静态共享包,编译期链接进 App)。
- **HSP** = 动态共享包(运行期加载,多个模块共用同一份时能减包体)。SDK 对外分发一般用 **HAR**。
- **OHPM** = 鸿蒙的包管理器,等价于 CocoaPods / Gradle+Maven。
- **OHPM 私有 Registry** = 你的 Maven 私服在鸿蒙上的对应物(可用 JFrog Artifactory 搭建)。

---

## 1. 打出 HAR 产物

### 方式 A:DevEco Studio(图形界面)
1. 右上角模块选 `qx_hybrid`。
2. 菜单 `Build > Make Module 'qx_hybrid'`。
3. 产物:`qx_hybrid/build/default/outputs/default/qx-hybrid.har`。

### 方式 B:命令行(CI 用)
```bash
# 在工程根目录
./hvigorw assembleHar --mode module -p module=qx_hybrid@default -p product=default
# 产物同上:qx_hybrid/build/default/outputs/default/qx-hybrid.har
```

> 版本号来自 `qx_hybrid/oh-package.json5` 的 `version`(当前 `0.1.10`)。每次发布前记得升版本。

---

## 2. 分发方式一:直接给 .har 文件(最简单)

适合还没搭私服、先联调的场景。像给对方一个 aar。

**你做的:** 把 `qx-hybrid.har` 发给对方。

**对方做的:**
1. 把文件放到工程里,例如 `entry/libs/qx-hybrid.har`。
2. 在 `entry/oh-package.json5` 加依赖:
   ```json5
   "dependencies": {
     "qx-hybrid": "file:./libs/qx-hybrid.har"
   }
   ```
3. 执行 `ohpm install`,然后正常 `import { QXWebView } from 'qx-hybrid'`。

**缺点:** 手动传文件、无版本管理、升级要重新发文件。正式协作建议用方式二。

---

## 3. 分发方式二:OHPM 私有源(推荐,对标 Maven 私服)

### 3.1 搭建私有 Registry(一次性,由你/运维做)
常见用 **JFrog Artifactory**(支持 OHPM 仓库类型),或华为提供的私仓方案。搭好后你会拿到:
- Registry 地址,如 `https://ohpm.your-company.com/repo`
- 发布用的账号 / token

### 3.2 生成发布密钥(一次性)
OHPM 发布用非对称密钥签名:
```bash
ohpm gen-keys                       # 生成公钥/私钥到 ~/.ohpm/
# 把生成的公钥登记到你的私有 Registry(按 Artifactory / 私仓文档操作)
```

### 3.3 配置 OHPM
```bash
ohpm config set registry https://ohpm.your-company.com/repo
ohpm config set publish_registry https://ohpm.your-company.com/repo
ohpm config set key_path ~/.ohpm/privateKey.pem
ohpm config set publish_id <你的发布ID>
# 若私仓用 token 鉴权:
ohpm config set auth_token <token>
```

### 3.4 发布
```bash
ohpm publish qx_hybrid/build/default/outputs/default/qx-hybrid.har
```
发布成功后,`qx-hybrid@0.1.10` 就在私有源可见了。

### 3.5 对方如何引入
1. 对方也把 registry 指向你的私有源(项目级 `.ohpmrc` 或全局):
   ```
   # 工程根目录 .ohpmrc
   registry=https://ohpm.your-company.com/repo
   ```
2. `oh-package.json5` 加依赖(带版本,支持 `^` / `~` 语义化):
   ```json5
   "dependencies": {
     "qx-hybrid": "^0.1.10"
   }
   ```
3. `ohpm install` → `import` 使用。

---

## 4. 分发方式三:OHPM 中心仓(公开)

对标 CocoaPods trunk / Maven Central。发布到 `https://ohpm.openharmony.cn`,需华为账号 + 审核。**仅对外开源 SDK 用**;内部给兄弟团队用方式二即可。

---

## 5. 集成方接入后要做的额外配置

不是所有能力都是"装上就好",以下需集成方在**自己入口模块**配置:

| 能力 | 集成方需做 |
|---|---|
| 定位 / 蓝牙 / 相机 | 在自己 `module.json5` 声明对应 `requestPermissions`(HAR 的权限声明不会自动合并到宿主,需宿主再声明一遍) |
| `openMap` 唤起第三方地图 | 声明 `querySchemes: ["petalmaps","amapuri","baidumap","qqmap"]` |
| 宿主 UI(返回/关闭/新开页/导航栏) | 实现 `QXHostDelegate` 传给 `QXWebView` |
| 扫码 / 选图 | 默认走 Scan Kit / PhotoPicker;如需自定义,注入 `scanHandler` |

> ⚠️ 关键差异:鸿蒙 HAR 的 `requestPermissions` **不会**像 Android aar 那样自动合并进宿主 App。集成方**必须**在自己的 entry 模块再声明一次权限,否则运行时申请会失败。这点要写进给对方的接入文档。

---

## 6. 版本与兼容

- 每次改动升 `qx_hybrid/oh-package.json5` 的 `version`,遵循 semver。
- 破坏性改动(桥协议字段变更)升主版本,并同步更新 `BRIDGE_PROTOCOL.md`,通知三端 + H5。
- 建议 CI:`assembleHar` → 自动化用例(hypium)→ `ohpm publish`。

---

## 7. 一页速查

| 目的 | 命令 |
|---|---|
| 打 HAR | `./hvigorw assembleHar --mode module -p module=qx_hybrid@default -p product=default` |
| 生成发布密钥 | `ohpm gen-keys` |
| 配置私有源 | `ohpm config set registry <url>` |
| 发布 | `ohpm publish path/to/qx-hybrid.har` |
| 对方安装 | `ohpm install`(依赖写在 oh-package.json5) |
