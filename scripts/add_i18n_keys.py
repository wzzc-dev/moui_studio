#!/usr/bin/env python3
"""Incrementally add i18n keys to the generated MoonBit catalog.

`moon info` cannot regenerate `app/i18n_catalog_generated.mbt` here (the
catalog's canonical backend is native, and this repo's catalog is generated
by an external tool). This script performs the same insertion the generator
would: keys are placed in the order they appear in the source JSON, using
the same line-folding rule as the generated file.

Usage:
  python3 scripts/add_i18n_keys.py <key>=<en> <key>=<zh-Hans> ...
"""

import collections
import json
import re
import sys

SOURCE_FILES = {
    "en": "app/i18n/en.json",
    "zh-Hans": "app/i18n/zh-Hans.json",
}
GENERATED = "app/i18n_catalog_generated.mbt"


def load_catalog(path):
    data = json.loads(
        open(path, encoding="utf-8").read(), object_pairs_hook=collections.OrderedDict
    )

    def find(node):
        if isinstance(node, dict):
            if any(key.startswith("app.plugin.ai") for key in node):
                return node
            for value in node.values():
                found = find(value)
                if found is not None:
                    return found
        return None

    return find(data)


def mbt_escape(text):
    return text.replace("\\", "\\\\").replace('"', '\\"')


def render_entry(key, value):
    """Render one catalog entry with the generator's folding rule."""
    text = f'GeneratedI18nMessage::Text("{mbt_escape(value)}")'
    single = f'      ("{key}", {text}),'
    if len(single) <= 80:
        return single
    inner = f'        {text},'
    if len(inner) <= 80:
        return f'      (\n        "{key}",\n{inner}\n      ),'
    content = f'          "{mbt_escape(value)}",'
    return f'      (\n        "{key}",\n        GeneratedI18nMessage::Text(\n{content}\n        ),\n      ),'


def parse_entries(lines):
    """Map catalog key -> (start line, end line) in the generated body."""
    entries = {}
    index = 0
    count = len(lines)
    while index < count:
        stripped = lines[index].strip()
        single = re.match(r'^\("([^"]+)",\s*GeneratedI18nMessage::', stripped)
        if single and stripped.endswith("),"):
            entries[single.group(1)] = (index, index + 1)
            index += 1
            continue
        if stripped == "(":
            start = index
            cursor = index + 1
            key = None
            while cursor < count:
                inner = lines[cursor].strip()
                key_match = re.match(r'^"([^"]+)",$', inner)
                if key_match and key is None:
                    key = key_match.group(1)
                if inner == "),":
                    break
                cursor += 1
            if key:
                entries[key] = (start, cursor + 1)
            index = cursor + 1
            continue
        index += 1
    return entries


def main():
    if len(sys.argv) < 2:
        print(__doc__)
        return 2
    additions = {}
    for argument in sys.argv[1:]:
        key, _, value = argument.partition("=")
        additions[key] = value
    if not additions:
        print("no keys given", file=sys.stderr)
        return 2

    generated_src = open(GENERATED, encoding="utf-8").read()
    for locale, source_path in SOURCE_FILES.items():
        catalog = load_catalog(source_path)
        for key, value in additions.items():
            catalog.setdefault(key, value)
        # Write the source JSON back (same key order as the catalog).
        raw = json.loads(
            open(source_path, encoding="utf-8").read(),
            object_pairs_hook=collections.OrderedDict,
        )

        def replace(node):
            if isinstance(node, dict):
                if any(key.startswith("app.plugin.ai") for key in node):
                    return catalog
                for key in list(node.keys()):
                    node[key] = replace(node[key])
            return node

        raw = replace(raw)
        open(source_path, "w", encoding="utf-8").write(
            json.dumps(raw, ensure_ascii=False, indent=2) + "\n"
        )
        # Insert into the generated catalog.
        order = list(catalog.keys())
        marker = f'locale: "{locale}",\n    messages: ['
        index = generated_src.index(marker)
        start = index + len(marker)
        end = generated_src.index("\n    ],", start)
        lines = generated_src[start:end].split("\n")
        entries = parse_entries(lines)
        pending = []
        for position, key in enumerate(order):
            if key in entries:
                continue
            anchor = None
            for later in order[position + 1 :]:
                if later in entries:
                    anchor = later
                    break
            if anchor:
                pending.append((key, anchor, catalog[key]))
            else:
                # No later key to anchor on → append at the end of the
                # section (the generator keeps source order, so a key added
                # last in the source JSON lands last here).
                pending.append((key, None, catalog[key]))
        # Insert anchored entries first (descending by anchor position), then
        # append the unanchored ones.
        anchored = [item for item in pending if item[1] is not None]
        unanchored = [item for item in pending if item[1] is None]
        for key, anchor, value in sorted(
            anchored, key=lambda item: entries[item[1]][0], reverse=True
        ):
            at = entries[anchor][0]
            lines[at:at] = render_entry(key, value).split("\n")
            entries = parse_entries(lines)
        for key, _anchor, value in unanchored:
            lines.append(render_entry(key, value))
            entries = parse_entries(lines)
        generated_src = generated_src[:start] + "\n".join(lines) + generated_src[end:]
    open(GENERATED, "w", encoding="utf-8").write(generated_src)
    print(f"added {len(additions)} key(s)")
    return 0


if __name__ == "__main__":
    sys.exit(main())
