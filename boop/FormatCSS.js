/**{
  "api": 1,
  "name": "Format CSS (2 spaces)",
  "description": "Simple CSS formatter with 2-space indent.",
  "author": "DELTHETA",
  "icon": "paintbrush",
  "tags": "format,css"
}**/

function main(state) {
  const src = state.fullText
    .replace(/\r\n/g, '\n')
    .replace(/\s*{\s*/g, ' {\n')
    .replace(/;\s*/g, ';\n')
    .replace(/\s*}\s*/g, '\n}\n')

  const lines = src.split('\n')
  let depth = 0
  const indent = '  '
  const out = []

  for (let line of lines) {
    const trimmed = line.trim()
    if (!trimmed) continue

    if (trimmed === '}') {
      depth = Math.max(0, depth - 1)
    }

    out.push(indent.repeat(depth) + trimmed)

    if (trimmed.endsWith('{')) {
      depth += 1
    }
  }

  state.text = out.join('\n')
}

