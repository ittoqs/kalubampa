use scraper::{Html, Selector};
use serde::{Deserialize, Serialize};
use std::collections::HashMap;
use std::ffi::{CStr, CString};
use std::os::raw::c_char;

#[derive(Deserialize, Debug)]
pub struct ExtractionSchema {
    pub container: Option<String>,
    pub fields: HashMap<String, String>,
}

unsafe fn c_ptr_to_str<'a>(ptr: *const c_char) -> Option<&'a str> {
    if ptr.is_null() {
        return None;
    }
    CStr::from_ptr(ptr).to_str().ok()
}

fn string_to_c_ptr(s: String) -> *mut c_char {
    CString::new(s).unwrap_or_else(|_| CString::new("{}").unwrap()).into_raw()
}

fn extract_text(document: &Html, selector_str: &str) -> Option<String> {
    let selector = Selector::parse(selector_str).ok()?;
    document
        .select(&selector)
        .next()
        .map(|el| el.text().collect::<Vec<_>>().join(" ").trim().to_string())
        .filter(|s| !s.is_empty())
}

fn extract_attr(document: &Html, selector_str: &str, attr: &str) -> Option<String> {
    let selector = Selector::parse(selector_str).ok()?;
    document
        .select(&selector)
        .next()
        .and_then(|el| el.value().attr(attr))
        .map(|s| s.trim().to_string())
        .filter(|s| !s.is_empty())
}

fn extract_with_schema(document: &Html, fields: &HashMap<String, String>) -> serde_json::Value {
    let mut result = serde_json::Map::new();

    for (field_name, selector_str) in fields {
        let (actual_selector, attr) = if let Some(idx) = selector_str.find('@') {
            (&selector_str[..idx], Some(&selector_str[idx + 1..]))
        } else {
            (selector_str.as_str(), None)
        };

        let extracted_value = if let Some(attr_name) = attr {
            extract_attr(document, actual_selector, attr_name)
        } else {
            extract_text(document, actual_selector)
                .or_else(|| extract_attr(document, actual_selector, "content"))
                .or_else(|| extract_attr(document, actual_selector, "src"))
                .or_else(|| extract_attr(document, actual_selector, "href"))
        };

        let val = extracted_value.unwrap_or_else(|| "N/A".to_string());
        result.insert(field_name.clone(), serde_json::Value::String(val));
    }

    serde_json::Value::Object(result)
}

#[no_mangle]
pub extern "C" fn extract_entities(
    raw_html: *const c_char,
    schema_json: *const c_char,
) -> *mut c_char {
    let result = std::panic::catch_unwind(|| {
        if raw_html.is_null() || schema_json.is_null() {
            return string_to_c_ptr(r#"{"error": "Input is null"}"#.to_string());
        }

        let html_str = match unsafe { c_ptr_to_str(raw_html) } {
            Some(s) => s,
            None => return string_to_c_ptr(r#"{"error": "Invalid UTF-8 HTML"}"#.to_string()),
        };

        let schema_str = match unsafe { c_ptr_to_str(schema_json) } {
            Some(s) => s,
            None => return string_to_c_ptr(r#"{"error": "Invalid UTF-8 Schema"}"#.to_string()),
        };

        let schema: ExtractionSchema = match serde_json::from_str(schema_str) {
            Ok(s) => s,
            Err(e) => {
                return string_to_c_ptr(format!(r#"{{"error": "Invalid JSON Schema: {}"}}"#, e))
            }
        };

        let document = Html::parse_document(html_str);

        if let Some(container_sel) = schema.container {
            let container_selector = match Selector::parse(&container_sel) {
                Ok(s) => s,
                Err(_) => {
                    return string_to_c_ptr(format!(
                        r#"{{"error": "Invalid container selector: {}"}}"#,
                        container_sel
                    ))
                }
            };

            let mut entities = Vec::new();
            for element in document.select(&container_selector) {
                let fragment_html = element.html();
                let fragment = Html::parse_fragment(&fragment_html);
                entities.push(extract_with_schema(&fragment, &schema.fields));
            }

            let json_result = serde_json::to_string(&entities).unwrap_or_else(|_| "[]".to_string());
            string_to_c_ptr(json_result)
        } else {
            let entity = extract_with_schema(&document, &schema.fields);
            let json_result = serde_json::to_string(&[entity]).unwrap_or_else(|_| "[]".to_string());
            string_to_c_ptr(json_result)
        }
    });

    result.unwrap_or_else(|_| {
        string_to_c_ptr(r#"{"error": "Internal panic caught by Shield"}"#.to_string())
    })
}

#[no_mangle]
pub extern "C" fn free_json_string(ptr: *mut c_char) {
    if !ptr.is_null() {
        unsafe {
            let _ = CString::from_raw(ptr);
        }
    }
}

#[no_mangle]
pub extern "C" fn parser_version() -> *mut c_char {
    string_to_c_ptr("kalubampa-shield/1.0.0".to_string())
}

#[cfg(test)]
mod tests {
    use super::*;

    fn with_c_string<F, R>(s: &str, f: F) -> R
    where
        F: FnOnce(*const c_char) -> R,
    {
        let c = CString::new(s).unwrap();
        f(c.as_ptr())
    }

    unsafe fn read_field(ptr: *mut c_char) -> String {
        if ptr.is_null() {
            return "NULL".to_string();
        }
        CStr::from_ptr(ptr).to_str().unwrap_or("INVALID_UTF8").to_string()
    }

    #[test]
    fn test_extract_entities_job() {
        let html = r#"
            <html><body>
                <div class="job-card">
                    <h1 class="job-title">Software Engineer</h1>
                    <span class="salary">$100,000</span>
                    <a class="apply-link" href="/apply/123">Apply Here</a>
                </div>
            </body></html>
        "#;

        let schema = r#"{
            "container": ".job-card",
            "fields": {
                "title": ".job-title",
                "salary": ".salary",
                "apply_url": ".apply-link@href"
            }
        }"#;

        with_c_string(html, |c_html| {
            with_c_string(schema, |c_schema| {
                let result_ptr = extract_entities(c_html, c_schema);
                assert!(!result_ptr.is_null());

                unsafe {
                    let json_str = read_field(result_ptr);
                    assert!(json_str.contains("Software Engineer"));
                    assert!(json_str.contains("$100,000"));
                    assert!(json_str.contains("/apply/123"));

                    let parsed: Vec<serde_json::Value> = serde_json::from_str(&json_str).unwrap();
                    assert_eq!(parsed.len(), 1);
                    assert_eq!(parsed[0]["title"], "Software Engineer");
                    assert_eq!(parsed[0]["salary"], "$100,000");
                    assert_eq!(parsed[0]["apply_url"], "/apply/123");
                }

                free_json_string(result_ptr);
            });
        });
    }
}
