# android-signing-ci — CI 里的 Android release 签名（修 SHA 指纹漂移）

CI 每次构建出来的 APK **签名指纹都不一样**，用户装新版必须先卸载旧版（`INSTALL_FAILED_UPDATE_INCOMPATIBLE`）。

根因永远是同一句话：**构建时没拿到 release keystore，静默 fall back 到了 debug 签名**——而 debug keystore 是 runner 每次临时生成的。

本 ref 给一套与具体项目解耦的干净模板：本地生成 keystore → base64 灌进 secret → CI 重建 → 构建 → 验签。

## 加载时机

- CI 产物是 Android APK/AAB，需要**稳定签名**（覆盖安装、Play 上架、第三方 SDK 白名单校验 SHA）
- 用户反馈"每次更新都要卸载重装"、`INSTALL_FAILED_UPDATE_INCOMPATIBLE`
- `deploy.yml` 里已有 keystore 步骤但签名没生效
- 配合 [[references/deploy-template]] 或 [[references/deploy-template-no-registry]] 使用（它们负责服务端部署，本 ref 只负责 APK 签名段）

---

## 代价：为什么必须一次做对

签名指纹是 Android 包的**身份**，不是版本属性：

| 后果 | 说明 |
|---|---|
| 无法覆盖安装 | 系统拒绝用不同签名的包升级，必须卸载（**用户数据全丢**） |
| 无法上架 | Play / 各应用商店首次上传后签名锁定，改签名等于换应用 |
| 三方 SDK 失效 | 地图、支付、推送、OAuth 都按 `包名 + SHA-1/SHA-256` 白名单鉴权 |
| **不可逆** | keystore 丢失 = 永远无法再发布这个包名的更新（Play 有申诉通道，其它渠道没有） |

> ⚠ keystore 文件和密码务必**离线备份**（不是只存在 CI secret 里）。secret 可被覆盖，删掉就找不回来。

---

## 两层根因（按发生频率排）

### 第 1 层：secret 根本没配

`gh secret list` 里没有 keystore 相关条目。模板里常见的"没配就跳过"写法会让这一层**静默通过**：

```bash
if [ -z "$ANDROID_KEYSTORE_BASE64" ]; then
  echo "⚠ 未配置 keystore，跳过"
  exit 0        # ← CI 全绿，产物却是 debug 签名
fi
```

### 第 2 层：步骤顺序错（更隐蔽）

secret 配好了，但 **"Prepare keystore" 排在 "Build APK" 之后**。构建那一刻 `key.properties` 还不存在，Gradle 依旧 fall back debug 签名。

日志里两个步骤都是绿的 ✅，产物却是错的——这是最容易看走眼的一种。

**正确顺序（keystore 必须早于任何 build 命令）**：

```
Checkout → JDK → Android SDK → Flutter/构建工具 → 依赖安装
       → ★ Prepare keystore ★ → Build APK → 验签 → 分发
```

> 判据：`key.properties` 的写入步骤，必须出现在 workflow 文件里 build 步骤的**上方**。YAML 是顺序执行的，把它当成一条硬约束检查。

---

## 干净模板（四件套）

### ① 生成 keystore（本地，一次性）

```bash
keytool -genkeypair -v \
  -keystore release.keystore \
  -alias <KEY_ALIAS> \
  -keyalg RSA -keysize 2048 \
  -validity 10000 \
  -storepass '<STORE_PASSWORD>' \
  -keypass  '<KEY_PASSWORD>' \
  -dname "CN=<App>, OU=<Team>, O=<Org>, L=<City>, S=<State>, C=CN"
```

- `-validity 10000`（约 27 年）是 Play 的推荐下限，别用默认 90 天
- 生成后**离线备份** keystore + 两个密码
- 存放位置必须在 `.gitignore` 里（见 ④）

### ② 灌进 GitHub Secrets（4 个）

keystore 是二进制，要 base64 成单行文本再存：

```bash
# Linux
base64 -w0 release.keystore > ks.b64
# macOS（无 -w0）
base64 -i release.keystore | tr -d '\n' > ks.b64
# Windows PowerShell
[Convert]::ToBase64String([IO.File]::ReadAllBytes("release.keystore")) | Set-Content -NoNewline ks.b64
```

