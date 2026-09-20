#!/usr/bin/env bash
set -Eeuo pipefail

PROGRAM_NAME="genp"
VERSION="2.0.0"

# ============================================================================== 
# グローバル変数
# ============================================================================== 
PROJECT_TYPE=""
PROMPT_MODE=""
OUT_FILE="ai_prompt_context.txt"
COPIED=false
RG_ARGS=()
FILE_LIST=()

# ============================================================================== 
# エラー処理
# ============================================================================== 
on_error() {
  local status=$?
  local line_no=$1
  local command=$2

  printf '%s: エラー（終了コード: %d）\n' "$PROGRAM_NAME" "$status" >&2
  printf '  行: %s\n' "$line_no" >&2
  printf '  コマンド: %s\n' "$command" >&2
  exit "$status"
}

on_interrupt() {
  printf '\n%s: 中断しました。\n' "$PROGRAM_NAME" >&2
  exit 130
}

trap 'on_error "$LINENO" "$BASH_COMMAND"' ERR
trap on_interrupt INT TERM

# ============================================================================== 
# コマンドライン引数
# ============================================================================== 
usage() {
  cat <<EOF
使い方: ${PROGRAM_NAME} [-v]

オプション:
  -v    バージョン情報を表示
EOF
}

# ------------------------------------------------------------------------------
# 対話 UI 関数
# ------------------------------------------------------------------------------
choose_action() {
  echo "行いたい処理を選択してください:"
  select action in \
    "Prompt 生成" \
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
parse_args() {
  while (($# > 0)); do
    case "$1" in
      -v)
        printf '%s %s\n' "$PROGRAM_NAME" "$VERSION"
        exit 0
        ;;
      --)
        shift
        break
        ;;
      -*)
        printf '%s: 不明なオプション: %s\n' "$PROGRAM_NAME" "$1" >&2
        usage >&2
        exit 2
        ;;
      *)
        printf '%s: このコマンドは位置引数を受け付けません: %s\n' "$PROGRAM_NAME" "$1" >&2
        usage >&2
        exit 2
        ;;
    esac
    shift
  done
}

# ============================================================================== 
# プロンプトテンプレートの内部定義
# ============================================================================== 
get_prompt_instruction() {
  local mode="$1"

  case "$mode" in
    fix)
      echo "以下のコードとコンテキスト情報を基に、発生しているエラーや不具合の原因を究明し、具体的な修正コードを提案してください。"
      ;;
    review)
      echo "以下のコードに対して、可読性、保守性、パフォーマンス、セキュリティ、およびベストプラクティスの観点から厳密なコードレビューを行ってください。"
      ;;
    summary)
      echo "以下のプロジェクトファイル群を分析し、全体のアーキテクチャ、技術スタック、および各ファイルの役割を分かりやすく要約してください。"
      ;;
    generic)
      echo "以下はプロジェクトのファイル群とディレクトリ構成です。まずプロジェクト種別、技術スタック、主要な構成要素を推定してください。不明な点は推測であることを明示し、確認すべきファイルや質問を挙げてください。そのうえで、次の開発・分析に役立つ実践的なフィードバックを提示してください。"
      ;;
    *)
      echo "テンプレートのマッピングが見つかりません：ACTION=${ACTION} PROMPT_MODE=${PROMPT_MODE}" >&2
      exit 1
      echo "上記コードを解析し、適切なフィードバックを提示してください。"
      ;;
  esac
}

# ============================================================================== 
# ユーティリティ関数
# ============================================================================== 
print_header() {
  echo "================================================="
  echo " 🤖 AI Context Generator (Self-contained)"
  echo "================================================="
  echo
}

command_exists() {
  command -v "$1" >/dev/null 2>&1
}

# 簡易ディレクトリツリー生成関数
# 出力ファイル自身と大きな依存ディレクトリは表示しない。
generate_tree() {
  if command_exists tree; then
    tree -I ".git|node_modules|DerivedData|.build|build|dist|coverage|Pods|Carthage|vendor|.venv|venv|__pycache__|.idea|.vscode|$OUT_FILE" --dirsfirst
  else
    find . \
      -path './.git' -prune -o \
      -path './node_modules' -prune -o \
      -path './DerivedData' -prune -o \
      -path './.build' -prune -o \
      -path './build' -prune -o \
      -path './dist' -prune -o \
      -path './coverage' -prune -o \
      -path './Pods' -prune -o \
      -path './Carthage' -prune -o \
      -path './.venv' -prune -o \
      -path './venv' -prune -o \
      -path './__pycache__' -prune -o \
      -path './.idea' -prune -o \
      -path './.vscode' -prune -o \
      ! -name "$OUT_FILE" -print | sed -e 's;[^/]*/;|____;g;s;____|; |;g'
  fi
}

