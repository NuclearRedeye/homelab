# Turns one CRD into a kubeconform schema per version, as {file, schema}.
# Mirrors kubeconform's scripts/openapi2jsonschema.py.

# Objects that list their fields reject any others, so misspelt fields fail.
# A properties map holds field names, not a schema, so a field that is itself
# called "properties" (as in Piraeus) isn't mistaken for one. See #132.
def deny_unknown_fields:
  if type == "object" then
    (if has("properties") and (has("additionalProperties") | not)
     then .additionalProperties = false else . end)
    | with_entries(
        if .key == "properties" and (.value | type) == "object"
        then .value |= map_values(deny_unknown_fields)
        else .value |= deny_unknown_fields end
      )
  elif type == "array" then map(deny_unknown_fields)
  else . end;

# JSON Schema has no int-or-string format, so spell it out.
def int_or_string:
  walk(
    if type == "object" and .format == "int-or-string"
    then {oneOf: [{type: "string"}, {type: "integer"}]}
    else . end
  );

# The root stays open, as apiVersion, kind and metadata are checked elsewhere.
def keep_root_open($original):
  if $original | has("additionalProperties") then . else del(.additionalProperties) end;

.spec as $crd
| $crd.versions[]
| select(.schema.openAPIV3Schema)
| .schema.openAPIV3Schema as $schema
| {
    file: "\($crd.group)/\($crd.names.kind | ascii_downcase)_\(.name).json",
    schema: ($schema | deny_unknown_fields | int_or_string | keep_root_open($schema))
  }
