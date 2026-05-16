# 推送到 GitHub — TODO

记下流程，等想公开时一气呵成。

## 前置确认

- [ ] LICENSE 里 `<your-name>` 已替换成真名/网名
- [ ] `pnpm typecheck` 全工程过
- [ ] `cd app && flutter analyze lib` 过
- [ ] 没有 `server/config.json` 出现在 `git status` 里（已在 `.gitignore`）
- [ ] 没有 `.idea/`、`.dart_tool/`、`node_modules/`、`build/` 进 commit

## 一键发布命令

```bash
cd ~/path/to/claude-companion

# 1. 替换 LICENSE 占位（如果还没改）
sed -i '' 's/<your-name>/airoucat/' LICENSE

# 2. 第一次 commit（git init 已做过的话跳到 git status）
git status                          # 看看要提交什么
git add .
git commit -m "chore: initial commit"

# 3. 去 GitHub 网页建仓库（关键：不要勾任何 Initialize options）
#    https://github.com/new
#    Repository name: claude-companion
#    Visibility:      Public
#    Description:     Mobile + web control surface for local Claude Code

# 4. 关联远程 + push
git remote add origin git@github.com:airoucat/claude-companion.git
git push -u origin main
```

> `git@github.com:...` 走 SSH，需要先配过 SSH key（见下）。
> 不想配 SSH 用 HTTPS：`https://github.com/airoucat/claude-companion.git`，第一次会让你输 GitHub Personal Access Token。

## SSH key（一次性配）

```bash
ssh-keygen -t ed25519 -C "asingle233@gmail.com"   # 一路回车
pbcopy < ~/.ssh/id_ed25519.pub                     # 公钥复制到剪贴板
# 浏览器开：https://github.com/settings/keys → New SSH key → 粘贴
# 验证：ssh -T git@github.com
```

## 推完之后的润色

- **Repo Settings → Topics**：加 `claude-code`、`flutter`、`fastify`、`mobile`、`developer-tools`、`anthropic`
- **About 框**：填一句话描述（复制 README 第一行）
- **Pin** 到 GitHub 主页（profile → Customize your pins）
- **Releases**：用 `git tag v0.1.0 && git push --tags`，然后在 GitHub web 上 New Release，上传 `latest.apk` 给手机直装党

## 后续维护

```bash
# 日常推送
git add .
git commit -m "feat: ..."
git push

# 打 release tag
git tag v0.2.0
git push --tags
# 然后 GitHub → Releases → Draft new release → 上传 APK + 写更新日志

# 跑通 CI（远期，先不做）
# .github/workflows/typecheck.yml 跑 pnpm typecheck 和 flutter analyze
```

## 别忘了

每次 GitHub push 前都瞄一眼 `git status`，看有没有意外文件被加入。最容易混进去的：
- `server/config.json`（已 ignore，但别在外面再生成同名文件）
- 临时调试的 `.env`、`*.log`
- `app/build/app/outputs/flutter-apk/releases/`（APK 历史，已 ignore，发版走 GitHub Releases 更合理）
