#!/usr/bin/env python3
"""Generate Moongate's completion catalogs from a pinned Klipper revision."""

import argparse
import json
import re
import urllib.request
from pathlib import Path

ROOT = Path(__file__).parents[1]
DEFAULT_REF = "f0892d82b0f1c1228454f09eb508eddde2250f4b"

def fetch(ref: str, name: str) -> str:
    url = f"https://raw.githubusercontent.com/Klipper3d/klipper/{ref}/docs/{name}"
    with urllib.request.urlopen(url) as response:
        return response.read().decode()


def value_type(description: str) -> str:
    text = description.lower()
    if "true or false" in text:
        return "boolean"
    if "pin" in text and any(word in text for word in ("mcu", "gpio", "input", "output")):
        return "pin"
    if "comma separated" in text:
        return "list"
    if "integer" in text:
        return "integer"
    if any(word in text for word in ("float", "floating point", "in mm", "in degrees", "in seconds")):
        return "floating"
    if any(word in text for word in ("file name", "filename", "path to")):
        return "path"
    return "string"


def parse_config(markdown: str, ref: str) -> dict:
    lines = markdown.splitlines()
    sections = []
    heading = re.compile(r"^### `?\[([^]]+)]`?")
    option = re.compile(r"^#?([a-zA-Z][a-zA-Z0-9_<>-]*):")
    i = 0
    while i < len(lines):
        match = heading.match(lines[i])
        if not match:
            i += 1
            continue
        raw_name = match.group(1).strip()
        end = i + 1
        while end < len(lines) and not lines[end].startswith("### "):
            end += 1
        block = lines[i + 1:end]
        fenced = []
        in_fence = False
        for line in block:
            if line.startswith("```"):
                in_fence = not in_fence
            elif in_fence:
                fenced.append(line)
        example = next(
            (m.group(1).strip() for line in fenced
             if (m := re.match(r"^\[([^]]+)]$", line.strip()))),
            raw_name,
        )
        if raw_name == "include":
            i = end
            continue
        if example.startswith(f"{raw_name} "):
            name = f"{raw_name} <name>"
        elif raw_name == "stepper" and example.startswith("stepper_"):
            name = "stepper_<name>"
        else:
            name = re.sub(r"\s+my_[^ ]+$", " <name>", raw_name)
        options = []
        seen = set()
        for pos, line in enumerate(fenced):
            found = option.match(line.strip())
            if not found or found.group(1) in seen or "<" in found.group(1):
                continue
            key = found.group(1)
            seen.add(key)
            description = []
            for following in fenced[pos + 1:]:
                stripped = following.strip()
                if option.match(stripped) or stripped.startswith("["):
                    break
                if stripped.startswith("#"):
                    description.append(stripped.lstrip("# "))
                elif description and stripped:
                    break
            text = " ".join(description).strip()
            item = {
                "name": key,
                "type": "list" if key in {"probe_count", "mesh_pps"} else value_type(text),
            }
            if "one of" in text.lower():
                choices = re.findall(r"`([^`]+)`", text)
                if not choices:
                    listed = re.search(r"one of:\s*([^.]+)", text, re.IGNORECASE)
                    if listed:
                        choices = [
                            choice.strip()
                            for choice in re.split(r",|\bor\b", listed.group(1))
                            if choice.strip()
                        ]
                if choices:
                    item.update(type="enumeration", enum=choices)
            if text:
                item["description"] = text
            options.append(item)
        sections.append({"name": name, "repeatable": "<name>" in name, "options": options})
        i = end
    return {"formatVersion": 1, "upstreamCommit": ref, "sections": sections}


def parse_gcodes(markdown: str, ref: str) -> dict:
    lines = markdown.splitlines()
    commands = []
    seen = set()
    for i, line in enumerate(lines):
        match = re.match(r"^#### ([A-Z][A-Z0-9_]+)$", line)
        if not match or match.group(1) in seen:
            continue
        name = match.group(1)
        seen.add(name)
        body = []
        for following in lines[i + 1:]:
            if following.startswith("#### ") or following.startswith("### "):
                break
            body.append(following)
        text = " ".join(part.strip(" `") for part in body if part.strip())
        params = sorted(set(re.findall(r"\b([A-Z][A-Z0-9_]*)=", text)))
        commands.append({
            "name": name,
            "description": text[:500],
            "parameters": [{"name": param} for param in params],
        })
    return {"formatVersion": 1, "upstreamCommit": ref, "commands": commands}


def write(name: str, data: dict) -> None:
    path = ROOT / "mobile/assets/klipper" / name
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(data, ensure_ascii=False, indent=2) + "\n")


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--ref", default=DEFAULT_REF)
    args = parser.parse_args()
    write("config_schema.json", parse_config(fetch(args.ref, "Config_Reference.md"), args.ref))
    write("gcode_schema.json", parse_gcodes(fetch(args.ref, "G-Codes.md"), args.ref))


if __name__ == "__main__":
    main()