# ============================================================================== 
# プロジェクト種別の自動判定
# ============================================================================== 
detect_project_type() {
  local detected=()

  # Ren'Py: 標準の game/ ディレクトリ配下に .rpy がある。
  if [[ -d "game" ]] && [[ -n "$(find "game" -type f -name '*.rpy' -print -quit)" ]]; then
    detected+=("renpy")
  fi

  # WordPress: ルートの設定ファイルと標準ディレクトリを組み合わせて判定する。
  if [[ -f "wp-config.php" ]] && [[ -d "wp-content" ]] \
    && { [[ -d "wp-admin" ]] || [[ -d "wp-includes" ]]; }; then
    detected+=("wordpress")
  fi

  # Swift / Xcode / Swift Package Manager
  if [[ -f "Package.swift" ]] \
    || [[ -n "$(find . -maxdepth 2 -type d \( -name '*.xcodeproj' -o -name '*.xcworkspace' \) -print -quit)" ]]; then
    detected+=("swift")
  fi

  # Node.js 系のWebフロントエンド
  if [[ -f "package.json" ]]; then
    detected+=("web_frontend")
  fi

  case "${#detected[@]}" in
    0)
      PROJECT_TYPE="generic"
      ;;
    1)
      PROJECT_TYPE="${detected[0]}"
      ;;
    *)
      PROJECT_TYPE="generic"
      ;;
  esac
}

print_detected_project_type() {
  case "$PROJECT_TYPE" in
    renpy)
      echo "🎮 Ren'Py プロジェクトを検出しました。"
      ;;
    wordpress)
      echo "🌐 WordPress プロジェクトを検出しました。"
      ;;
    swift)
      echo "🍎 Swift / Xcode プロジェクトを検出しました。"
      ;;
    web_frontend)
      echo "🖥️ Webフロントエンドプロジェクトを検出しました。"
      ;;
    generic)
      echo "📦 プロジェクト種別を一意に特定できませんでした。"
      echo "   汎用プロジェクト分析モードで生成します。"
      ;;
  esac
}

choose_project_type() {
  detect_project_type
  print_detected_project_type
}

# ============================================================================== 
# 対話UI関数
# ============================================================================== 
choose_prompt_mode() {
  echo

  if [[ "$PROJECT_TYPE" == "generic" ]]; then
    PROMPT_MODE="generic"
    echo "🎯 汎用プロジェクト分析モードを自動選択しました。"
    return
  fi

  echo "🎯 AIへの主な依頼内容（モード）を選択してください:"
  select pm in \
    "エラー・バグの修正依頼" \
    "コードレビュー依頼" \
    "プロジェクト構成の要約"; do
    case "$REPLY" in
  echo "プロジェクト種別を選択してください:"
  select project_type in \
    "Swift" \
    "Ruby" \
    "Python" \
    "Ren'Py" \
    "Web (JS/TS)" \
    "KMP (Kotlin Multiplatform)" \
    "その他テキスト中心"; do
    case "$REPLY" in
      1) PROJECT_TYPE="swift"; break ;;
      2) PROJECT_TYPE="ruby"; break ;;
      3) PROJECT_TYPE="python"; break ;;
      4) PROJECT_TYPE="renpy"; break ;;
      5) PROJECT_TYPE="web"; break ;;
      6) PROJECT_TYPE="kmp"; break ;;
      7) PROJECT_TYPE="text"; break ;;

  if [[ "$PROJECT_TYPE" == "generic" ]]; then
    PROMPT_MODE="generic"
    echo "🎯 汎用プロジェクト分析モードを自動選択しました。"
    return
  fi

  echo "🎯 AIへの主な依頼内容（モード）を選択してください:"
  select pm in \
    "エラー・バグの修正依頼" \
    "コードレビュー依頼" \
    "プロジェクト構成の要約"; do
    case "$REPLY" in
      1) PROMPT_MODE="fix"; break ;;
      2) PROMPT_MODE="review"; break ;;
      3) PROMPT_MODE="summary"; break ;;
      *) echo "無効な選択です。番号で選んでください。" ;;
    esac
  done
}

