#!/usr/bin/env bash
set -euo pipefail

# ------------------------------------------------------------------------------
# 一時ディレクトリとテンプレートの自動生成（単一ファイル完結型）
# ------------------------------------------------------------------------------
# Mac (BSD) と Linux (GNU) の両方で安全に動作する一時ディレクトリを作成
TMP_TEMPLATE_DIR="$(mktemp -d "${TMPDIR:-/tmp}/genP.XXXXXX")"
trap 'rm -rf "$TMP_TEMPLATE_DIR"' EXIT

# 各テンプレートをヒアドキュメントで埋め込み定義
cat << 'EOF' > "${TMP_TEMPLATE_DIR}/p_fix.md"
# 指示
以下のコードやエラー情報を基に、原因の究明と具体的な修正コードを提案してください。
EOF

cat << 'EOF' > "${TMP_TEMPLATE_DIR}/p_summary.md"
# 指示
以下のプロジェクトファイル群を分析し、全体のアーキテクチャと各ファイルの役割を分かりやすく要約してください。
EOF

cat << 'EOF' > "${TMP_TEMPLATE_DIR}/p_review.md"
# 指示
以下のコードに対して、可読性、保守性、パフォーマンス、セキュリティ、およびベストプラクティスの観点からコードレビューを行ってください。
EOF

cat << 'EOF' > "${TMP_TEMPLATE_DIR}/p_git_push.md"
# 指示
特記事項なし
EOF

# テンプレートパスの定義
TEMPLATE_PROMPT_FIX="${TMP_TEMPLATE_DIR}/p_fix.md"
TEMPLATE_PROMPT_SUMMARY="${TMP_TEMPLATE_DIR}/p_summary.md"
TEMPLATE_PROMPT_REVIEW="${TMP_TEMPLATE_DIR}/p_review.md"
TEMPLATE_GIT_PUSH="${TMP_TEMPLATE_DIR}/p_git_push.md"

PROMPT_MODE=""
ACTION=""
PROMPT_TEMPLATE=""
PROJECT_TYPE=""
OUT=""

# ------------------------------------------------------------------------------
# ユーティリティ関数
# ------------------------------------------------------------------------------
print_header() {
  echo "========================================"
  echo " genP.sh (Self-contained)"
  echo " Project helper for prompt / git tasks"
  echo "========================================"
  echo
}

require_command() {
  local cmd="$1"
  if ! command -v "$cmd" >/dev/null 2>&1; then
    echo "エラー: 必要なコマンドが見つかりません: $cmd" >&2
    exit 1
  fi
}

ensure_git_repo() {
  if ! git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    echo "エラー: このディレクトリは Git リポジトリではありません。" >&2
    exit 1
  fi
}

# ------------------------------------------------------------------------------
# 対話UI関数
# ------------------------------------------------------------------------------
choose_action() {
  echo "行いたい処理を選択してください:"
  select action in \
    "Prompt生成" \
    "Git push" \
    "Git pull" \
    "Project summary" \
    "終了"; do
    case "$REPLY" in
      1) ACTION="prompt"; break ;;
      2) ACTION="git_push"; break ;;
      3) ACTION="git_pull"; break ;;
      4) ACTION="summary"; break ;;
      5) exit 0 ;;
      *) echo "無効な選択です。番号で選んでください。" ;;
    esac
  done
}

choose_prompt_mode() {
  echo
  echo "Prompt の種類を選択してください:"
  select prompt_mode in \
    "エラー修正依頼" \
    "構成要約" \
    "コードレビュー"; do
    case "$REPLY" in
      1) PROMPT_MODE="fix"; break ;;
      2) PROMPT_MODE="summary"; break ;;
      3) PROMPT_MODE="review"; break ;;
      *) echo "無効な選択です。番号で選んでください。" ;;
    esac
  done
}

set_template_by_action() {
  case "${ACTION}:${PROMPT_MODE}" in
    prompt:fix)
      PROMPT_TEMPLATE="$TEMPLATE_PROMPT_FIX"
      ;;
    prompt:summary)
      PROMPT_TEMPLATE="$TEMPLATE_PROMPT_SUMMARY"
      ;;
    prompt:review)
      PROMPT_TEMPLATE="$TEMPLATE_PROMPT_REVIEW"
      ;;
    git_push:*)
      PROMPT_TEMPLATE="$TEMPLATE_GIT_PUSH"
      ;;
    *)
      echo "テンプレートのマッピングが見つかりません: ACTION=${ACTION} PROMPT_MODE=${PROMPT_MODE}" >&2
      exit 1
      ;;
  esac
}

