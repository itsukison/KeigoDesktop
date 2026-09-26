import importlib.util
from pathlib import Path
import tempfile
import unittest
import xml.etree.ElementTree as ET

spec = importlib.util.spec_from_file_location("localize", Path(__file__).with_name("localize-appcast.py"))
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)


class LocalizedAppcastTests(unittest.TestCase):
    def test_languages_are_isolated_and_html_is_escaped(self):
        notes = "# App\n\n## 日本語\n\n日本語の説明\n\n## English\n\nEnglish description <script>\n\n## 简体中文\n\n中文说明"
        english = module.localized_notes(notes, "en")
        self.assertIn("English description &lt;script&gt;", english)
        self.assertNotIn("日本語の説明", english)
        self.assertNotIn("中文说明", english)
        self.assertIn("中文说明", module.localized_notes(notes, "zh-Hans"))

    def test_signed_enclosure_is_unchanged_and_legacy_feed_survives(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            feed = root / "appcast.xml"
            original = '<rss xmlns:sparkle="' + module.SPARKLE + '"><channel><item><sparkle:shortVersionString>1.0</sparkle:shortVersionString><description>All languages</description><enclosure url="https://example.com/app.zip" length="123" sparkle:edSignature="signed" sparkle:version="42"/></item></channel></rss>'
            feed.write_text(original)
            (root / "1.0.md").write_text("## 日本語\n\n日本語\n\n## English\n\nEnglish\n\n## 简体中文\n\n中文")
            module.generate(feed, root, root)
            self.assertEqual(feed.read_text(), original)
            expected = ET.fromstring(original).find("./channel/item/enclosure").attrib
            for language in module.LANGUAGES:
                item = ET.parse(root / ("appcast-" + language + ".xml")).find("./channel/item")
                self.assertEqual(item.find("enclosure").attrib, expected)
                self.assertIn('lang="' + language + '"', item.findtext("description"))

    def test_old_japanese_only_release_has_localized_fallback(self):
        self.assertIn("usability improvements", module.localized_notes("# 更新\n\n改善しました", "en"))
        self.assertNotIn("改善しました", module.localized_notes("# 更新\n\n改善しました", "en"))

    def test_wrapped_bullets_remain_one_list_item(self):
        rendered = module.localized_notes("## English\n\n- First line\n  continues here\n- Second point", "en")
        self.assertIn("<li>First line continues here</li>", rendered)
        self.assertEqual(rendered.count("<li>"), 2)


if __name__ == "__main__":
    unittest.main()
