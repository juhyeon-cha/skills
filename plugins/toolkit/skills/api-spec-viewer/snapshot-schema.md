# Snapshot JSON schema

The shape of the JSON that `extract-spring.py` and `extract-fastapi.py` emit. **Both extractors emit
the same shape** — the shape is the interface of the framework-neutral diff. What differs by
framework is the values; the keys do not.

Every value is **the string as written in the source**. Types are neither interpreted nor
normalised — `List<Pet>` · `ItemPublic` · `str | None` are carried in the notation their framework
used.

## Top-level keys (all four always present)

| Key | Type | Content |
|---|---|---|
| `framework` | string | Extractor identifier. `"spring"` or `"fastapi"` |
| `endpoints` | array | The endpoint list. **One or more** — with zero, the extractor does not exit 0 |
| `models` | array | The structures used in requests and responses. **One or more** |
| `enums` | array | The enum list. **May be empty** |

## Keys of `endpoints[]` (all four always present)

| Key | Type | Content |
|---|---|---|
| `method` | string | The HTTP method in upper case. Spring: `GET` · `POST` · `PUT` · `PATCH` · `DELETE`; FastAPI can add `HEAD` · `OPTIONS` · `TRACE` |
| `path` | string | The path with its prefix joined on. Always starts with `/`; a trailing `/` is stripped |
| `request` | string \| null | The request body type name. `null` when there is no body |
| `response` | string \| null | The response type name. `null` when it cannot be known |

- The prefix of `path`: Spring, the class-level `@RequestMapping`; FastAPI, `APIRouter(prefix=...)`.
- Where `request` comes from: Spring, the parameter annotated `@RequestBody`; FastAPI, the parameter
  whose type is in `models`.
- Where `response` comes from: Spring, the method's return type (`void` is carried as it is);
  FastAPI, `response_model=`, or the function's return annotation when that is absent.

## Keys of `models[]`

| Key | Type | Content |
|---|---|---|
| `name` | string | The declared name |
| `fields` | array | A list of `{"name": string, "type": string}`. Empty when there are no fields |

What counts: Spring, `record` types and `@Entity` classes; FastAPI, every class that inherits from
`SQLModel` or `BaseModel`.

**`name` is not unique.** A multi-module repo declares a DTO of the same name once per module (for
example `PetDetails` in the Spring sample `check.sh` fetches). When the fields differ, both are
carried as separate items.

## Keys of `enums[]`

| Key | Type | Content |
|---|---|---|
| `name` | string | The declared name |
| `values` | array | The list of constant names, as strings |

## Order and determinism

Two runs over the same input are **byte-identical.** Each of the three lists is sorted by the
sorted JSON representation of its items, with duplicates removed. Top-level keys are sorted too. No
file paths, timestamps or absolute paths are carried — with them, the diff would shift whenever the
run location changed.

## Example

```json
{
  "framework": "spring",
  "endpoints": [
    { "method": "POST", "path": "/owners/{ownerId}/pets", "request": "PetRequest", "response": "Pet" }
  ],
  "models": [
    { "name": "PetType", "fields": [ { "name": "name", "type": "String" } ] }
  ],
  "enums": []
}
```

Whether a file satisfies this schema is asserted by `check.sh` in the same folder.