# ============================================================================== 
# 検索ルール構築（ripgrep / find）
# ============================================================================== 
add_common_excludes() {
  RG_ARGS+=(
choose_output_file() {
  echo
  read -r -p "出力ファイル名を入力してください（Enter でデフォルト）: " input_out
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
    -g '!**/*.class'
    -g '!**/*.jar'
    -g '!**/*.so'
    -g '!**/*.dylib'
    -g '!**/*.dll'
# ============================================================================== 
# 検索ルール構築（ripgrep / find）
# ============================================================================== 
add_common_excludes() {
  RG_ARGS+=(
    -g '!**/.git/**' -g '!**/node_modules/**' -g '!**/DerivedData/**'
    -g '!**/.build/**' -g '!**/build/**' -g '!**/dist/**' -g '!**/coverage/**'
    -g '!**/Pods/**' -g '!**/Carthage/**' -g '!**/vendor/bundle/**'
    -g '!**/.venv/**' -g '!**/venv/**' -g '!**/__pycache__/**'
    -g '!**/.idea/**' -g '!**/.vscode/**' -g '!**/xcuserdata/**' -g '!**/*.xcuserstate'
    -g '!**/*.png' -g '!**/*.jpg' -g '!**/*.jpeg' -g '!**/*.gif' -g '!**/*.webp'
    -g '!**/*.pdf' -g '!**/*.zip' -g '!**/*.tar' -g '!**/*.gz' -g '!**/*.mp3' -g '!**/*.mp4'
    -g "!$OUT_FILE" -g "!**/$OUT_FILE"
    -g '!**/.env' -g '!**/.env.*' -g '!**/*.pem' -g '!**/*.key'
    -g '!**/credentials*.json' -g '!**/*secret*' -g '!**/*token*'
    -g '!wp-config.php'
  )
}

add_project_globs() {
  case "$PROJECT_TYPE" in
    swift)
      RG_ARGS+=( -g '*.swift' -g '*.plist' -g '*.md' -g '*.json' -g '*.yml' -g '*.yaml' -g 'Package.swift' )
      ;;
    renpy)
      RG_ARGS+=( -g '*.rpy' -g '*.rpyi' -g '*.toml' -g '*.json' -g '*.yml' -g '*.yaml' -g '*.md' )
      ;;
    wordpress)
      RG_ARGS+=( -g '*.php' -g '*.html' -g '*.css' -g '*.js' -g '*.json' -g '*.yml' -g '*.yaml' -g '*.md' )
      ;;
    kmp)
      RG_ARGS+=(
        # Kotlin ソース
        -g '*.kt' -g '*.kts'
        # Gradle 設定
        -g 'build.gradle.kts' -g 'settings.gradle.kts'
        -g 'build.gradle' -g 'settings.gradle'
        -g 'gradle.properties' -g 'local.properties'
        # Gradle wrapper
        -g 'gradlew' -g 'gradlew.bat'
        -g 'gradle/wrapper/gradle-wrapper.properties'
        # KMP 固有
        -g 'composeResources/**/*'
        # 設定・ドキュメント
        -g '*.md' -g '*.json' -g '*.yml' -g '*.yaml'
        -g '*.toml' -g '*.properties'
        # ProGuard/R8
        -g 'proguard-rules.pro'
        # Android 固有（共有モジュールが参照する可能性）
        -g 'AndroidManifest.xml'
        # iOS 連携（KMP から Swift を呼ぶ場合など）
        -g '*.swift' -g '*.h'
      )
      ;;
    web_frontend)
      RG_ARGS+=( -g '*.js' -g '*.ts' -g '*.tsx' -g '*.jsx' -g '*.css' -g '*.scss' -g '*.html' -g '*.json' -g '*.md' )
      ;;
    *)
      echo "未知のプロジェクト種別です：$PROJECT_TYPE" >&2
      exit 1
    web_frontend)
      RG_ARGS+=( -g '*.js' -g '*.ts' -g '*.tsx' -g '*.jsx' -g '*.css' -g '*.scss' -g '*.html' -g '*.json' -g '*.md' )
      ;;
    generic)
      # 任意プロジェクト用。コード、設定、ドキュメントを中心に収集する。
      RG_ARGS+=(
        -g '*.sh' -g '*.bash' -g '*.zsh' -g '*.py' -g '*.rb' -g '*.php'
        -g '*.js' -g '*.ts' -g '*.tsx' -g '*.jsx' -g '*.mjs' -g '*.cjs'
        -g '*.c' -g '*.h' -g '*.cpp' -g '*.hpp' -g '*.rs' -g '*.go'
        -g '*.java' -g '*.kt' -g '*.kts' -g '*.swift' -g '*.rpy'
        -g '*.html' -g '*.css' -g '*.scss' -g '*.sql'
        -g '*.json' -g '*.toml' -g '*.yml' -g '*.yaml' -g '*.xml' -g '*.plist'
        -g '*.md' -g '*.txt' -g 'Makefile' -g 'Dockerfile' -g 'Gemfile'
        -g 'package.json' -g 'Package.swift' -g 'pyproject.toml' -g 'Cargo.toml'
      )
      ;;
  esac
}

