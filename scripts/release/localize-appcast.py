#!/usr/bin/env python3
"""Keep the legacy feed and produce one-language feeds for new desktop clients."""
import argparse
import html
from pathlib import Path
import re
import xml.etree.ElementTree as ET

SPARKLE = "http://www.andymatuschak.org/xml-namespaces/sparkle"
LANGUAGES = {"ja": "日本語", "en": "English", "zh-Hans": "简体中文"}
FALLBACK = {
    "ja": "使いやすさの改善と不具合の修正を含むアップデートです。",
    "en": "This update includes usability improvements and bug fixes.",
    "zh-Hans": "本次更新包含使用体验改进和问题修复。",
}


def localized_notes(markdown, language):
    sections = re.split(r"(?m)^## (日本語|English|简体中文)\s*$", markdown)
    if len(sections) > 1:
        translations = dict(zip(sections[1::2], sections[2::2]))
        content = translations.get(LANGUAGES[language], FALLBACK[language])
    else:
        content = markdown if language == "ja" else FALLBACK[language]
    # Release notes use paragraphs, headings and bullets. Escape all source HTML.
    blocks = []
    for block in re.split(r"\n\s*\n", content.strip()):
        lines = block.strip().splitlines()
        if not lines:
            continue
        if lines[0].startswith("- "):
            bullets = []
            for line in lines:
                if line.startswith("- "):
                    bullets.append(line[2:])
                else:
                    bullets[-1] += " " + line.strip()
            blocks.append("<ul>" + "".join("<li>" + html.escape(line) + "</li>" for line in bullets) + "</ul>")
        elif lines[0].startswith("#"):
            blocks.append("<h3>" + html.escape(lines[0].lstrip("# ")) + "</h3>")
        else:
            blocks.append("<p>" + html.escape(" ".join(lines)) + "</p>")
    return '<html lang="' + language + '"><body>' + "".join(blocks) + "</body></html>"


def generate(feed, notes_directory, output_directory):
    ET.register_namespace("sparkle", SPARKLE)
    ET.register_namespace("dc", "http://purl.org/dc/elements/1.1/")
    for language in LANGUAGES:
        tree = ET.parse(feed)
        for item in tree.findall("./channel/item"):
            version = item.findtext("{" + SPARKLE + "}shortVersionString")
            enclosure = item.find("enclosure")
            if version is None and enclosure is not None:
                version = enclosure.get("{" + SPARKLE + "}shortVersionString")
            source = notes_directory / ((version or "unknown") + ".md")
            markdown = source.read_text() if source.is_file() else FALLBACK[language]
            description = item.find("description")
            if description is None:
                description = ET.SubElement(item, "description")
            description.text = localized_notes(markdown, language)
            for link in list(item.findall("{" + SPARKLE + "}releaseNotesLink")):
                item.remove(link)
        output_directory.mkdir(parents=True, exist_ok=True)
        tree.write(output_directory / ("appcast-" + language + ".xml"), encoding="utf-8", xml_declaration=True)


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("feed", type=Path)
    parser.add_argument("notes_directory", type=Path)
    parser.add_argument("output_directory", type=Path)
    args = parser.parse_args()
    generate(args.feed, args.notes_directory, args.output_directory)
