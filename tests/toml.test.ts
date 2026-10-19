import assert from 'node:assert/strict'
import { describe, it } from 'node:test'
import { familyOf, parseForgeToml, parseRoute, resolveRole } from '../src/roles.ts'
import { parseToml, TomlError } from '../src/toml.ts'

describe('parseToml', () => {
  it('reads tables, strings, numbers, booleans, and arrays', () => {
    const t = parseToml([
      '# forge settings',
      'version = 1',
      '',
      '[roles]',
      'build = "deepseek-official/deepseek-chat"  # cheap builder',
      "review = ['openrouter/qwen/qwen3-coder', \"x/y\"]",
      '"quoted-key" = "a\\"b\\\\c\\u0041"',
      '',
      '[budgets]',
      'bug = 150',
      'ratio = 1.5',
      'big = 1_000',
      'strict = true',
      'list = [',
      '  "a", # first',
      '  "b",',
      ']',
    ].join('\n'))
    assert.equal(t['']!.version, 1)
    assert.equal(t.roles!.build, 'deepseek-official/deepseek-chat')
    assert.deepEqual(t.roles!.review, ['openrouter/qwen/qwen3-coder', 'x/y'])
    assert.equal(t.roles!['quoted-key'], 'a"b\\cA')
    assert.deepEqual(t.budgets, { bug: 150, ratio: 1.5, big: 1000, strict: true, list: ['a', 'b'] })
  })

  it('keeps a dotted table name as one key', () => {
    assert.deepEqual(parseToml('[a.b]\nx = 1\n')['a.b'], { x: 1 })
  })

  it('handles CRLF line endings and an empty file', () => {
    assert.deepEqual(parseToml('[roles]\r\nbuild = "a/b"\r\n').roles, { build: 'a/b' })
    assert.deepEqual(parseToml(''), { '': {} })
  })

  const errors: [string, RegExp][] = [
    ['[roles]\nbuild = deepseek/chat\n', /line 2: unsupported value/],
    ['[roles]\nbuild = { provider = "a" }\n', /inline tables/],
    ['[[roles]]\n', /arrays of tables/],
    ['[roles]\nbuild = "a/b"\nbuild = "c/d"\n', /line 3: key "build" defined twice/],
    ['[roles]\n[roles]\n', /table \[roles\] defined twice/],
    ['x = "unterminated\n', /unterminated string/],
    ['x = """multi"""\n', /multi-line strings/],
    ['a.b = 1\n', /dotted keys/],
    ['x = 1 y = 2\n', /expected end of line/],
    ['x = [1, 2\n', /expected , or \]/],
  ]
  for (const [text, re] of errors) {
    it(`rejects ${JSON.stringify(text.split('\n')[0])} with a line number`, () => {
      assert.throws(() => parseToml(text), (e: unknown) => e instanceof TomlError && re.test(e.message))
    })
  }
})

describe('forge.toml roles', () => {
  it('splits provider from model at the first slash', () => {
    assert.deepEqual(parseRoute('openrouter/qwen/qwen3-coder'), { provider: 'openrouter', model: 'qwen/qwen3-coder' })
    assert.equal(parseRoute('no-slash'), undefined)
    assert.equal(parseRoute('/model'), undefined)
    assert.equal(parseRoute('provider/'), undefined)
  })

  it('reports unknown roles and bad routes as warnings', () => {
    const { config, warnings } = parseForgeToml('[roles]\nbuild = "a/b"\nplanner = "c/d"\nreview = "nope"\n[effort]\nreview = "high"\nmystery = "x"\n')
    assert.deepEqual(config.roles.build, [{ provider: 'a', model: 'b' }])
    assert.deepEqual(config.roles.review, [])
    assert.equal(config.effort.review, 'high')
    assert.equal(warnings.length, 3)
  })

  it('unmapped and inherit roles fall back to the parent route', () => {
    const { config } = parseForgeToml('[roles]\nescalation = "inherit"\n')
    assert.equal(resolveRole(config, 'escalation').inherit, true)
    assert.equal(resolveRole(config, 'ground').inherit, true)
  })

  it('derives families from model ids, with [families] overrides', () => {
    assert.equal(familyOf({ provider: 'deepseek-official', model: 'deepseek-chat' }, {}), 'deepseek')
    assert.equal(familyOf({ provider: 'openrouter', model: 'qwen/qwen3-coder' }, {}), 'qwen')
    assert.equal(familyOf({ provider: 'zai', model: 'glm-4.6' }, {}), 'glm')
    assert.equal(familyOf({ provider: 'x', model: 'r1-distill' }, { 'x/r1-distill': 'DeepSeek' }), 'deepseek')
  })

  it('review prefers a different model family than build', () => {
    const { config } = parseForgeToml([
      '[roles]',
      'build = "deepseek-official/deepseek-chat"',
      'review = ["deepseek-official/deepseek-reasoner", "openrouter/qwen/qwen3-coder"]',
    ].join('\n'))
    const review = resolveRole(config, 'review')
    assert.equal(review.inherit, false)
    if (!review.inherit) {
      assert.deepEqual(review.route, { provider: 'openrouter', model: 'qwen/qwen3-coder' })
      assert.equal(review.warning, undefined)
    }
  })

  it('review keeps a same-family route but warns when it is the only option', () => {
    const { config } = parseForgeToml('[roles]\nbuild = "a/deepseek-chat"\nreview = "b/deepseek-reasoner"\n')
    const review = resolveRole(config, 'review')
    assert.equal(review.inherit, false)
    if (!review.inherit) assert.match(review.warning ?? '', /same model family as build \(deepseek\)/)
  })

  it('review takes its first candidate when build is unmapped', () => {
    const { config } = parseForgeToml('[roles]\nreview = ["a/deepseek-chat", "b/qwen3"]\n')
    const review = resolveRole(config, 'review')
    assert.equal(!review.inherit && review.route.model, 'deepseek-chat')
  })
})
