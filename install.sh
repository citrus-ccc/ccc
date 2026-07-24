#!/usr/bin/env bash
set -euo pipefail

# ------------------------------------------------------------------------------
# 設定・パスの定義
# ------------------------------------------------------------------------------
INSTALL_DIR="/usr/local/bin"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

print_header() {
  echo "========================================"
  echo " Multi-Tool Central Installer"
  echo "========================================"
  echo
}

# ------------------------------------------------------------------------------
# メイン処理
# ------------------------------------------------------------------------------
print_header

# 1. 各ツールディレクトリ内の .sh ファイルを自動検出 (depth 2)
scripts=()
while IFS= read -r -d '' file; do
  scripts+=("$file")
done < <(find "$SCRIPT_DIR" -mindepth 2 -maxdepth 2 -name "*.sh" -print0)

if [ ${#scripts[@]} -eq 0 ]; then
  echo "エラー: インストール対象のシェルスクリプトが見つかりません。" >&2
  exit 1
fi

echo "-> 以下のツールを検出しました:"
for script in "${scripts[@]}"; do
  tool_name="$(basename "$(dirname "$script")")"
  echo "   - [${tool_name}] ($(basename "$script"))"
done
echo

# 2. 管理者権限（sudo）が必要かチェック
needs_sudo=false
if [[ ! -w "$INSTALL_DIR" ]]; then
  needs_sudo=true
  echo "-> 管理者権限が必要です。パスワードの入力が求められます。"
fi

echo "-> コマンドを ${INSTALL_DIR} に登録しています..."

# 3. 各スクリプトに実行権限を付与し、ディレクトリ名をコマンド名としてリンク作成
for script in "${scripts[@]}"; do
  cmd_name="$(basename "$(dirname "$script")")"
  target_link="${INSTALL_DIR}/${cmd_name}"

  # 実行権限の付与
  chmod +x "$script"

  # シンボリックリンクの作成
  if [[ "$needs_sudo" == true ]]; then
    sudo ln -sf "$script" "$target_link"
  else
    ln -sf "$script" "$target_link"
  fi
  echo "   [OK] ${cmd_name} -> ${script}"
done

echo
echo "========================================"
echo " すべてのツールのインストールが完了しました！"
echo "========================================"


