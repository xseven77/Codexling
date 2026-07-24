#!/usr/bin/env bash
set -euo pipefail

APP_NAME="Codexling"
BINARY_NAME="Codexling"
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${ROOT_DIR}/../.." && pwd)"
PLIST_PATH="${ROOT_DIR}/Resources/Info.plist"
DIST_DIR="${ROOT_DIR}/dist"
CURRENT_BRANCH="$(git -C "${REPO_ROOT}" branch --show-current)"
ORIGINAL_VERSION=""
ORIGINAL_BUILD=""
ROLLBACK_VERSION_ON_FAILURE="false"

cd "${ROOT_DIR}"

info() {
  printf "\033[1;34m==>\033[0m %s\n" "$*"
}

warn() {
  printf "\033[1;33m!!\033[0m %s\n" "$*"
}

fail() {
  printf "\033[1;31merror:\033[0m %s\n" "$*" >&2
  exit 1
}

restore_version_on_failure() {
  local exit_status="$?"
  trap - EXIT

  if [[ "${exit_status}" -ne 0 && "${ROLLBACK_VERSION_ON_FAILURE}" == "true" ]]; then
    warn "发布在提交版本号之前失败，恢复版本 ${ORIGINAL_VERSION} (${ORIGINAL_BUILD})"
    /usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString ${ORIGINAL_VERSION}" "${PLIST_PATH}" || true
    /usr/libexec/PlistBuddy -c "Set :CFBundleVersion ${ORIGINAL_BUILD}" "${PLIST_PATH}" || true
  fi

  exit "${exit_status}"
}

trap restore_version_on_failure EXIT

confirm() {
  local prompt="$1"
  local answer
  read -r -p "${prompt} [y/N] " answer
  [[ "${answer}" == "y" || "${answer}" == "Y" ]]
}

require_command() {
  local command_name="$1"
  local install_hint="$2"

  if ! command -v "${command_name}" >/dev/null 2>&1; then
    fail "缺少命令：${command_name}。${install_hint}"
  fi
}

ensure_github_auth() {
  require_command gh "请先安装 GitHub CLI：brew install gh"

  info "检查 GitHub CLI 登录状态"
  if gh auth status >/dev/null 2>&1; then
    gh auth status
    return
  fi

  warn "GitHub CLI 尚未登录，将启动交互式网页登录授权"
  gh auth login --hostname github.com --git-protocol ssh --skip-ssh-key --web

  if ! gh auth status >/dev/null 2>&1; then
    fail "GitHub CLI 登录失败，请重新运行脚本并完成授权。"
  fi
}

require_clean_worktree() {
  local status
  status="$(git -C "${REPO_ROOT}" status --porcelain)"

  if [[ -n "${status}" ]]; then
    printf "%s\n" "${status}"
    fail "工作区不干净。请先提交、stash 或清理改动后再发布。"
  fi
}

require_branch() {
  if [[ -z "${CURRENT_BRANCH}" ]]; then
    fail "当前处于 detached HEAD，无法自动推送分支。请切回发布分支后再运行。"
  fi
}

validate_version() {
  local version="$1"
  [[ "${version}" =~ ^[0-9]+(\.[0-9]+){1,2}$ ]]
}

validate_build_number() {
  local build_number="$1"
  [[ "${build_number}" =~ ^[0-9]+$ ]]
}

bump_version() {
  local version="$1"
  local bump_type="$2"
  local major minor patch

  IFS='.' read -r major minor patch <<< "${version}"
  patch="${patch:-0}"

  case "${bump_type}" in
    patch)
      patch="$((patch + 1))"
      ;;
    minor)
      minor="$((minor + 1))"
      patch="0"
      ;;
    major)
      major="$((major + 1))"
      minor="0"
      patch="0"
      ;;
    *)
      fail "未知版本更新类型：${bump_type}"
      ;;
  esac

  printf "%s.%s.%s" "${major}" "${minor}" "${patch}"
}

