/**{
  "api": 1,
  "name": "Format HTML (2 spaces)",
  "description": "Indent with 2 spaces, keep long lines, add blank lines around <script> and <style>.",
  "author": "DELTHETA",
  "icon": "html",
  "tags": "format,html"
}**/

function main(state) {
  const src = state.fullText

  // ざっくり HTML をインデント（2スペース、改行はタグ前後だけ）
  const formatted = basicHtmlIndent(src, 2)

  // <script> / <style> の前後に空行を入れる
  const withBlankLines = addBlankLinesAroundBlocks(formatted)

  state.text = withBlankLines
}

/**
 * ごく簡単なインデントロジック:
 * - 開始タグでインデント+1、終了タグでインデント-1
 * - 自閉タグ、コメントなどはそのまま
 * - 行途中での折り返しはしない
 */
function basicHtmlIndent(src, indentSize) {
  const lines = src
    .replace(/\r\n/g, '\n')
    // タグごとに改行を挿入（テキストノードはなるべくそのまま）
    .replace(/>(\s*)</g, '>\n<')
    .split('\n')

  let depth = 0
  const indentUnit = ' '.repeat(indentSize)
  const result = []

  for (let rawLine of lines) {
    let line = rawLine.trim()
    if (!line) {
      continue
    }

    const isClosing =
      /^<\/[^>]+>/.test(line) ||
      /^<!DOCTYPE/i.test(line)

    if (isClosing && depth > 0) {
      depth -= 1
    }

    const indented = indentUnit.repeat(depth) + line
    result.push(indented)

    const isSelfClosing =
      /\/>$/.test(line) ||
      /^<!/.test(line) ||
      /^<meta/i.test(line) ||
      /^<link/i.test(line) ||
      /^<br\b[^>]*>$/i.test(line) ||
      /^<hr\b[^>]*>$/i.test(line)

    const opens =
      /<[^/!][^>]*>/.test(line) &&
      !isSelfClosing

    const closes = /<\/[^>]+>/.test(line)

    if (opens && !closes) {
      depth += 1
    }
  }

  return result.join('\n')
}

/**
 * <script> / <style> ブロックの上下に空行を追加
 */
function addBlankLinesAroundBlocks(src) {
  const lines = src.split('\n')
  const result = []
  const openRe = /<\s*(script|style)\b[^>]*>/i
  const closeRe = /<\s*\/\s*(script|style)\s*>/i

  let inBlock = false
  for (let i = 0; i < lines.length; i++) {
    const line = lines[i]

    if (openRe.test(line) && !inBlock) {
      // 直前が空行でなければ空行追加
      if (result.length > 0 && result[result.length - 1].trim() !== '') {
        result.push('')
      }
      inBlock = true
      result.push(line)
      continue
    }

    if (inBlock) {
      result.push(line)
      if (closeRe.test(line)) {
        inBlock = false
        // 閉じタグの後に空行（次の行が空じゃなければ）
        if (i + 1 < lines.length && lines[i + 1].trim() !== '') {
          result.push('')
        }
      }
      continue
    }

    result.push(line)
  }

  return result.join('\n')
}

