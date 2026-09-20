/**{
  "api": 1,
  "name": "Format JSON (2 spaces)",
  "description": "Pretty-print JSON with 2-space indent.",
  "author": "DELTHETA",
  "icon": "curlybraces",
  "tags": "format,json"
}**/

function main(state) {
  try {
    const obj = JSON.parse(state.fullText)
    state.text = JSON.stringify(obj, null, 2)
  } catch (e) {
    state.postError("JSON parse error: " + e.message)
  }
}

