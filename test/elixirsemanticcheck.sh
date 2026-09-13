#!/usr/bin/env bash
# Static Elixir name resolution: every positive has same-name decoys and scope/arity negatives.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
BIN="${RIPWIRE_BIN:-$ROOT/build/ripwire}"
python3 - "$BIN" <<'PY'
import json, os, pathlib, subprocess, sys, tempfile, xml.etree.ElementTree as ET

with tempfile.TemporaryDirectory() as tmp:
    root = pathlib.Path(tmp)
    code = root / 'code'
    code.mkdir()
    cache = root / 'cache'
    cache.mkdir()
    env = dict(os.environ, XDG_CACHE_HOME=str(cache))
    def write(path, text):
        p = code / path
        p.parent.mkdir(parents=True, exist_ok=True)
        p.write_text(text)
    write('lib.ex', r'''
defmodule Real.Work do
  def run(), do: 0
  def run(x), do: x
  def run(x, y), do: {x, y}
  def defaults(x, y \\ 1), do: {x, y}
  def clauses(x \\ 1)
  def clauses(0), do: zero()
  def clauses(x) when x > 0, do: positive()
  def zero(), do: 0
  def positive(), do: 1
  defp hidden(x), do: x
  defmacro macro(x), do: x
end
defmodule Real.Other do
  def run(x), do: x
end
defmodule Decoy do
  def run(), do: 0
  def run(x), do: x
  def run(x, y), do: {x, y}
  def missing(x), do: x
  def defaults(), do: 0
  def hidden(x), do: x
  def unbound(), do: 0
end
''')
    lib = (code / 'lib.ex').read_text()
    split = lib.index('defmodule Real.Other')
    write('other.ex', lib[split:])
    write('lib.ex', lib[:split])
    write('apps/client/main.ex', r'''
defmodule Client do
  alias Real.{Work, Other}
  alias Work, as: W
  import Real.Work, only: [run: 1]
  def remote(x), do: W.run(x)
  def absolute(x), do: Elixir.Real.Work.run(x)
  def imported(x), do: run(x)
  def wrong_import(), do: run()
  def pipe(x), do: x |> W.run()
  def pipe_bare(x), do: x |> W.run
  def capture(), do: &W.run/1
  def local_capture(), do: &local/1
  def local(x), do: x
  def apply_capture(), do: &W.run(&1)
  def default_call(), do: W.defaults(1)
  def all_defaults(), do: W.clauses()
  def wrong_defaults(), do: W.defaults()
  def bad_module(x), do: Outside.run(x)
  def bad_private(x), do: W.hidden(x)
  defdelegate delegated(x), to: W, as: :run
  defdelegate run_again(x), to: Work, as: :run
  def own(x), do: __MODULE__.local(x)
  def scoped(x) do
    alias Other, as: W
    W.run(x)
  end
  def after_scope(x), do: W.run(x)
  def branch_alias(x) do
    if x do
      alias Real.Other, as: W
      W.run(x)
    else
      W.run(x)
    end
  end
  def branch_import(x) do
    if x do
      import Real.Work, only: []
      run(x)
    else
      run(x)
    end
  end
  def function_import(x) do
    import Real.Other, only: [run: 1]
    run(x)
  end
  def no_leak(x), do: run(x)
  def bare(), do: zero_local
  def zero_local(), do: 0
  def shadow(zero_local), do: zero_local
  def match_rhs(), do: zero_local = zero_local
  def match_shadow() do
    zero_local = 1
    zero_local
  end
  def capture_shadow(zero_local), do: &zero_local/0
  def unknown_bare(), do: unbound
  def pattern({:ok, zero_local}), do: zero_local
  def branch_shadow(x) do
    case x do
      {:ok, zero_local} -> zero_local
      _ -> zero_local
    end
  end
  def with_else(x) do
    with {:ok, zero_local} <- x do
      zero_local
    else
      _ -> zero_local
    end
  end
  def no_quoted() do
    quote do
      alias Decoy
      def phantom(), do: Decoy.run()
    end
  end
  defmodule Nested do
    def run(x), do: x
  end
  def nested(x), do: Nested.run(x)
end
defmodule Sibling do
  def no_alias(x), do: W.run(x)
  import Real.Work, except: [run: 1]
  def excluded(x), do: run(x)
  def included(), do: run()
  import Real.Work, only: :functions
  def no_macro(x), do: macro(x)
end
''')
    write('contracts.ex', r'''
defmodule Behaviour do
  @callback execute(integer()) :: :ok
end
defmodule Contracts do
  @behaviour Behaviour
  @type id :: integer()
  @typep private_id :: integer()
  @opaque token(a) :: {a, integer()}
  @callback execute(id()) :: :ok
  @macrocallback build(term()) :: Macro.t()
  @callback constrained(a) :: a when a: atom()
  @limit seed()
  @spec seed() :: integer()
  def seed(), do: 7
  def limit(), do: @limit
  def commented(
    # comments are not arguments
    x,
    y
  ), do: {x, y}
  defstruct [:id, count: 0]
end
''')
    write('operators.ex', r'''
defmodule Operators do
  import Kernel, except: [+: 2]
  def a + b when is_integer(a), do: {a, b}
  def sum(x), do: x + 1
  def a(), do: 1
  def b(), do: 2
end
defprotocol Multi do
  def render(x)
end
defimpl Multi, for: [Integer, Atom] do
  def render(x), do: local(x)
  def local(x), do: __MODULE__.identity(x)
  def identity(x), do: x
end
''')
    def run(*args):
        return subprocess.check_output([sys.argv[1], str(code), *args], env=env)
    def parse(data):
        tree = ET.fromstring(data)
        # row 6 (2026-09-12): the row prints sc= (the scope); its canonical id composes as <f p=>::sc::n
        return {f.get('p') + '::' + s.get('sc') + '::' + s.get('n'): s for f in tree.iter('f') for s in f.iter('s') if s.get('sc')}
    def targets(rows, name, scope='Client'):
        key = 'apps/client/main.ex::' + scope + '::' + name
        assert key in rows, ('missing definition', key, sorted(rows))
        return {(c.get('id') or c.get('n')) for c in rows[key].iter('c')}
    cold = run('--no-cache')
    rows = parse(cold)
    protocol_uses = ET.fromstring(run('--uses=Multi', '--no-cache'))
    assert any(u.get('role') == 'extends' for u in protocol_uses.iter('u')), 'defimpl lost its protocol relation'
    implementations = ET.fromstring(run('--lego=Multi', '--no-cache'))
    assert {i.get('n') for i in implementations.iter('impl')} == {'Multi.Atom', 'Multi.Integer'}
    behaviour_uses = ET.fromstring(run('--uses=Behaviour', '--no-cache'))
    assert any(u.get('role') == 'extends' for u in behaviour_uses.iter('u')), '@behaviour lost its contract relation'
    module_uses = ET.fromstring(run('--uses=Real.Work', '--no-cache'))
    assert any(u.get('role') == 'import' for u in module_uses.iter('u')), 'module directives missing from use-sites'
    for name in ['@type id/0', '@type private_id/0', '@type token/1', '@callback execute/1', '@callback build/1', '@callback constrained/1', '@limit', 'commented/2']:
        assert 'contracts.ex::Contracts::' + name in rows, ('missing attribute', name)
    contract_module = next(s for s in ET.fromstring(cold).iter('s') if s.get('n') == 'Contracts')
    assert contract_module.get('t') == 'struct', contract_module.attrib
    attr = rows['contracts.ex::Contracts::@limit']
    assert any(c.get('n') == 'seed/0' for c in attr.iter('c')), 'compile-time attribute expression lost its call'
    assert 'operators.ex::Operators::+/2' in rows
    assert not list(rows['operators.ex::Operators::+/2'].iter('c')), 'operator parameters became zero-arity calls'
    assert any(c.get('n') == '+/2' for c in rows['operators.ex::Operators::sum/1'].iter('c'))
    for module in ['Multi.Atom', 'Multi.Integer']:
        assert 'operators.ex::' + module + '::render/1' in rows
        assert any(c.get('n') == 'local/1' for c in rows['operators.ex::' + module + '::render/1'].iter('c'))
        assert any(c.get('n') == 'identity/1' for c in rows['operators.ex::' + module + '::local/1'].iter('c'))
    # Canonical function names include arity; a zero-arity and a unary function cannot share an id.
    assert 'lib.ex::Real.Work::run/0' in rows and 'lib.ex::Real.Work::run/1' in rows, sorted(rows)
    def edge(name, target, scope='Client'):
        found = targets(rows, name, scope)
        # c rows expose names even where the normal map omits the canonical target id.
        assert any(t == target or t.endswith('::' + target) for t in found), (name, target, found)
    for name in ['remote/1', 'absolute/1', 'imported/1', 'pipe/1', 'pipe_bare/1',
                 'capture/0', 'apply_capture/0', 'delegated/1', 'run_again/1', 'after_scope/1', 'no_leak/1']:
        edge(name, 'run/1')
    edge('local_capture/0', 'local/1')
    edge('own/1', 'local/1')
    edge('default_call/0', 'defaults/2')
    edge('all_defaults/0', 'clauses/1')
    edge('bare/0', 'zero_local/0')
    edge('match_rhs/0', 'zero_local/0')
    edge('capture_shadow/1', 'zero_local/0')
    edge('branch_shadow/1', 'zero_local/0')
    edge('with_else/1', 'zero_local/0')
    edge('included/0', 'run/0', 'Sibling')
    for name in ['wrong_import/0', 'wrong_defaults/0', 'bad_module/1', 'bad_private/1',
                 'shadow/1', 'match_shadow/0', 'pattern/1', 'unknown_bare/0', 'no_quoted/0']:
        assert not targets(rows, name), (name, targets(rows, name))
    for name in ['no_alias/1', 'excluded/1', 'no_macro/1']:
        assert not targets(rows, name, 'Sibling'), (name, targets(rows, name, 'Sibling'))
    assert not any('phantom' in k for k in rows)
    # --callees identifies which module actually won, rather than merely agreeing on the short name.
    for caller, expected, rejected in [('remote/1', 'lib.ex:', 'other.ex:'), ('scoped/1', 'other.ex:', 'lib.ex:'),
                                       ('nested/1', 'apps/client/main.ex:', 'lib.ex:')]:
        output = ET.fromstring(run('--callees=Client::' + caller, '--no-cache'))
        paths = [s.get('p') for s in output.iter('s')]
        assert paths and all(p.startswith(expected) and not p.startswith(rejected) for p in paths), (caller, paths)
    work_uses = ET.fromstring(run('--uses=Real.Work::run/1', '--no-cache'))
    for caller in ['branch_alias/1', 'branch_import/1']:
        assert any(u.get('in_id', '').endswith('::' + caller) for u in work_uses.iter('u')), caller + ': branch scope leaked into else'
    uses = ET.fromstring(run('--uses=Real.Work::defaults/2', '--no-cache'))
    assert any(u.get('in_id', '').endswith('::default_call/0') for u in uses.iter('u'))
    attrs = ET.fromstring(run('--uses=Contracts::@limit', '--no-cache'))
    assert any(u.get('role') == 'read' for u in attrs.iter('u'))
    request = {'jsonrpc': '2.0', 'id': 2, 'method': 'tools/call', 'params': {'name': 'uses', 'arguments':
               {'path': str(code), 'symbol': 'Real.Work::defaults/2'}}}
    messages = json.dumps({'jsonrpc': '2.0', 'id': 1, 'method': 'initialize'}) + '\n' + json.dumps(request) + '\n'
    reply = subprocess.check_output([sys.argv[1], '--mcp'], input=messages.encode(), env=env)
    reply = json.loads(reply.splitlines()[-1])
    mcp_uses = ET.fromstring(reply['result']['content'][0]['text'])
    assert [(u.get('p'), u.get('in_id')) for u in mcp_uses.iter('u')] == [(u.get('p'), u.get('in_id')) for u in uses.iter('u')]
    deps = run('--deps', '--no-cache').decode()
    assert 't="Real.Work"' in deps and 't="Real.Other"' in deps
    assert 't="Decoy"' not in deps, 'quoted alias leaked into dependencies'
    for _ in range(3):
        assert run() == cold, 'cold/warm output differs'
    before = (code / 'apps/client/main.ex').read_text()
    after = before.replace('def remote(x), do: W.run(x)', 'def remote(x), do: Outside.run(x)')
    assert before != after
    (code / 'apps/client/main.ex').write_text(after)
    rows = parse(run())
    assert not targets(rows, 'remote/1'), 'warm cache preserved an invalidated call'
    print('  PASS Elixir module/arity resolution, defaults, delegates, captures, lexical names, negatives and cache mutation')
PY
