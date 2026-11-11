.pragma library

function isLongBracketStart(source, index) {
  const match = /^\[(=*)\[/.exec(source.slice(index))
  return match ? match[0] : ""
}

function luaTokens(source) {
  const tokens = []
  let index = 0

  while (index < source.length) {
    const character = source[index]
    if (/\s/.test(character)) {
      index++
      continue
    }

    if (source.slice(index, index + 2) === "--") {
      const longStart = isLongBracketStart(source, index + 2)
      if (longStart) {
        const equals = longStart.slice(1, -1)
        const end = "]" + equals + "]"
        const close = source.indexOf(end, index + 2 + longStart.length)
        index = close < 0 ? source.length : close + end.length
      } else {
        const newline = source.indexOf("\n", index + 2)
        index = newline < 0 ? source.length : newline + 1
      }
      continue
    }

    const longStart = character === "[" ? isLongBracketStart(source, index) : ""
    if (longStart) {
      const equals = longStart.slice(1, -1)
      const end = "]" + equals + "]"
      const start = index + longStart.length
      const close = source.indexOf(end, start)
      tokens.push({
        type: "string",
        value: source.slice(start, close < 0 ? source.length : close)
      })
      index = close < 0 ? source.length : close + end.length
      continue
    }

    if (character === "\"" || character === "'") {
      const quote = character
      let value = ""
      index++
      while (index < source.length && source[index] !== quote) {
        if (source[index] === "\\" && index + 1 < source.length) {
          const escaped = source[index + 1]
          const escapes = { a: "\x07", b: "\b", f: "\f", n: "\n",
            r: "\r", t: "\t", v: "\x0b", "\\": "\\", "\"": "\"", "'": "'" }
          value += escapes[escaped] !== undefined ? escapes[escaped] : escaped
          index += 2
        } else {
          value += source[index]
          index++
        }
      }
      if (index >= source.length)
        return null
      index++
      tokens.push({ type: "string", value: value })
      continue
    }

    const identifier = /^[A-Za-z_][A-Za-z0-9_]*/.exec(source.slice(index))
    if (identifier) {
      tokens.push({ type: "identifier", value: identifier[0] })
      index += identifier[0].length
      continue
    }

    const number = /^\d+/.exec(source.slice(index))
    if (number) {
      tokens.push({ type: "number", value: number[0] })
      index += number[0].length
      continue
    }

    const symbol = source.slice(index, index + 2) === ".."
      ? ".." : character
    tokens.push({ type: "symbol", value: symbol })
    index += symbol.length
  }

  return tokens
}

function addValue(values, name, value) {
  if (!values[name])
    values[name] = []
  if (values[name].indexOf(value) === -1)
    values[name].push(value)
}

function staticValues(tokens) {
  const values = ({})
  for (let index = 0; index + 3 < tokens.length; index++) {
    if (tokens[index].value === "local"
        && tokens[index + 1].type === "identifier"
        && tokens[index + 2].value === "="
        && (tokens[index + 3].type === "string"
          || tokens[index + 3].type === "number")) {
      const atom = tokens[index + 3]
      addValue(values, tokens[index + 1].value,
        atom.type === "number" ? Number(atom.value) : atom.value)
    }

    if (tokens[index].value !== "for"
        || tokens[index + 1].type !== "identifier"
        || tokens[index + 2].value !== "="
        || tokens[index + 3].type !== "number")
      continue

    const commaIndex = index + 4
    if (tokens[commaIndex]?.value !== ","
        || tokens[commaIndex + 1]?.type !== "number")
      continue
    const start = Number(tokens[index + 3].value)
    const finish = Number(tokens[commaIndex + 1].value)
    const step = tokens[commaIndex + 2]?.value === ","
      && tokens[commaIndex + 3]?.type === "number"
      ? Number(tokens[commaIndex + 3].value) : 1
    if (step === 0 || Math.abs(finish - start) / Math.abs(step) > 256)
      continue
    for (let value = start;
         step > 0 ? value <= finish : value >= finish;
         value += step) {
      addValue(values, tokens[index + 1].value, value)
    }
  }
  return values
}

function parseConcat(tokens, values) {
  let parts = tokens
  while (parts.length >= 2 && parts[0].value === "("
      && parts[parts.length - 1].value === ")")
    parts = parts.slice(1, -1)

  const resolved = [""]
  let expectAtom = true
  for (const token of parts) {
    if (expectAtom) {
      let atomValues
      if (token.type === "string")
        atomValues = [token.value]
      else if (token.type === "number")
        atomValues = [token.value]
      else if (token.type === "identifier")
        atomValues = values[token.value]
      else
        return null
      if (!atomValues || atomValues.length === 0)
        return null

      const combined = []
      for (const prefix of resolved) {
        for (const value of atomValues) {
          combined.push(prefix + String(value))
          if (combined.length > 256)
            return null
        }
      }
      resolved.splice(0, resolved.length, ...combined)
      expectAtom = false
    } else {
      if (token.value !== "..")
        return null
      expectAtom = true
    }
  }
  return expectAtom ? null : resolved
}

function bindingExpressions(tokens) {
  const expressions = []
  for (let index = 0; index + 3 < tokens.length; index++) {
    if (tokens[index].value !== "hl"
        || tokens[index + 1].value !== "."
        || tokens[index + 2].value !== "bind"
        || tokens[index + 3].value !== "(")
      continue

    const expression = []
    let depth = 0
    let end = false
    for (let cursor = index + 4; cursor < tokens.length; cursor++) {
      const value = tokens[cursor].value
      if (value === "," && depth === 0) {
        end = true
        break
      }
      if (value === "(" || value === "{" || value === "[")
        depth++
      else if (value === ")" || value === "}" || value === "]") {
        if (depth === 0)
          break
        depth--
      }
      expression.push(tokens[cursor])
    }
    if (!end)
      return { valid: false, expressions: [] }
    expressions.push(expression)
  }
  return { valid: true, expressions: expressions }
}

function sourceFiles(output) {
  const marker = "\n__MYQUICKSHELL_LUA_FILE__\n"
  const sections = output.split(marker)
  if (sections.length < 2)
    return []
  return sections.slice(1)
}

function inspectBindings(output, shortcut, canonicalize) {
  const files = sourceFiles(output)
  if (files.length === 0)
    return { valid: false, conflict: false }

  for (const source of files) {
    const tokens = luaTokens(source)
    if (!tokens)
      return { valid: false, conflict: false }
    const expressions = bindingExpressions(tokens)
    if (!expressions.valid)
      return { valid: false, conflict: false }

    const values = staticValues(tokens)
    for (const expression of expressions.expressions) {
      const chords = parseConcat(expression, values)
      if (!chords)
        return { valid: false, conflict: false }
      for (const chord of chords) {
        if (canonicalize(chord) === shortcut)
          return { valid: true, conflict: true }
      }
    }
  }

  return { valid: true, conflict: false }
}
