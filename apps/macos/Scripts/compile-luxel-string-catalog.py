import json
import pathlib
import sys

catalog_path = pathlib.Path(sys.argv[1])
output_roots = [pathlib.Path(path) for path in sys.argv[2:] if pathlib.Path(path).exists()]

with catalog_path.open(encoding="utf-8") as catalog_file:
    catalog = json.load(catalog_file)

locales = sorted({
    locale
    for entry in catalog.get("strings", {}).values()
    for locale in entry.get("localizations", {})
})


def escaped(value):
    return (
        value.replace("\\", "\\\\")
        .replace('"', '\\"')
        .replace("\n", "\\n")
    )


for output_root in output_roots:
    for locale in locales:
        lproj = output_root / f"{locale}.lproj"
        lproj.mkdir(parents=True, exist_ok=True)
        strings_file = lproj / "Localizable.strings"
        with strings_file.open("w", encoding="utf-8") as output:
            for key, entry in sorted(catalog.get("strings", {}).items()):
                unit = entry.get("localizations", {}).get(locale, {}).get("stringUnit", {})
                value = unit.get("value")
                if value:
                    output.write(f'"{escaped(key)}" = "{escaped(value)}";\n')
