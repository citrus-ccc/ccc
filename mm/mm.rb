#!/usr/bin/env ruby
# frozen_string_literal: true

require 'fileutils'
require 'json'
require 'optparse'
require 'securerandom'

STATE_DIR  = File.join(Dir.home, '.cache', 'tidy_files')
UNDO_FILE  = File.join(STATE_DIR, 'last_run.json')
BACKUP_DIR = File.join(STATE_DIR, 'backup')

IS_TTY = $stdout.isatty

def colorize(text, code)
  IS_TTY ? "\e[#{code}m#{text}\e[0m" : text
end

def log_info(msg)
  puts "#{colorize('➜', 34)} #{msg}" if IS_TTY
end

def log_success(msg)
  puts "#{colorize('✔', 32)} #{msg}" if IS_TTY
end

def log_warn(msg)
  puts "#{colorize('⚠', 33)} #{msg}" if IS_TTY
end

def log_error(msg)
  $stderr.puts "#{colorize('✘', 31)} #{msg}"
end

def notify(message, subtitle = '')
  script = %(display notification "#{message}" with title "Tidy Files" subtitle "#{subtitle}")
  system('osascript', '-e', script)
end

# 人間が読みやすいファイルサイズ表記
def human_size(bytes)
  units = %w[B KB MB GB TB]
  return '0 B' if bytes.to_i.zero?

  exp = (Math.log(bytes) / Math.log(1024)).to_i
  exp = units.size - 1 if exp >= units.size
  format('%.1f %s', bytes.to_f / (1024**exp), units[exp]).sub('.0 ', ' ')
end

# 日時とサイズの情報を取得
def file_meta(path)
  stat = File.stat(path)
  time_str = stat.mtime.strftime('%Y-%m-%d %H:%M:%S')
  size_str = human_size(stat.size)
  "#{time_str} (#{size_str})"
rescue StandardError
  '情報取得不可'
end

# 衝突しない別名（例: file (1).ext）を生成
def generate_unique_path(dest)
  return dest unless File.exist?(dest)

  dir = File.dirname(dest)
  ext = File.extname(dest)
  base = File.basename(dest, ext)
  i = 1
  loop do
    candidate = File.join(dir, "#{base} (#{i})#{ext}")
    return candidate unless File.exist?(candidate)

    i += 1
  end
end

# ----------------------------------------------------
# Undo 処理
# ----------------------------------------------------
def run_undo
  unless File.exist?(UNDO_FILE)
    log_warn('元に戻せる直前の操作履歴がありません。')
    notify('元に戻せる直前の操作履歴がありません。', 'Undo不可') unless IS_TTY
    exit 0
  end

  begin
    state = JSON.parse(File.read(UNDO_FILE))
  rescue StandardError => e
    log_error("履歴ファイルの読み込みに失敗しました: #{e.message}")
    exit 1
  end

  restored_count = 0
  state['moves'].reverse_each do |item|
    current_path = item['dest']
    orig_path    = item['src']
    backup_path  = item['backup']

    if File.exist?(current_path)
      FileUtils.mkdir_p(File.dirname(orig_path))
      FileUtils.mv(current_path, orig_path)
      restored_count += 1
      log_info("戻しました: #{File.basename(orig_path)}")
    end

    if backup_path && File.exist?(backup_path)
      FileUtils.mkdir_p(File.dirname(current_path))
      FileUtils.mv(backup_path, current_path)
      log_info("上書き前のファイルを復元: #{File.basename(current_path)}")
    end
  end

  dest_dir = state['dest_dir']
  if Dir.exist?(dest_dir) && (Dir.children(dest_dir) - ['.DS_Store']).empty?
    FileUtils.rm_rf(dest_dir)
  end

  FileUtils.rm_f(UNDO_FILE)
  FileUtils.rm_rf(BACKUP_DIR)

  msg = "#{restored_count} 件の項目を元の場所に戻しました。"
  log_success(msg)
  notify(msg, '取り消し完了') unless IS_TTY
  exit 0
