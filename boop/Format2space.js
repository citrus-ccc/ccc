/**
{
  "api": 1,
  "name": "Format 2 Spaces Indent",
  "description": "Replaces NBSP and normalizes tabs/4-spaces to 2 spaces.",
  "author": "gen",
  "icon": "broom",
  "tags": ["format", "indent", "2 spaces", "tabs"]
}
**/
function main(state) {
  // 1. コピペ時に混入しやすいノーブレークスペースなどを通常の半角スペースに変換
  let text = state.text.replace(/[\xA0\u200B]/g, ' ');

  // 2. タブ文字を半角スペース2つに変換
  text = text.replace(/\t/g, '  ');

  // 3. 行頭のスペース4つを2つに半減させる（簡易的な2スペースインデント化）
  const lines = text.split('\n');
  const newLines = lines.map(line => {
    const match = line.match(/^( +)(.*)$/);
    if (match) {
      // 行頭のスペース数を半分にする
      const spaces = match[1].length;
      const newSpaces = ' '.repeat(Math.floor(spaces / 2));
      return newSpaces + match[2];
    }
    return line;
  });

  state.text = newLines.join('\n');
}