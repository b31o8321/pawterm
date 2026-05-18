# Claude Companion (PawTerm) 项目规范

## 构建 & 发布流程

**必须使用已写好的脚本，禁止手动执行 flutter build / gh release / npm publish。**

### App 打包（Android APK）

```bash
bash app/scripts/build-apk.sh
```

- 交互式选择版本 bump 策略（same / build / patch / minor / major）
- 自动更新 `app/pubspec.yaml` 版本号
- 输出到 `app/build/app/outputs/flutter-apk/releases/<version>/`

### App 打包（iOS IPA）

```bash
bash app/scripts/build-ipa.sh
```

### GitHub Release（App）

```bash
bash app/scripts/release.sh
```

- 读取当前 pubspec 版本，自动收集 APK / IPA 产物
- 调用 `gh release create`，title 中附带 server 版本号
- **必须先跑完打包脚本，再跑 release 脚本**

### 服务端 npm 发布

```bash
cd server
npm version patch   # 或 minor / major
npm run build
npm publish
```

发布后记得 commit `server/package.json` 的版本变更。

---

## 目录结构关键路径

- `app/`：Flutter 客户端
- `server/`：Node.js 服务端（npm 包 `pawterm-server`）
- `packages/shared/`：客户端和服务端共享的 TypeScript 类型
- `web/`：Web 前端

## 服务端注意事项

- 端口 `8766` 是给未重打包 app 使用的稳定测试服，**不要随意重启**
- `server/dist/` 在 `.gitignore` 中，不入 git；发布 npm 前需先 `npm run build`
