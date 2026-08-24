# Kalubampa FFI Contract

This document describes the Foreign Function Interface (FFI) contract between the Crystal Worker (Muscle) and the Rust Parser (Shield).

## Overview

The Crystal worker delegates HTML parsing and data extraction to a compiled Rust shared library (`librust_parser.a` statically or `.so` dynamically). The interaction is performed entirely via C-ABI compatible functions.

## Functions

### `parser_version`

```c
const char* parser_version();
```
- **Description:** Returns the version string of the Rust parser.
- **Memory Management:** The returned string is allocated by Rust. The caller MUST free it using `free_json_string`.

### `parse_html`

```c
const char* parse_html(const char* html_content, const char* schema_json);
```
- **Description:** Takes raw HTML content and a JSON schema string. Extracts data according to the CSS selectors defined in the schema.
- **Arguments:**
  - `html_content`: Null-terminated string containing the HTML to parse.
  - `schema_json`: Null-terminated JSON string describing what to extract. Example: `{"fields": {"title": ".title-class"}}`
- **Returns:** A null-terminated JSON string containing the extracted data, or an error JSON object.
- **Memory Management:** The returned string is allocated by Rust. The caller MUST free it using `free_json_string`.

### `free_json_string`

```c
void free_json_string(char* s);
```
- **Description:** Frees memory allocated by the Rust parser.
- **Arguments:**
  - `s`: The pointer previously returned by `parser_version` or `parse_html`.
- **Memory Management:** MUST be called exactly once per returned string to prevent memory leaks. Calling it on a null pointer is a no-op. Calling it twice will cause a double-free (segmentation fault).

## Thread Safety

The Rust parser functions are completely thread-safe and hold no global state. They can be called concurrently from multiple Crystal Fibers.