get_file_list() {
  if command_exists rg; then
    RG_ARGS=()
    add_project_globs
    add_common_excludes
    rg --files "${RG_ARGS[@]}" .
  else
    # ripgrep がない場合の簡易フォールバック。
    find . -type f \
      ! -path './.git/*' \
      ! -path './node_modules/*' \
      ! -path './DerivedData/*' \
      ! -path './build/*' \
      ! -path './dist/*' \
      ! -path './.venv/*' \
      ! -path './venv/*' \
      ! -name "$OUT_FILE" \
      ! -name '.env' \
      ! -name '.env.*' \
      ! -name 'wp-config.php'
  fi
}

    echo "注意：'rg' (ripgrep) が見つからないため 'find' コマンドで代用します。" >&2
    find . -type f \
      ! -path '*/.*' \
      ! -path '*/node_modules/*' \
      ! -path '*/venv/*' \
      ! -path '*/.venv/*' \
      ! -path '*/DerivedData/*' \
      ! -path '*/build/*' \
      ! -path '*/dist/*' \
      ! -path '*/.build/*' \
      ! -path '*/.gradle/*' \
      ! -name '*.class' \
      ! -name '*.jar' \
      ! -name '*.so' \
      ! -name '*.dylib' \
      ! -name '*.dll'
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
    echo "注意：テンプレートファイルが見つかりません ($PROMPT_TEMPLATE)" >&2
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
  echo "出力完了：$OUT"
}

git_push_flow() {
  require_command git
  ensure_git_repo
  set_template_by_action

  echo
  echo "現在のディレクトリ：$(pwd)"
  echo
  git status --short

  if [[ -z "$(git status --porcelain)" ]]; then
    echo
    echo "変更がありません。Git push を中止します。"
    exit 0
  fi

  echo
  read -r -p "コミットメッセージを入力してください：" commit_msg
  if [[ -z "${commit_msg:-}" ]]; then
    echo "エラー：コミットメッセージが空です。" >&2
    # ripgrep がない場合の簡易フォールバック。
    find . -type f \
      ! -path './.git/*' \
      ! -path './node_modules/*' \
      ! -path './DerivedData/*' \
      ! -path './build/*' \
      ! -path './dist/*' \
      ! -path './.venv/*' \
      ! -path './venv/*' \
      ! -name "$OUT_FILE" \
      ! -name '.env' \
      ! -name '.env.*' \
      ! -name 'wp-config.php'
  fi
}