end

# ----------------------------------------------------
# オプション解析
# ----------------------------------------------------
options = {
  open_finder: false,
  dry_run: false,
  force_overwrite: false,
  force_rename: false
}

opt_parser = OptionParser.new do |opts|
  opts.banner = '使用方法: ftidy [オプション] [ディレクトリ] <拡張子> | ftidy undo'
  opts.separator ''
  opts.separator 'オプション:'

  opts.on('-o', '--open', '処理完了後に Path Finder で開く') { options[:open_finder] = true }
  opts.on('-n', '--dry-run', '実際には移動せず、確認のみ行う') { options[:dry_run] = true }
  opts.on('-f', '--force', '衝突確認を行わず、すべて上書きする') { options[:force_overwrite] = true }
  opts.on('--rename', '衝突確認を行わず、すべて別名保存する') { options[:force_rename] = true }
  opts.on('-h', '--help', 'ヘルプを表示する') do
    puts opts
    exit 0
  end
end

opt_parser.parse!(ARGV)

run_undo if ARGV.first&.downcase == 'undo'

if ARGV.empty?
  puts opt_parser
  exit 1
end

# ----------------------------------------------------
# パスと拡張子の解決
# ----------------------------------------------------
home = Dir.home

if ARGV.length == 1
  ext = ARGV[0]
  if IS_TTY
    target_dir = Dir.pwd
    location_name = File.basename(target_dir)
  else
    target_dir = File.join(home, 'Downloads')
    location_name = 'ダウンロード'
  end
