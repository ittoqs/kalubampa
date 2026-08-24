#ifndef RUST_PARSER_H
#define RUST_PARSER_H

#ifdef __cplusplus
extern "C" {
#endif

char* extract_entities(const char *raw_html, const char *schema_json);
void free_json_string(char *ptr);
char* parser_version(void);

#ifdef __cplusplus
}
#endif

#endif
