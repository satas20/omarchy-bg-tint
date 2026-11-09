.pragma library

function parseState(text) {
  var state = { theme: "", current: "", cfg: {}, colors: [], sources: [], outs: [] }
  String(text || "").split("\n").forEach(function(line) {
    var f = line.split("\t")
    switch (f[0]) {
      case "theme": state.theme = f[1] || ""; break
      case "current": state.current = f[1] || ""; break
      case "cfg": state.cfg[f[1]] = f.slice(2).join("\t"); break
      case "color": state.colors.push({ key: f[1], hex: f[2] }); break
      case "src": state.sources.push(f[1]); break
      case "out": state.outs.push(f[1]); break
    }
  })
  return state
}

// COLORS="" means every palette colour is selected.
function selectedKeys(cfg, colors) {
  var raw = String(cfg.COLORS || "").trim()
  if (!raw) return colors.map(function(c) { return c.key })
  var want = raw.split(",")
  return colors.filter(function(c) { return want.indexOf(c.key) >= 0 }).map(function(c) { return c.key })
}

function toggleKey(cfg, colors, key) {
  var keys = selectedKeys(cfg, colors)
  var i = keys.indexOf(key)
  if (i >= 0) {
    if (keys.length <= 2) return null
    keys.splice(i, 1)
  } else {
    keys.push(key)
  }
  return keys.length === colors.length ? "" : keys.join(",")
}

function baseName(path) {
  var name = String(path || "").split("/").pop()
  return name.replace(/\.[^.]+$/, "")
}

// tint-<stem>-<hash>.jpg → <stem>
function outStem(path) {
  return baseName(path).replace(/^tint-/, "").replace(/-[0-9a-f]{8}$/, "")
}