else
  ext = ARGV.pop
  path_str = ARGV.join(' ').gsub(/^['"]|['"]$/, '').gsub('\\ ', ' ')

  case path_str.downcase
  when '.', 'here', 'pwd'
    target_dir = Dir.pwd
    location_name = File.basename(target_dir)
  when 'desktop', 'desk', 'dt'
    target_dir = File.join(home, 'Desktop')
    location_name = 'デスクトップ'
  when 'downloads', 'download', 'dl'
    target_dir = File.join(home, 'Downloads')
    location_name = 'ダウンロード'
  when 'documents', 'document', 'doc', 'docs'
    target_dir = File.join(home, 'Documents')
    location_name = '書類'
  when 'pictures', 'picture', 'pic', 'pics'
    target_dir = File.join(home, 'Pictures')
    location_name = 'ピクチャ'
  when 'home', '~'
    target_dir = home
    location_name = 'ホーム'
  else
    expanded = File.expand_path(path_str)
    if Dir.exist?(expanded)
      target_dir = expanded
      location_name = File.basename(expanded)
    else
      log_error("指定されたフォルダが見つかりませんでした: #{path_str}")
      notify("指定されたフォルダが見つかりませんでした: #{path_str}", 'エラー') unless IS_TTY
      exit 1
    end
  end
end

ext = ext.delete_prefix('.').downcase
if ext.empty?
  log_error('拡張子が指定されていません。')
  exit 1
end

target_folder = "_#{ext}"
dest_dir = File.join(target_dir, target_folder)

pattern = File.join(target_dir, "*.#{ext}")
targets = Dir.glob(pattern, File::FNM_CASEFOLD).reject do |path|
  name = File.basename(path)
  name.start_with?('.') || File.identical?(path, dest_dir) rescue false
end

if targets.empty?
  msg = "#{location_name} に対象の .#{ext} は見つかりませんでした。"
  log_warn(msg)
  notify(msg, '該当なし') unless IS_TTY
  exit 0
end

if options[:dry_run]
  puts "#{colorize('[Dry Run]', 33)} 以下の項目が移動対象です (移動先: #{dest_dir}):"
  targets.each do |t|
    dest_path = File.join(dest_dir, File.basename(t))
    status = File.exist?(dest_path) ? colorize('(同名ファイルあり)', 31) : ''
    puts "  - #{File.basename(t)} #{status}"
  end
  exit 0
end

# ----------------------------------------------------
# 移動処理と対話的衝突解決
# ----------------------------------------------------
FileUtils.mkdir_p(STATE_DIR)
FileUtils.rm_rf(BACKUP_DIR)
FileUtils.mkdir_p(BACKUP_DIR)

$history = []
$global_choice = nil # 'all_overwrite' または 'all_rename'
$global_choice = 'all_overwrite' if options[:force_overwrite]
$global_choice = 'all_rename' if options[:force_rename]

def resolve_conflict(src, dest)
  return :overwrite if $global_choice == 'all_overwrite'
  return :rename    if $global_choice == 'all_rename'

  # Alfred 等の非対話実行時は安全のため自動リネーム
  return :rename unless IS_TTY

  puts "\n#{colorize('⚠ 同名ファイルが既に存在します:', 33)} #{File.basename(dest)}"
  puts "   #{colorize('[移動元/新]', 36)} #{file_meta(src)}"
  puts "   #{colorize('[移動先/旧]', 35)} #{file_meta(dest)}"

  loop do
    print "   どうしますか？ [#{colorize('o', 32)}:上書き / #{colorize('r', 34)}:別名で保存 / #{colorize('s', 33)}:スキップ / #{colorize('O', 32)}:以降すべて上書き / #{colorize('R', 34)}:以降すべて別名]: "
    ans = $stdin.gets&.strip

    case ans
    when 'o'
      return :overwrite
    when 'r'
      return :rename
    when 's'
      return :skip
    when 'O'
      $global_choice = 'all_overwrite'
      return :overwrite
    when 'R'
      $global_choice = 'all_rename'
      return :rename
    else
      puts "   無効な入力です。'o', 'r', 's', 'O', 'R' のいずれかを入力してください。"
    end
  end
end

def record_and_move(src, dest)
  if File.directory?(src)
    if Dir.exist?(dest)
      Dir.children(src).each do |child|
        record_and_move(File.join(src, child), File.join(dest, child))
      end
      FileUtils.rmdir(src) rescue nil
    else
      FileUtils.mkdir_p(File.dirname(dest))
      FileUtils.mv(src, dest)
      $history << { 'src' => src, 'dest' => dest, 'backup' => nil }
    end
    return
  end

  # 通常ファイル処理
  FileUtils.mkdir_p(File.dirname(dest))

  if File.exist?(dest)
    choice = resolve_conflict(src, dest)

    case choice
    when :skip
      log_warn("スキップしました: #{File.basename(src)}")
      return
    when :rename
      actual_dest = generate_unique_path(dest)
      FileUtils.mv(src, actual_dest)
      $history << { 'src' => src, 'dest' => actual_dest, 'backup' => nil }
      log_info("別名で移動: #{File.basename(src)} ➜ #{File.basename(actual_dest)}")
      return
    when :overwrite
      backup_file = File.join(BACKUP_DIR, SecureRandom.uuid)
      FileUtils.mv(dest, backup_file) # 上書き前ファイルを退避
      FileUtils.mv(src, dest)
      $history << { 'src' => src, 'dest' => dest, 'backup' => backup_file }
      log_info("上書き移動: #{File.basename(src)}")
      return
    end
  else
    FileUtils.mv(src, dest)
    $history << { 'src' => src, 'dest' => dest, 'backup' => nil }
    log_info("移動: #{File.basename(src)}")
  end
end

FileUtils.mkdir_p(dest_dir)

targets.each do |item|
  dest_path = File.join(dest_dir, File.basename(item))
  record_and_move(item, dest_path)
end

# Undo ログ保存
state_data = {
  'timestamp' => Time.now.to_s,
  'dest_dir' => dest_dir,
  'location_name' => location_name,
  'moves' => $history
}
File.write(UNDO_FILE, JSON.pretty_generate(state_data))

msg = "#{$history.size} 件の項目を #{location_name} の #{target_folder} に整理しました。"
log_success(msg)

system('open', '-a', 'Path Finder', dest_dir) if options[:open_finder]
notify(msg, '整理が完了しました') unless IS_TTY