choose_project_type() {
  echo
  echo "プロジェクト種別を選択してください:"
  select project_type in \
    "Swift" \
    "Ruby" \
    "Python" \
    "Ren'Py" \
    "Web (JS/TS)" \
    "その他テキスト中心"; do
    case "$REPLY" in
      1) PROJECT_TYPE="swift"; break ;;
      2) PROJECT_TYPE="ruby"; break ;;
      3) PROJECT_TYPE="python"; break ;;
      4) PROJECT_TYPE="renpy"; break ;;
      5) PROJECT_TYPE="web"; break ;;
      6) PROJECT_TYPE="text"; break ;;
      *) echo "無効な選択です。番号で選んでください。" ;;
    esac
  done
}

choose_output_file() {
  echo
  read -r -p "出力ファイル名を入力してください（Enterでデフォルト）: " input_out
  if [[ -n "${input_out:-}" ]]; then
    OUT="$input_out"
  else
    case "${ACTION}:${PROMPT_MODE}" in
      prompt:fix) OUT="combined-prompt-fix.txt" ;;
      prompt:summary) OUT="combined-prompt-summary.txt" ;;
      prompt:review) OUT="combined-prompt-review.txt" ;;
      summary:*) OUT="combined-project-summary.txt" ;;
      *) OUT="combined-project-light.txt" ;;
    esac
  fi
}

# ------------------------------------------------------------------------------
# 検索ルール構築 (ripgrep)
# ------------------------------------------------------------------------------
add_common_excludes() {
  RG_ARGS+=(
    -g '!**/.git/**'
    -g '!**/node_modules/**'
    -g '!**/DerivedData/**'
    -g '!**/.build/**'
    -g '!**/build/**'
    -g '!**/dist/**'
    -g '!**/coverage/**'
    -g '!**/Pods/**'
    -g '!**/Carthage/**'
    -g '!**/SourcePackages/**'
    -g '!**/vendor/bundle/**'
    -g '!**/.venv/**'
    -g '!**/venv/**'
    -g '!**/__pycache__/**'
    -g '!**/.pytest_cache/**'
    -g '!**/.mypy_cache/**'
    -g '!**/.idea/**'
    -g '!**/.vscode/**'
    -g '!**/xcuserdata/**'
    -g '!**/*.xcuserstate'
    -g '!**/*.png'
    -g '!**/*.jpg'
    -g '!**/*.jpeg'
    -g '!**/*.gif'
    -g '!**/*.webp'
    -g '!**/*.pdf'
    -g '!**/*.zip'
    -g '!**/*.mp3'
    -g '!**/*.mp4'
    -g '!**/*.mov'
    -g '!**/*.rpyc'
    -g '!**/*.pyc'
  )
}

add_project_globs() {
  case "$PROJECT_TYPE" in
    swift)
      RG_ARGS+=(
        -g '*.swift' -g '*.plist' -g '*.entitlements'
        -g '*.md' -g '*.json' -g '*.yml' -g '*.yaml'
        -g 'Package.swift' -g 'Package.resolved'
      )
      ;;
    ruby)
      RG_ARGS+=(
        -g '*.rb' -g 'Gemfile' -g 'Gemfile.lock' -g '*.rake'
        -g '*.ru' -g '*.erb' -g '*.haml' -g '*.slim'
        -g '*.yml' -g '*.yaml' -g '*.json' -g '*.md'
      )
      ;;
    python)
      RG_ARGS+=(
        -g '*.py' -g 'requirements.txt' -g 'pyproject.toml'
        -g 'Pipfile' -g 'Pipfile.lock' -g 'poetry.lock'
        -g '*.toml' -g '*.ini' -g '*.cfg' -g '*.yml'
        -g '*.yaml' -g '*.json' -g '*.md'
      )
      ;;
    renpy)
      RG_ARGS+=(
        -g '*.rpy' -g '*.rpym' -g '*.py'
        -g '*.json' -g '*.md' -g '*.yml' -g '*.yaml'
      )
      ;;
    web)
      RG_ARGS+=(
        -g '*.js' -g '*.jsx' -g '*.ts' -g '*.tsx'
        -g '*.mjs' -g '*.cjs' -g '*.html' -g '*.css'
        -g '*.scss' -g '*.sass' -g '*.json' -g '*.md'
        -g '*.yml' -g '*.yaml' -g 'package.json'
        -g 'tsconfig.json' -g 'vite.config.*' -g 'next.config.*'
      )
      ;;
    text)
      RG_ARGS+=(
        -g '*.txt' -g '*.md' -g '*.json'
        -g '*.yml' -g '*.yaml' -g '*.toml' -g '*.ini'
      )
      ;;
    *)
      echo "未知のプロジェクト種別です: $PROJECT_TYPE" >&2
      exit 1
      ;;
  esac
}

