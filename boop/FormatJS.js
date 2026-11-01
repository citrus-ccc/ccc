x/**
    {
        "name": "Format JavaScript (2 Spaces)",
        "description": "MinifyされたJavaScriptをインデント幅2で整形します",
        "author": "Custom",
        "bias": -0.1
    }
**/

function main(state) {
    let code = state.text;

    // 1. 文字列リテラルを一時退避
    const strings = [];
    code = code.replace(/(["'`])(?:\\.|[^\\])*?\1/g, (match) => {
        strings.push(match);
        return `__STR_${strings.length - 1}__`;
    });

    // 2. 構文記号の前後に空白と改行を挿入
    code = code
        .replace(/\s+/g, ' ')
        .replace(/\{/g, ' {\n')
        .replace(/\}/g, '\n}\n')
        .replace(/;/g, ';\n')
        .replace(/,/g, ', ')
        .replace(/:\s*/g, ': ')
        .replace(/\b(function|return|var|let|const|if|for|while|typeof|new)\b/g, '$1 ')
        .replace(/\s*([=+\-*/%&|<>!]+)\s*/g, ' $1 ')
        .replace(/\s*\(\s*/g, '(')
        .replace(/\s*\)\s*/g, ')')
        .replace(/\)\s*\{/g, ') {')
        .replace(/\n\s*;/g, ';');

    // 3. インデントの付与（幅2）
    const lines = code.split('\n');
    let indentLevel = 0;
    const indentStr = '  '; // スペース2つ
    const formattedLines = [];

    for (let rawLine of lines) {
        let line = rawLine.trim();
        if (!line) continue;

        const closeCount = (line.match(/\}/g) || []).length;
        const openCount = (line.match(/\{/g) || []).length;
        
        if (line.startsWith('}')) {
            indentLevel = Math.max(0, indentLevel - 1);
        }

        formattedLines.push(indentStr.repeat(indentLevel) + line);

        if (!line.startsWith('}')) {
            indentLevel = Math.max(0, indentLevel + openCount - closeCount);
        } else {
            indentLevel = Math.max(0, indentLevel + (openCount - (closeCount - 1)));
        }
    }

    let result = formattedLines.join('\n');

    // 4. 退避した文字列リテラルを復元
    result = result.replace(/__STR_(\d+)__/g, (_, index) => {
        return strings[Number(index)];
    });

    state.text = result;
}