read_release_inputs() {
  local current_version current_build default_build version_choice
  current_version="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "${PLIST_PATH}")"
  current_build="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "${PLIST_PATH}")"
  ORIGINAL_VERSION="${current_version}"
  ORIGINAL_BUILD="${current_build}"

  if [[ "${current_build}" =~ ^[0-9]+$ ]]; then
    default_build="$((current_build + 1))"
  else
    default_build="1"
  fi

  printf "\n当前版本：%s (%s)\n" "${current_version}" "${current_build}"
  printf "请选择版本更新方式：\n"
  printf "  1) 修复更新：%s -> %s\n" "${current_version}" "$(bump_version "${current_version}" patch)"
  printf "  2) 小版本更新：%s -> %s\n" "${current_version}" "$(bump_version "${current_version}" minor)"
  printf "  3) 大版本更新：%s -> %s\n" "${current_version}" "$(bump_version "${current_version}" major)"
  printf "  4) 手动输入版本号\n"

  read -r -p "请输入选项 [1-4]（默认 1）： " version_choice
  version_choice="${version_choice:-1}"

  case "${version_choice}" in
    1)
      RELEASE_VERSION="$(bump_version "${current_version}" patch)"
      ;;
    2)
      RELEASE_VERSION="$(bump_version "${current_version}" minor)"
      ;;
    3)
      RELEASE_VERSION="$(bump_version "${current_version}" major)"
      ;;
    4)
      read -r -p "请输入本次发布版本号，例如 0.1.1： " RELEASE_VERSION
      ;;
    *)
      fail "无效选项：${version_choice}"
      ;;
  esac

  if ! validate_version "${RELEASE_VERSION}"; then
    fail "版本号格式不正确：${RELEASE_VERSION}。请使用类似 0.1.1 或 1.0.0 的格式。"
  fi

  info "本次发布版本：${RELEASE_VERSION}"

  read -r -p "请输入 build number（留空使用 ${default_build}）： " RELEASE_BUILD
  RELEASE_BUILD="${RELEASE_BUILD:-${default_build}}"

  if ! validate_build_number "${RELEASE_BUILD}"; then
    fail "build number 必须是整数：${RELEASE_BUILD}"
  fi

  RELEASE_TAG="v${RELEASE_VERSION}"
  ZIP_PATH="${DIST_DIR}/${APP_NAME}-${RELEASE_VERSION}.zip"
  DMG_PATH="${DIST_DIR}/${APP_NAME}-${RELEASE_VERSION}.dmg"
}

update_plist_version() {
  info "写入版本号 ${RELEASE_VERSION} (${RELEASE_BUILD})"
  ROLLBACK_VERSION_ON_FAILURE="true"
  /usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString ${RELEASE_VERSION}" "${PLIST_PATH}"
  /usr/libexec/PlistBuddy -c "Set :CFBundleVersion ${RELEASE_BUILD}" "${PLIST_PATH}"
}

build_release_artifacts() {
  info "开始打包。发布前会重新生成 .app、.zip 和 .dmg"
  "${ROOT_DIR}/package_app.sh"

  [[ -f "${DMG_PATH}" ]] || fail "DMG 未生成：${DMG_PATH}"
  [[ -f "${ZIP_PATH}" ]] || fail "ZIP 未生成：${ZIP_PATH}"
}

release_dmg_image_if_busy() {
  hdiutil detach "${DMG_PATH}" >/dev/null 2>&1 || true
}

verify_dmg() {
  local mount_output mount_point attempt

  info "挂载验证 DMG 内容"
  release_dmg_image_if_busy

  mount_output=""
  for attempt in 1 2 3 4 5 6; do
    if mount_output="$(hdiutil attach "${DMG_PATH}" -nobrowse -readonly 2>&1)"; then
      break
    fi
    if [[ "${attempt}" -eq 6 ]]; then
      printf "%s\n" "${mount_output}"
      fail "无法挂载 DMG：${DMG_PATH}。若仍失败，可先执行：hdiutil detach \"${DMG_PATH}\""
    fi
    release_dmg_image_if_busy
    sleep 1
  done

  mount_point="$(printf "%s\n" "${mount_output}" | awk -F'\t' '/\/Volumes\// {print $NF; exit}')"

  if [[ -z "${mount_point}" || ! -d "${mount_point}" ]]; then
    printf "%s\n" "${mount_output}"
    fail "无法识别 DMG 挂载点。"
  fi

  if [[ ! -d "${mount_point}/${APP_NAME}.app" ]]; then
    hdiutil detach "${mount_point}" >/dev/null || true
    fail "DMG 中缺少 ${APP_NAME}.app"
  fi

  if [[ ! -L "${mount_point}/Applications" ]]; then
    hdiutil detach "${mount_point}" >/dev/null || true
    fail "DMG 中缺少 Applications 快捷方式"
  fi

  hdiutil detach "${mount_point}" >/dev/null
  info "DMG 验证通过"
}

