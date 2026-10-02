## Python Rules

### Architecture & Dependencies

- **Dependency Injection over Singletons**: Inject dependencies via constructor (`__init__`). No singletons, no mutable module-level state.
- **Composition over inheritance**: Prefer composing objects. If a class needs behavior from another, inject it.
- **Protocols for abstractions**: Use `typing.Protocol` for interfaces. Avoid `ABC` unless you need shared implementation.
- **No premature abstraction**: No abstract layers until at least two concrete implementations justify it.
- **No god classes**: One clear responsibility per class. If >5-7 public methods, split it.
- **Functions over single-method classes**: A class with only one public method should be a plain function.

### Module Organization

- **One file, one responsibility**: Each module has a clear, singular purpose.
- **No `utils.py` dumping grounds**: Group utilities in domain-specific modules.
- **`__init__.py` is only for exports**: No logic, only re-exports and `__all__`.
- **No circular imports**: Refactor by extracting shared types or inverting dependencies.

### Type Hints & Data Validation

- **Type hints everywhere**: All parameters, return types, and class attributes must have annotations.
- **No `Any` escape hatch**: Use `Protocol` or `TypeVar` instead.
- **Pydantic for external data**: Use Pydantic models for configuration, API schemas, and data from outside the system.
- **Dataclasses for internal data**: Use `@dataclass` for internal value objects that don't need validation.
- **Modern typing syntax**: Prefer `str | None` over `Optional[str]`, `list[int]` over `List[int]`.

### Error Handling

- **Custom exceptions per domain**: Define specific exception classes (e.g., `DocumentNotFoundError`, `IndexError`). Never raise bare `Exception`.
- **No generic except clauses**: Never `except Exception as e` unless re-raising. Catch specific exceptions.
- **Never silently swallow errors**: No `except: pass`.
- **Fail fast**: Validate inputs at boundaries (tool entry, config load).

### Async

- **Consistent async stack**: The MCP server is async; keep the entire call chain async.
- **No `asyncio.run()` inside async code**: Never call from within an already-running event loop.
- **No blocking calls in async functions**: Use `asyncio.sleep()`, async libraries, or `run_in_executor()` for blocking operations.
- **Async context managers**: Use `async with` for resources (DB connections).

### Testing (pytest)

- **Dependencies are injectable**: All external dependencies (DB session, filesystem) must be injectable for testing.
- **No monkeypatching globals**: Mock via injection, not `unittest.mock.patch` at module level.
- **pytest over unittest**: Use fixtures, parametrize, and conftest.py.
- **Tests are isolated**: No test depends on filesystem, network, or another test's state. Use in-memory fakes.
- **Arrange-Act-Assert structure**: Every test clearly separates setup, execution, and verification.

### Naming & Style

- **No abbreviations**: `configuration` not `cfg`, `document` not `doc` (except in established terms like "docstring").
- **Google-style docstrings**: All public functions and classes have docstrings with Args, Returns, Raises.
- **Self-documenting code over comments**: Comments explain *why*, not *what*.
- **Private with single underscore**: `_prefix` for private members.
- **Constants in UPPER_SNAKE_CASE**: Module-level only. No mutable "constants".
- **Boolean parameters need keyword-only syntax**: `def process(data, *, verbose: bool = False)`

### Anti-Patterns to Avoid

- No `@staticmethod` abuse — non-instance methods should be module-level functions.
- No logic in `__init__.py` — only `__all__` and re-exports.
- No mutable default arguments — use `None` and create inside the function.
- No wildcard imports — always import explicitly.
- No `print()` for logging — use `logging` module.
- No hardcoded values — magic numbers, paths, etc. must be configuration or constants.

### Known TODOs

- MCP tools currently return `dict` — should return typed response models.