```bash
gh secret set ANDROID_KEYSTORE_BASE64   < ks.b64
gh secret set ANDROID_KEYSTORE_PASSWORD --body '<STORE_PASSWORD>'
gh secret set ANDROID_KEY_ALIAS         --body '<KEY_ALIAS>'
gh secret set ANDROID_KEY_PASSWORD      --body '<KEY_PASSWORD>'
rm ks.b64            # 用完即删
```

> ⚠ Windows 的 `certutil -encode` 会产出**带换行和 BEGIN/END 头**的 PEM 格式，直接灌进去解不出来。用上面的 PowerShell 写法。

### ③ `android/app/build.gradle.kts`（签名配置）

```kotlin
import java.util.Properties
import java.io.FileInputStream

// 读 android/key.properties（不入库）。有则真 release 签名，
// 没有则 fall back 到 debug —— 保证开发者本地无 keystore 也能 build。
val keystoreProperties = Properties().apply {
    val f = rootProject.file("key.properties")   // = <项目>/android/key.properties
    if (f.exists()) load(FileInputStream(f))
}

android {
    signingConfigs {
        create("release") {
            val path = keystoreProperties["storeFile"] as String?
            if (path != null) {
                storeFile     = file(path)
                storePassword = keystoreProperties["storePassword"] as String?
                keyAlias      = keystoreProperties["keyAlias"]      as String?
                keyPassword   = keystoreProperties["keyPassword"]   as String?
            }
        }
    }

    buildTypes {
        release {
            signingConfig = if (keystoreProperties["storeFile"] != null)
                signingConfigs.getByName("release")
            else
                signingConfigs.getByName("debug")   // ← 静默 fallback，靠 ⑤ 兜底
        }
    }
}
```

Groovy DSL（`build.gradle`）等价写法：

```groovy
def keystoreProperties = new Properties()
def f = rootProject.file("key.properties")
if (f.exists()) keystoreProperties.load(new FileInputStream(f))
```

### ④ `.gitignore`

```gitignore
# Android 签名 —— 绝不入库
**/android/key.properties
*.keystore
*.jks
```

### ⑤ workflow 步骤（放在 Build 之前）

```yaml
      # ============================================================
      # 准备 Android release keystore
      # ⚠ 必须在任何 build 步骤之前 —— 否则构建时 key.properties 还没写，
      #   Gradle fall back debug 签名 → SHA 每次漂移 → 用户必须卸载重装
      # ============================================================
      - name: Prepare Android keystore
        env:
          ANDROID_KEYSTORE_BASE64:   ${{ secrets.ANDROID_KEYSTORE_BASE64 }}
          ANDROID_KEYSTORE_PASSWORD: ${{ secrets.ANDROID_KEYSTORE_PASSWORD }}
          ANDROID_KEY_ALIAS:         ${{ secrets.ANDROID_KEY_ALIAS }}
          ANDROID_KEY_PASSWORD:      ${{ secrets.ANDROID_KEY_PASSWORD }}
        working-directory: <APP_DIR>/android      # ← 必须是 android/ 目录
        run: |
          set -euo pipefail
          if [ -z "${ANDROID_KEYSTORE_BASE64}" ]; then
            echo "::error::ANDROID_KEYSTORE_BASE64 未配置，release 构建会退化为 debug 签名"
            exit 1                                 # ← 严格模式：宁可红，不可静默出错包
          fi
          echo "${ANDROID_KEYSTORE_BASE64}" | base64 -d > "${RUNNER_TEMP}/release.keystore"
          cat > key.properties <<EOF
          storePassword=${ANDROID_KEYSTORE_PASSWORD}
          keyPassword=${ANDROID_KEY_PASSWORD}
          keyAlias=${ANDROID_KEY_ALIAS}
          storeFile=${RUNNER_TEMP}/release.keystore
          EOF
          echo "✓ keystore 就绪"

      - name: Build APK (release)
        working-directory: <APP_DIR>
        run: flutter build apk --release      # 或 ./gradlew assembleRelease
```

**`exit 1` vs `exit 0` 的取舍**：