commit_version_if_needed() {
  if git -C "${REPO_ROOT}" diff --quiet -- app/Codexling/Resources/Info.plist; then
    info "版本文件没有变化，无需提交版本号"
    return
  fi

  info "提交版本号变更"
  git -C "${REPO_ROOT}" add app/Codexling/Resources/Info.plist
  git -C "${REPO_ROOT}" commit -m "Release ${RELEASE_VERSION}"
}

push_branch_and_tag() {
  info "推送 ${CURRENT_BRANCH}"
  git -C "${REPO_ROOT}" push origin "${CURRENT_BRANCH}"
  git -C "${REPO_ROOT}" fetch --tags origin

  if git -C "${REPO_ROOT}" rev-parse "${RELEASE_TAG}" >/dev/null 2>&1; then
    local tag_commit head_commit
    tag_commit="$(git -C "${REPO_ROOT}" rev-list -n 1 "${RELEASE_TAG}")"
    head_commit="$(git -C "${REPO_ROOT}" rev-parse HEAD)"

    if [[ "${tag_commit}" != "${head_commit}" ]]; then
      fail "本地 tag ${RELEASE_TAG} 已存在，但不指向当前 HEAD。请手动检查后再发布。"
    fi

    warn "本地 tag ${RELEASE_TAG} 已存在，跳过创建。"
  else
    info "创建 tag ${RELEASE_TAG}"
    git -C "${REPO_ROOT}" tag -a "${RELEASE_TAG}" -m "${APP_NAME} ${RELEASE_VERSION}"
  fi

  info "推送 tag ${RELEASE_TAG}"
  git -C "${REPO_ROOT}" push origin "${RELEASE_TAG}"
}

release_notes_file() {
  local notes_path="${DIST_DIR}/release-notes-${RELEASE_VERSION}.md"

  cat > "${notes_path}" <<EOF
## ${APP_NAME} ${RELEASE_VERSION}

### 下载

- \`${APP_NAME}-${RELEASE_VERSION}.dmg\`：推荐安装包
- \`${APP_NAME}-${RELEASE_VERSION}.zip\`：备用压缩包

> 当前构建使用 ad-hoc 签名，未做 Apple notarization。
EOF

  printf "%s" "${notes_path}"
}

publish_github_release() {
  local repo notes_path release_exists
  repo="$(gh repo view --json nameWithOwner --jq .nameWithOwner)"
  notes_path="$(release_notes_file)"

  info "发布到 GitHub Release：${repo} ${RELEASE_TAG}"
  if gh release view "${RELEASE_TAG}" --repo "${repo}" >/dev/null 2>&1; then
    release_exists="yes"
  else
    release_exists="no"
  fi

  if [[ "${release_exists}" == "yes" ]]; then
    warn "Release ${RELEASE_TAG} 已存在"
    if ! confirm "是否覆盖上传 DMG/ZIP，并更新 release notes？"; then
      fail "已取消发布。"
    fi

    gh release edit "${RELEASE_TAG}" \
      --repo "${repo}" \
      --title "${APP_NAME} ${RELEASE_VERSION}" \
      --notes-file "${notes_path}"
    gh release upload "${RELEASE_TAG}" "${DMG_PATH}" "${ZIP_PATH}" --repo "${repo}" --clobber
  else
    gh release create "${RELEASE_TAG}" "${DMG_PATH}" "${ZIP_PATH}" \
      --repo "${repo}" \
      --title "${APP_NAME} ${RELEASE_VERSION}" \
      --notes-file "${notes_path}"
  fi

  gh release view "${RELEASE_TAG}" --repo "${repo}" --web
}

main() {
  require_command swift "请先安装 Xcode Command Line Tools。"
  require_command hdiutil "hdiutil 是 macOS 自带命令，请在 macOS 上运行。"
  require_command codesign "codesign 是 macOS 自带命令，请在 macOS 上运行。"

  ensure_github_auth
  require_branch
  require_clean_worktree
  read_release_inputs
  update_plist_version
  build_release_artifacts
  verify_dmg
  commit_version_if_needed
  ROLLBACK_VERSION_ON_FAILURE="false"
  push_branch_and_tag
  publish_github_release

  info "发布完成：${RELEASE_TAG}"
}

main "$@"
