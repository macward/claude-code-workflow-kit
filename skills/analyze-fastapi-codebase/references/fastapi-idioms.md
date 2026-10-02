# Idiomatic FastAPI / Python antipatterns

This is targeted reading: static tools don't detect it. Each block has a starting `grep`, but confirm by reading the code; the grep only takes you to the spot.

## 1. Business logic in endpoints
The endpoint should orchestrate (parse request → call service → return response), not contain business rules, queries or calculations.

```bash
# Long endpoints = suspects. Look at the body of each @router/@app:
grep -rn "@\(app\|router\)\.\(get\|post\|put\|patch\|delete\)" <src>
```
Bad sign: a 60-line `@router.post` function that opens a DB session, validates by hand, runs the `select`, transforms and handles errors. It should delegate to a service/repository layer. Sign a service layer is missing: the same query or rule repeated across several endpoints.

## 2. DB session management
The session should be injected via `Depends` and close itself; never instantiated inside the handler.

```bash
grep -rn "SessionLocal()\|Session()\|sessionmaker" <src>
grep -rn "def get_db\|async def get_db\|Depends(get_db" <src>
```
Bad sign: `db = SessionLocal()` inside an endpoint with no `try/finally` or dependency → connection leak. Bad sign: inconsistent commit/rollback across handlers. Healthy: a `get_db` dependency with `yield` and guaranteed close, injected the same way everywhere.

## 3. async that blocks the event loop
An `async def` doing synchronous I/O (requests, sync DB driver, `time.sleep`, blocking file read) freezes the whole worker.

```bash
grep -rn "async def" <src> | head -40   # then inspect each one
grep -rn "requests\.\|time\.sleep\|\.read()\|open(" <src>
```
Bad sign: `async def` with `requests.get(...)` or a sync ORM inside, without `run_in_threadpool`. Consistency: either the whole stack is async (async driver, async repos) or it's sync with plain `def` endpoints that FastAPI runs in a threadpool. The dangerous part is mixing: `async def` + blocking client.

## 4. Pydantic / validation at the boundary
Validation lives in the request's Pydantic models, not by hand inside the handler.

```bash
grep -rn "BaseModel\|response_model=" <src>
grep -rn "raise HTTPException" <src> | wc -l   # many = scattered manual validation
```
Bad sign: `if not x: raise HTTPException(400)` checks that a Pydantic validator would do declaratively. Bad sign: endpoints returning raw `dict` instead of `response_model` → no contract and no guaranteed serialization. Pydantic v1/v2 mix (`@validator` and `@field_validator` side by side) = migration debt.

## 5. Depends and configuration
```bash
grep -rn "os.environ\|os.getenv" <src>      # scattered config
grep -rn "BaseSettings\|Settings(" <src>     # centralized config (good)
```
Bad sign: `os.getenv` sprinkled across the code instead of a single injected `Settings(BaseSettings)`. Bad sign: heavy dependencies (creating an HTTP client, opening a connection) not cached, rebuilt per request when they should live once via `lru_cache` or lifespan.

## 6. SQLAlchemy antipatterns
```bash
grep -rn "\.query(\|session.execute\|text(" <src>
grep -rn "for .* in .*:\s*$" <src>   # possible N+1 when iterating and querying inside
```
Bad sign: N+1 (a loop firing one query per iteration instead of a join/`selectinload`). Bad sign: raw SQL with f-strings (`text(f"... {user_input}")`) → injection. Bad sign: lazy relationships loaded outside the session → latent `DetachedInstanceError`. Mixing the 1.x (`.query()`) and 2.0 (`select()`) APIs without a rule.

## 7. Error and exception handling
```bash
grep -rn "except:" <src>           # bare except = severe
grep -rn "except Exception" <src>  # too broad
grep -rn "pass$" <src>             # swallowed errors
```
Bad sign: `except Exception: pass` hiding failures. Healthy: domain exceptions + a FastAPI `exception_handler` that maps them to HTTP responses, instead of `HTTPException` scattered through business logic (couples the domain to HTTP transport).

## 8. Project structure
A healthy, consistent layout by feature or by layer. Compare against what the community recommends (domain-based structure for large projects). Bad sign: a monolithic 1500-line `main.py` or `models.py`; folders each feature organized differently; domain logic importing from `api/`.

## 9. Tests
```bash
find . -path "*/tests/*" -name "*.py" | wc -l
grep -rn "TestClient\|AsyncClient\|httpx" tests/ 2>/dev/null | head
```
Bad sign: only happy-path endpoint tests, zero tests of isolated business logic (a symptom that logic is glued to the endpoint and can't be tested without HTTP). Healthy: logic in services testable without `TestClient`, plus a handful of integration tests per endpoint.

---
When reporting, distinguish "this is a latent bug" (Fact: N+1, bare except, unclosed session) from "this is a questionable design decision" (Opinion: missing service layer, scattered config). The former gets severity by risk; the latter is argued and left to the user's judgment.