| 策略 | 适合 | 风险 |
|---|---|---|
| 缺 secret 就 `exit 1`（上面） | 已经在正式分发 APK 的仓库 | fork / PR 跑 CI 会红 |
| 缺 secret 就 `exit 0` 跳过 | 开源仓库、fork 也要能跑 | **静默出 debug 包**，必须配 ⑥ 兜底 |

选 `exit 0` 的话，⑥ 不是可选项，是必需项。

### ⑥ 构建后验签（加固建议）

原始修复只调了顺序，没有断言。加这一步，才能让"签错了"变成 CI 红灯而不是用户投诉：

```yaml
      - name: Verify APK signature
        env:
          EXPECTED_SHA256: ${{ vars.RELEASE_CERT_SHA256 }}   # 仓库变量，非 secret
        working-directory: <APP_DIR>
        run: |
          set -euo pipefail
          APKSIGNER=$(ls "$ANDROID_HOME"/build-tools/*/apksigner | sort -V | tail -1)
          ACTUAL=$("$APKSIGNER" verify --print-certs build/app/outputs/flutter-apk/app-release.apk \
                   | grep -i 'SHA-256 digest' | head -1 | awk '{print $NF}')
          echo "actual = $ACTUAL"
          if [ -n "${EXPECTED_SHA256}" ] && [ "$ACTUAL" != "${EXPECTED_SHA256}" ]; then
            echo "::error::签名指纹不符，可能 fall back 到 debug 签名"
            exit 1
          fi
```

`RELEASE_CERT_SHA256` 从本地 keystore 取一次（注意去掉冒号、转小写以匹配 apksigner 输出格式）：

```bash
keytool -list -v -keystore release.keystore -alias <KEY_ALIAS> | grep 'SHA256:'
```

---

## 本地自查（不跑 CI 也能验）

```bash
# 看 APK 实际用了什么证书
$ANDROID_HOME/build-tools/<ver>/apksigner verify --print-certs app-release.apk

# debug 签名的特征：CN=Android Debug, O=Android, C=US
```

> `keytool -printcert -jarfile app.apk` 只读 v1(JAR) 签名。现代 Flutter/AGP 默认 v2+，v1 可能缺失导致该命令报"未找到签名"——**用 `apksigner`**，别用它误判。

---

## 坑清单

| 坑 | 表现 | 预防 |
|---|---|---|
| keystore 步骤排在 build 之后 | 两步都绿，产物 debug 签名 | workflow 里肉眼确认顺序；配 ⑥ 断言 |
| secret 从没配过 | 同上 | `gh secret list` 核对 4 个都在 |
| `working-directory` 写成项目根 | `key.properties` 落错目录，Gradle 读不到 | 必须是 `<APP_DIR>/android` |
| Windows `certutil -encode` 生成 base64 | `base64 -d` 解出损坏文件 | 用 PowerShell `[Convert]::ToBase64String` |
| base64 带换行 | 解码失败或截断 | Linux `-w0`；macOS `\| tr -d '\n'` |
| 密码含 `$` / 反引号 | heredoc 里被 shell 展开，密码写错 | 用引号包裹的 `<<'EOF'`，或密码只用字母数字 |
| keystore 提交进仓库 | 私钥泄露，需换包名重发 | `.gitignore` 三条（④）+ 提交前 `git status` 确认 |
| keystore 只存在 CI secret 里 | secret 误删 = 永久失去发版能力 | 离线备份 keystore 与密码 |
| 改 `-validity` 默认 90 天 | 证书过期后无法再签新版 | 用 10000 天 |

---

## 一次性迁移成本（从 debug 签名切到 release 签名）

切换那一刻，**旧包和新包签名不同**，存量用户仍需卸载一次：

1. 通知用户：这一版需要卸载重装，**之后不再需要**
2. 切换前提醒用户导出/备份 app 内数据（卸载会清空）
3. 切换后所有版本共用同一签名，覆盖安装恢复正常

越早切成本越低——用户基数每天都在涨。

---

## 关联引用

- [[references/deploy-template]] — GHCR 派部署模板，APK 段接本 ref
- [[references/deploy-template-no-registry]] — 自包含部署模板，同上
- [[references/gh-troubleshoot]] — 构建失败时抓 raw log / 诊断 run