# ============================================================================== 
# 実行場所・対象ファイルの検証
# ============================================================================== 
validate_project_root() {
  # 明らかな誤実行を防ぐ。
  if [[ "$PWD" == "/" || "$PWD" == "$HOME" ]]; then
    printf '%s: エラー: プロジェクトのルートディレクトリで実行してください。\n' \
      "$PROGRAM_NAME" >&2
    printf '現在地: %s\n' "$PWD" >&2
    exit 1
  fi

  FILE_LIST=()

  while IFS= read -r file; do
    [[ -n "$file" ]] && FILE_LIST+=("$file")
  done < <(get_file_list)

  if ((${#FILE_LIST[@]} == 0)); then
    printf '%s: エラー: 読み込み対象のプロジェクトファイルが見つかりません。\n' \
      "$PROGRAM_NAME" >&2
    printf '現在地: %s\n' "$PWD" >&2
    printf 'プロジェクトのルートディレクトリへ移動してから実行してください。\n' >&2
    exit 1
  fi

  if [[ ! -d '.git' ]]; then
    printf '%s: 警告: .git ディレクトリがありません。Git管理外のプロジェクトとして続行します。\n' \
      "$PROGRAM_NAME" >&2
  fi
}

# ============================================================================== 
# 出力生成
# ============================================================================== 
generate_output() {
  local file

  echo
  echo "現在のディレクトリ：$(pwd)"
  git pull

  echo
  echo "Git pull が完了しました。"
}

project_summary_flow() {
  choose_project_type
  choose_output_file
  echo "⏳ プロジェクトファイルを収集・結合しています..."

  {
    echo "<project_context>"
    echo "Project Type: $PROJECT_TYPE"
    echo "Project Root: $PWD"
    echo "Directory Structure:"
    echo '```text'
    generate_tree
    echo '```'
    echo "</project_context>"
    echo
    echo "<files>"
  } > "$OUT_FILE"

  echo
  echo "出力完了：$OUT"
  for file in "${FILE_LIST[@]}"; do
    if [[ ! -f "$file" || ! -r "$file" ]]; then
      printf '%s: エラー: 読み取り可能なファイルではありません: %s\n' \
        "$PROGRAM_NAME" "$file" >&2
      exit 1
    fi

    printf '<file path="%s">\n' "$file" >> "$OUT_FILE"
    cat "$file" >> "$OUT_FILE"
    echo "</file>" >> "$OUT_FILE"
    echo >> "$OUT_FILE"
  done

  echo "</files>" >> "$OUT_FILE"
  echo >> "$OUT_FILE"
  echo "<instructions>" >> "$OUT_FILE"
  get_prompt_instruction "$PROMPT_MODE" >> "$OUT_FILE"
  echo "</instructions>" >> "$OUT_FILE"

  if command_exists pbcopy; then
    pbcopy < "$OUT_FILE"
    COPIED=true
  fi
}

# ============================================================================== 
# ユーザーへのサジェスト表示
# ============================================================================== 
show_suggestions() {
  echo "================================================="
  echo "✅ 完了しました！ 出力ファイル: $OUT_FILE"

  if [[ "$COPIED" == true ]]; then
    echo "✨ コンテキスト全体がクリップボードにコピーされています。"
    echo "   そのままAIチャットにペースト（Cmd+V）できます。"
  fi

  echo
  echo "💡 【AIへのオススメの伝え方】"
  echo "-------------------------------------------------"

  case "$PROMPT_MODE" in
    fix)
      echo "「クリップボードの内容（コードと設定）を読み込んでください。"
      echo " 現在、〇〇という操作をした時に ×× というエラーが出ます。"
      echo " 原因の特定と、対象ファイルの修正コードを出力してください。」"
      ;;
    review)
      echo "「クリップボードにプロジェクトのコードをコピーしました。"
      echo " 特に〇〇の処理周りについて、パフォーマンスと安全性の観点から"
      echo " リファクタリング案があれば教えてください。」"
      ;;
    summary)
      echo "「クリップボードのプロジェクトを読み込んでください。"
      echo " このプロジェクトに新しく参画する開発者向けに、"
      echo " 全体像とディレクトリ構成の役割を分かりやすく解説してください。」"
      ;;
    *)
      echo "不明なアクションです：$ACTION" >&2
      exit 1
    generic)
      echo "「クリップボードのファイル群を読み込んでください。"
      echo " まずプロジェクト種別・技術スタック・ディレクトリ構成を推定し、"
      echo " 根拠と不明点を明示したうえで、次に確認すべき事項を提案してください。」"
      ;;
  esac

  echo "-------------------------------------------------"
  echo
}

# ============================================================================== 
# メイン実行
# ============================================================================== 
main() {
  parse_args "$@"
  print_header
  choose_project_type
  choose_prompt_mode
  validate_project_root
  generate_output
  show_suggestions
}

main "$@"