build_rg_args() {
  RG_ARGS=()
  add_project_globs
  add_common_excludes
}

get_file_list() {
  if command -v rg >/dev/null 2>&1; then
    build_rg_args
    rg --files . "${RG_ARGS[@]}"
  else
    echo "注意: 'rg' (ripgrep) が見つからないため 'find' コマンドで代用します。" >&2
    find . -type f \
      ! -path '*/.*' \
      ! -path '*/node_modules/*' \
      ! -path '*/venv/*' \
      ! -path '*/.venv/*' \
      ! -path '*/DerivedData/*' \
      ! -path '*/build/*' \
      ! -path '*/dist/*'
  fi
}

# ------------------------------------------------------------------------------
# メイン処理フロー
# ------------------------------------------------------------------------------
collect_files() {
  {
    echo "===== PROJECT TYPE ====="
    echo "$PROJECT_TYPE"
    echo
    echo "===== PROJECT ROOT ====="
    pwd
    echo
  } > "$OUT"

  while IFS= read -r file; do
    printf '\n\n===== FILE: %s =====\n\n' "$file"
    cat "$file"
  done < <(get_file_list) >> "$OUT"
}

append_template() {
  printf '\n\n===== PROMPT TEMPLATE =====\n\n' >> "$OUT"
  
  if [[ -f "$PROMPT_TEMPLATE" ]]; then
    cat "$PROMPT_TEMPLATE" >> "$OUT"
  else
    echo "注意: テンプレートファイルが見つかりません ($PROMPT_TEMPLATE)" >&2
    echo "デフォルトの指示文を出力に追加します。" >&2
    case "$PROMPT_MODE" in
      fix)
        echo "上記コードに関するエラーを特定し、修正案と原因の解説を提示してください。" >> "$OUT"
        ;;
      summary)
        echo "上記プロジェクトの全体構成と各ファイルの役割を分かりやすく要約してください。" >> "$OUT"
        ;;
      review)
        echo "上記コードの可読性・パフォーマンス・安全性・ベストプラクティスの観点からコードレビューを行ってください。" >> "$OUT"
        ;;
      *)
        echo "上記コードを解析し、適切なフィードバックを提示してください。" >> "$OUT"
        ;;
    esac
  fi
}

generate_prompt() {
  choose_prompt_mode
  choose_project_type
  choose_output_file
  set_template_by_action

  collect_files
  append_template

  echo
  echo "出力完了: $OUT"
}

git_push_flow() {
  require_command git
  ensure_git_repo
  set_template_by_action

  echo
  echo "現在のディレクトリ: $(pwd)"
  echo
  git status --short

  if [[ -z "$(git status --porcelain)" ]]; then
    echo
    echo "変更がありません。Git push を中止します。"
    exit 0
  fi

  echo
  read -r -p "コミットメッセージを入力してください: " commit_msg
  if [[ -z "${commit_msg:-}" ]]; then
    echo "エラー: コミットメッセージが空です。" >&2
    exit 1
  fi

  git add .
  git commit -m "$commit_msg"
  git push

  echo
  echo "Git push が完了しました。"
}

git_pull_flow() {
  require_command git
  ensure_git_repo

  echo
  echo "現在のディレクトリ: $(pwd)"
  git pull

  echo
  echo "Git pull が完了しました。"
}

project_summary_flow() {
  choose_project_type
  choose_output_file

  {
    echo "===== PROJECT TYPE ====="
    echo "$PROJECT_TYPE"
    echo
    echo "===== PROJECT ROOT ====="
    pwd
    echo
    echo "===== FILE LIST ====="
    get_file_list
  } > "$OUT"

  echo
  echo "出力完了: $OUT"
}

main() {
  print_header
  choose_action

  case "$ACTION" in
    prompt)
      generate_prompt
      ;;
    git_push)
      git_push_flow
      ;;
    git_pull)
      git_pull_flow
      ;;
    summary)
      project_summary_flow
      ;;
    *)
      echo "不明なアクションです: $ACTION" >&2
      exit 1
      ;;
  esac
}

main "$@"
